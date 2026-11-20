import Foundation
import HealthKit

/// Reads cycle history from Apple Health: everything Clue, Flo, Natural
/// Cycles or Apple's own Cycle Tracking has saved there. Read-only. After
/// the first import it keeps going: each time Clutch opens it pulls in only
/// what's new since last time (an anchored query per type), so she can keep
/// logging in her old app while she moves over.
@MainActor
final class HealthSync: ObservableObject {
    static let shared = HealthSync()

    private static let connectedKey = "health.connected"
    private static let anchorPrefix = "health.anchor."

    @Published private(set) var isConnected = UserDefaults.standard.bool(forKey: HealthSync.connectedKey)
    @Published private(set) var isSyncing = false

    private let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Health's symptom types and the Clutch symptom each one becomes.
    nonisolated static let symptomTypes: [(HKCategoryTypeIdentifier, String)] = [
        (.abdominalCramps, "cramps"),
        (.bloating, "bloating"),
        (.headache, "headache"),
        (.sleepChanges, "poor-sleep"),
        (.appetiteChanges, "cravings"),
    ]

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKCategoryType(.menstrualFlow)]
        for (id, _) in Self.symptomTypes { types.insert(HKCategoryType(id)) }
        return types
    }

    /// Asks once, then imports everything. Returns how many days changed.
    /// Health never says whether reading was allowed, so a refusal just
    /// looks like no data.
    func connect() async throws -> Int {
        guard Self.isAvailable else { return 0 }
        try await store.requestAuthorization(toShare: [], read: readTypes)
        UserDefaults.standard.set(true, forKey: Self.connectedKey)
        isConnected = true
        return try await sync()
    }

    func disconnect() {
        UserDefaults.standard.set(false, forKey: Self.connectedKey)
        for type in readTypes { UserDefaults.standard.removeObject(forKey: Self.anchorPrefix + type.identifier) }
        isConnected = false
    }

    /// On every app open, quietly.
    func syncIfConnected() {
        guard isConnected, !isSyncing else { return }
        Task { _ = try? await sync() }
    }

    @discardableResult
    func sync() async throws -> Int {
        guard Self.isAvailable else { return 0 }
        isSyncing = true
        defer { isSyncing = false }

        var days: [ImportedDay] = []
        for case let type as HKCategoryType in readTypes {
            let samples = try await newSamples(of: type)
            days += samples.compactMap(Self.day(from:))
        }
        guard !days.isEmpty else { return 0 }
        return PeriodImport.merge(days, source: .health)
    }

    private func newSamples(of type: HKCategoryType) async throws -> [HKCategorySample] {
        let key = Self.anchorPrefix + type.identifier
        let anchor = UserDefaults.standard.data(forKey: key)
            .flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0) }
        let query = HKAnchoredObjectQueryDescriptor(predicates: [.categorySample(type: type)], anchor: anchor)
        let result = try await query.result(for: store)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: result.newAnchor, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: key)
        }
        return result.addedSamples
    }

    /// One Health sample as a day of history.
    nonisolated static func day(from sample: HKCategorySample) -> ImportedDay? {
        let date = Calendar.current.startOfDay(for: sample.startDate)
        if sample.categoryType.identifier == HKCategoryTypeIdentifier.menstrualFlow.rawValue {
            guard let flow = flow(fromHealthValue: sample.value) else { return nil }
            let start = (sample.metadata?[HKMetadataKeyMenstrualCycleStart] as? Bool) ?? false
            return ImportedDay(date: date, flow: flow, periodStart: start && flow.isBleeding)
        }
        // Appetite counts only when it went up; the rest are "not present"
        // or a severity, where 1 means not present for both.
        if sample.categoryType.identifier == HKCategoryTypeIdentifier.appetiteChanges.rawValue {
            guard sample.value == HKCategoryValueAppetiteChanges.increased.rawValue else { return nil }
        } else if sample.value == HKCategoryValueSeverity.notPresent.rawValue {
            return nil
        }
        guard let symptom = symptomTypes.first(where: { $0.0.rawValue == sample.categoryType.identifier })?.1 else { return nil }
        return ImportedDay(date: date, symptoms: [symptom])
    }

    nonisolated static func flow(fromHealthValue value: Int) -> Flow? {
        guard let reading = HKCategoryValueMenstrualFlow(rawValue: value) else { return nil }
        switch reading {
        case .light: return .light
        case .medium, .unspecified: return .medium
        case .heavy: return .heavy
        case .none: return .noFlow
        @unknown default: return nil
        }
    }
}
