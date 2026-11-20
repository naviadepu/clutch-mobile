import Foundation

/// Where a widget tap or notification wants to take her. The Garden picks
/// up `pending` and opens the matching screen.
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    enum Route: String, Identifiable {
        case today, tracker, cloud, windDown = "wind-down", journal, request, importData = "import", profile
        var id: String { rawValue }
    }

    @Published var pending: Route?
    /// Changes when the app should start over from the first screen
    /// (after "Delete my data").
    @Published private(set) var session = UUID()

    func restart() {
        pending = nil
        session = UUID()
    }

    /// `clutch://hard-time` and friends.
    func handle(_ url: URL) {
        guard url.scheme == "clutch" else { return }
        // Links from widgets placed before hard-time and cravings were
        // retired still land somewhere sensible.
        let aliases = ["hard-time": "wind-down", "cravings": "today"]
        let host = url.host ?? ""
        guard let route = Route(rawValue: aliases[host] ?? host) else { return }
        pending = route
    }
}
