import Foundation

/// One day's worth of Garden activity. `seed` is what makes the garden
/// deterministic — flower shape, position and sway all derive from it, so
/// the same day always renders the same garden instead of reshuffling on
/// every redraw.
struct DayLog: Codable {
    let date: Date
    var symptoms: [String] = []
    var skipped: [String] = []
    let seed: Int
}

/// A tiny local store for `DayLog`s, keyed by calendar day. This is a
/// placeholder for the real backend (Firestore, matching the rest of the
/// app) — swapping the storage layer later shouldn't need to touch
/// `GardenModel`, since it only talks to this type.
enum DayLogStore {
    private static let defaults = UserDefaults.standard

    private static func key(for date: Date) -> String {
        "garden.log." + dayKey(for: date)
    }

    static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    static func load(for date: Date) -> DayLog? {
        guard let data = defaults.data(forKey: key(for: date)) else { return nil }
        return try? JSONDecoder().decode(DayLog.self, from: data)
    }

    static func save(_ log: DayLog) {
        guard let data = try? JSONEncoder().encode(log) else { return }
        defaults.set(data, forKey: key(for: log.date))
    }

    /// Loads or mints today's log, so the seed (and therefore the garden's
    /// look) is stable across app launches for the same day.
    static func loadOrCreate(for date: Date) -> DayLog {
        if let existing = load(for: date) { return existing }
        let fresh = DayLog(date: date, seed: Int.random(in: 0...Int.max / 2))
        save(fresh)
        return fresh
    }
}

/// Deterministic RNG (SplitMix64) so a stored `seed` always reproduces the
/// same sequence of "random" flower values.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: Int) {
        state = UInt64(bitPattern: Int64(seed)) &+ 0x9E3779B97F4A7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
