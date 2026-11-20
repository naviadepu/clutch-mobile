import FirebaseAuth
import FirebaseFirestore
import Foundation

/// "Report empty" shared with everyone: one person's report reaches every
/// phone's map. A spot only shows as empty once two different people have
/// said so since it was last seen stocked, so one prank can't hide it.
/// Anonymous sign-in, no names, nothing about her cycle. If the backend
/// can't be reached, the screen falls back to the bundled list.
@MainActor
final class SharedSpotReports: ObservableObject {
    struct Community: Equatable {
        var status: ProductLocation.StockStatus
        var lastReported: Date
    }

    /// How far back reports count.
    static let window: TimeInterval = 3 * 24 * 3600
    static let collection = "spotReports"

    @Published private(set) var byLocation: [String: Community] = [:]
    private var listener: ListenerRegistration?

    func start() {
        guard listener == nil else { return }
        Task {
            guard (try? await Self.signIn()) != nil else { return }
            let since = Timestamp(date: Date.now.addingTimeInterval(-Self.window))
            listener = Firestore.firestore().collection(Self.collection)
                .whereField("at", isGreaterThan: since)
                .addSnapshotListener { [weak self] snapshot, _ in
                    guard let docs = snapshot?.documents else { return }
                    let reports = docs.compactMap(Report.init)
                    Task { @MainActor in self?.byLocation = Self.aggregate(reports) }
                }
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    /// Fire and forget; the local copy is already saved by `SpotReports`.
    static func report(_ locationID: String, kind: Report.Kind) {
        Task {
            guard let uid = try? await signIn() else { return }
            try? await Firestore.firestore().collection(collection).addDocument(data: [
                "locationId": locationID,
                "kind": kind.rawValue,
                "uid": uid,
                "at": FieldValue.serverTimestamp(),
            ])
        }
    }

    /// The bundled spot, with what the community says on top.
    func apply(to location: ProductLocation) -> ProductLocation {
        guard let community = byLocation[location.id] else { return location }
        var copy = location
        copy.stockStatus = community.status
        copy.lastReported = community.lastReported
        return copy
    }

    struct Report: Equatable {
        enum Kind: String { case empty, stocked }
        let locationID: String
        let kind: Kind
        let uid: String
        let at: Date

        init(locationID: String, kind: Kind, uid: String, at: Date) {
            self.locationID = locationID
            self.kind = kind
            self.uid = uid
            self.at = at
        }

        init?(_ doc: QueryDocumentSnapshot) {
            let data = doc.data()
            guard let id = data["locationId"] as? String,
                  let kind = (data["kind"] as? String).flatMap(Kind.init),
                  let uid = data["uid"] as? String,
                  let at = (data["at"] as? Timestamp)?.dateValue() else { return nil }
            self.init(locationID: id, kind: kind, uid: uid, at: at)
        }
    }

    /// Per spot: after the latest "stocked", two or more people saying
    /// empty makes it empty; one makes it "running low" (unconfirmed).
    nonisolated static func aggregate(_ reports: [Report]) -> [String: Community] {
        var result: [String: Community] = [:]
        for (id, spotReports) in Dictionary(grouping: reports, by: \.locationID) {
            let sorted = spotReports.sorted { $0.at < $1.at }
            let lastStocked = sorted.last { $0.kind == .stocked }
            let emptySince = sorted.filter { $0.kind == .empty && $0.at > (lastStocked?.at ?? .distantPast) }
            let people = Set(emptySince.map(\.uid)).count
            let latest = sorted.last!.at
            if people >= 2 {
                result[id] = Community(status: .empty, lastReported: latest)
            } else if people == 1 {
                result[id] = Community(status: .low, lastReported: latest)
            } else if lastStocked != nil {
                result[id] = Community(status: .stocked, lastReported: latest)
            }
        }
        return result
    }

    private static func signIn() async throws -> String {
        if let user = Auth.auth().currentUser { return user.uid }
        return try await Auth.auth().signInAnonymously().user.uid
    }
}
