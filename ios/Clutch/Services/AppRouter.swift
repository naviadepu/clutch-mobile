import Foundation

/// Where a widget tap or notification wants to take her. The Garden picks
/// up `pending` and opens the matching screen.
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    enum Route: String, Identifiable {
        case today, tracker, cloud, hardTime = "hard-time", cravings, windDown = "wind-down", request, importData = "import"
        var id: String { rawValue }
    }

    @Published var pending: Route?

    /// `clutch://hard-time` and friends.
    func handle(_ url: URL) {
        guard url.scheme == "clutch", let route = Route(rawValue: url.host ?? "") else { return }
        pending = route
    }
}
