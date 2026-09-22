import Foundation

/// Someone said a spot was out of stock.
struct EmptyReport: Codable, Identifiable, Hashable {
    var id = UUID()
    let locationID: String
    let reportedAt: Date
}

/// Someone knows a spot the list doesn't have yet.
struct SpotSuggestion: Codable, Identifiable, Hashable {
    var id = UUID()
    let name: String
    let directions: String
    let suggestedAt: Date
}

/// Reports and suggestions, kept on the device. There's no backend yet, so
/// nothing leaves the phone — this is a holding pen for when there is one,
/// and the same shape should go up unchanged.
enum SpotReports {
    private static let defaults = UserDefaults.standard
    private static let emptyKey = "spots.emptyReports"
    private static let suggestionKey = "spots.suggestions"

    static func emptyReports() -> [EmptyReport] {
        read([EmptyReport].self, from: emptyKey)
    }

    static func suggestions() -> [SpotSuggestion] {
        read([SpotSuggestion].self, from: suggestionKey)
    }

    /// The most recent report for a spot, so a row can say it was just
    /// reported without waiting on a backend.
    static func lastEmptyReport(for locationID: String) -> Date? {
        emptyReports()
            .filter { $0.locationID == locationID }
            .map(\.reportedAt)
            .max()
    }

    static func reportEmpty(_ locationID: String, at date: Date = .now) {
        var all = emptyReports()
        all.append(EmptyReport(locationID: locationID, reportedAt: date))
        write(all, to: emptyKey)
    }

    static func suggest(name: String, directions: String, at date: Date = .now) {
        var all = suggestions()
        all.append(SpotSuggestion(name: name, directions: directions, suggestedAt: date))
        write(all, to: suggestionKey)
    }

    private static func read<T: Decodable>(_ type: T.Type, from key: String) -> T where T: ExpressibleByArrayLiteral {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(type, from: data)
        else { return [] }
        return decoded
    }

    private static func write<T: Encodable>(_ value: T, to key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
