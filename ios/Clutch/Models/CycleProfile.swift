import Foundation

/// What onboarding learns about the user's cycle. Every cycle answer is
/// optional — `nil` means "I don't remember" / "Not sure", and the typical
/// values below stand in until real periods get logged.
struct CycleProfile: Codable, Equatable {
    static let typicalCycleLength = 28
    static let typicalPeriodLength = 5

    var age = 22
    /// `nil` when she doesn't remember; she logs it when the next one starts.
    var lastPeriodStart: Date?
    /// First day of one period to the first day of the next.
    var cycleLength: Int?
    var periodLength: Int?
    var birthControl: BirthControl = .preferNotToSay

    var effectiveCycleLength: Int { cycleLength ?? Self.typicalCycleLength }
    var effectivePeriodLength: Int { periodLength ?? Self.typicalPeriodLength }

    /// Logging a period today either starts a new cycle — giving an exact
    /// start date, even after "I don't remember" — or continues the one
    /// already running. Returns the new start date, or `nil` if the current
    /// one still holds.
    static func newPeriodStart(
        loggedOn day: Date,
        yesterdayHadPeriod: Bool,
        currentStart: Date?,
        periodLength: Int,
        calendar: Calendar = .current
    ) -> Date? {
        let today = calendar.startOfDay(for: day)
        if yesterdayHadPeriod { return nil }
        if let currentStart {
            let start = calendar.startOfDay(for: currentStart)
            let daysIn = calendar.dateComponents([.day], from: start, to: today).day ?? .max
            // Still inside the period she already told us about (with a day
            // or two of slack for a longer-than-usual one).
            if daysIn >= 0 && daysIn < periodLength + 2 { return nil }
        }
        return today
    }

    private static let storageKey = "cycleProfile"

    static func load(from defaults: UserDefaults = .standard) -> CycleProfile? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(CycleProfile.self, from: data)
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

enum BirthControl: String, Codable, CaseIterable, Identifiable {
    case none
    case pillPatchOrRing
    case hormonalIUD
    case copperIUD
    case implantOrShot
    case other
    case preferNotToSay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "No"
        case .pillPatchOrRing: "The pill, patch, or ring"
        case .hormonalIUD: "Hormonal IUD"
        case .copperIUD: "Copper IUD"
        case .implantOrShot: "Implant or shot"
        case .other: "Something else"
        case .preferNotToSay: "Prefer not to say"
        }
    }

    /// How the cycle should be read: "Prefer not to say" counts as no birth
    /// control until she changes it.
    var effective: BirthControl {
        self == .preferNotToSay ? .none : self
    }
}
