import Foundation

// Shared by the app and the widget. The app works out where she is in her
// cycle and writes a small snapshot to the App Group; the widget reads it
// and picks what the cloud is doing at each hour.

enum ClutchShared {
    static let appGroup = "group.com.love.clutch"
    static let widgetKind = "CloudWidget"

    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }
}

/// How one day sits in her cycle, as far as the cloud cares.
struct CycleDayState: Codable, Equatable {
    enum Kind: String, Codable {
        case period, hard, beforePeriod, normal
    }

    var kind: Kind
    var cycleDay: Int?
    /// Days until the next period starts; nil when unknown or late.
    var daysUntilPeriod: Int?
}

/// What the app last knew, keyed by `yyyy-MM-dd`, from today forward.
struct CycleSnapshot: Codable, Equatable {
    var days: [String: CycleDayState] = [:]
    /// Days she has finished logging; the cloud gets a flower on those.
    var loggedDays: Set<String> = []
    /// Mood (1–5) she logged each day, so the cloud can react to it.
    var moods: [String: Int] = [:]

    private static let key = "cloud.snapshot"

    static func load(from defaults: UserDefaults = ClutchShared.defaults) -> CycleSnapshot {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(CycleSnapshot.self, from: data) else { return CycleSnapshot() }
        return snapshot
    }

    func save(to defaults: UserDefaults = ClutchShared.defaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func state(on date: Date) -> CycleDayState {
        days[Self.dayKey(for: date)] ?? CycleDayState(kind: .normal)
    }

    func logged(on date: Date) -> Bool { loggedDays.contains(Self.dayKey(for: date)) }

    func mood(on date: Date) -> Int? { moods[Self.dayKey(for: date)] }
}

/// Everything the cloud can be caught doing.
enum MascotScene: String, CaseIterable, Identifiable {
    // An ordinary day, by the clock.
    case breakfast, walk, picnic, study, fetch, dinner, journal, sleep
    // Days her cycle makes heavier.
    case packing, cozyTea, hotWaterNap, cuddle, drizzle

    var id: String { rawValue }

    enum Sky { case dawn, day, dusk, night }

    var sky: Sky {
        switch self {
        case .breakfast, .packing, .cozyTea: .dawn
        case .walk, .picnic, .study, .hotWaterNap, .drizzle: .day
        case .fetch, .dinner, .cuddle: .dusk
        case .journal, .sleep: .night
        }
    }

    /// The default line under the cloud. Cycle scenes get a cycle-aware
    /// line from `MascotMoment` instead.
    var line: String {
        switch self {
        case .breakfast: "Morning! Pancakes today."
        case .walk: "Taking the pup to the park."
        case .picnic: "Lunch in the sun."
        case .study: "Caf\u{e9} focus mode."
        case .fetch: "Fetch time!"
        case .dinner: "Making pasta tonight."
        case .journal: "Winding down. Join me?"
        case .sleep: "Zzz\u{2026}"
        case .packing: "Packing pads, just in case."
        case .cozyTea: "Slow morning. Tea first."
        case .hotWaterNap: "Nap with the hot water bottle."
        case .cuddle: "Pup cuddles tonight."
        case .drizzle: "A little drizzly today. That's okay."
        }
    }
}

/// The cloud at one moment: the scene, the words, and when it changes.
struct MascotMoment: Equatable {
    var scene: MascotScene
    var line: String
    /// Small text above the line: "Day 24 · period in 4 days".
    var caption: String?
    var hasFlower: Bool
    /// She said today was good or great: little sparkles round the cloud.
    var sparkle = false

    /// Where a tap on the widget should take her (a `clutch://` host).
    var route: String {
        switch scene {
        case .drizzle, .cozyTea, .cuddle, .hotWaterNap: "hard-time"
        case .journal: "wind-down"
        case .packing: "request"
        case .picnic, .dinner: "cravings"
        default: "today"
        }
    }

    /// The hours each ordinary scene starts at, in order. Sleep wraps past
    /// midnight to 6am.
    static let slots: [(hour: Int, scene: MascotScene)] = [
        (6, .breakfast), (9, .walk), (12, .picnic), (14, .study),
        (17, .fetch), (19, .dinner), (21, .journal), (23, .sleep),
    ]

    static func make(at date: Date, snapshot: CycleSnapshot, calendar: Calendar = .current) -> MascotMoment {
        let hour = calendar.component(.hour, from: date)
        let state = snapshot.state(on: date)
        let mood = snapshot.mood(on: date)
        let base = slots.last { $0.hour <= hour }?.scene ?? .sleep
        // A low mood day gets the same gentle scenes as a usual hard day.
        let kind = state.kind == .normal && (mood ?? 3) <= 2 ? .hard : state.kind
        let scene = scene(for: base, state: kind)
        var line = line(for: scene, state: CycleDayState(kind: kind, cycleDay: state.cycleDay, daysUntilPeriod: state.daysUntilPeriod))
        if state.kind == .normal, let mood, mood <= 2, scene != .sleep, scene != .journal {
            line = "Rough day. I'm right here with you."
        }
        return MascotMoment(
            scene: scene,
            line: line,
            caption: caption(for: state),
            hasFlower: snapshot.logged(on: date),
            sparkle: (mood ?? 0) >= 4 && scene != .sleep
        )
    }

    /// The times today and tomorrow when the scene changes, for the widget
    /// timeline.
    static func changeTimes(from date: Date, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: date)
        return (0...1).flatMap { dayOffset -> [Date] in
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else { return [] }
            return slots.compactMap { calendar.date(bySettingHour: $0.hour, minute: 0, second: 0, of: day) }
        }
        .filter { $0 > date }
    }

    private static func scene(for base: MascotScene, state: CycleDayState.Kind) -> MascotScene {
        // The evening wind-down and sleep stay the same every day.
        guard base != .journal, base != .sleep else { return base }
        switch state {
        case .normal:
            return base
        case .beforePeriod:
            return base == .walk ? .packing : base
        case .period:
            switch base {
            case .breakfast, .walk: return .cozyTea
            case .picnic, .study: return .hotWaterNap
            default: return .cuddle
            }
        case .hard:
            switch base {
            case .breakfast: return .cozyTea
            case .walk, .picnic, .study: return .drizzle
            default: return .cuddle
            }
        }
    }

    private static func line(for scene: MascotScene, state: CycleDayState) -> String {
        switch (scene, state.kind) {
        case (.packing, _):
            if let days = state.daysUntilPeriod {
                return days == 1 ? "Period likely tomorrow. Pads packed." : "Period in \(days) days. Pads packed."
            }
            return scene.line
        case (.cozyTea, .period), (.hotWaterNap, .period), (.cuddle, .period):
            let day = state.cycleDay.map { "Day \($0). " } ?? ""
            return day + ["Taking it slow together.", "Warm and resting.", "Be gentle with yourself."][scene == .cozyTea ? 0 : scene == .hotWaterNap ? 1 : 2]
        case (.drizzle, _), (.cozyTea, .hard), (.cuddle, .hard):
            return scene == .drizzle
                ? "Heavier days are normal right now. It passes."
                : "This stretch is usually rough. Tap if you need me."
        default:
            return scene.line
        }
    }

    private static func caption(for state: CycleDayState) -> String? {
        var parts: [String] = []
        if let day = state.cycleDay { parts.append("Day \(day)") }
        if state.kind != .period, let days = state.daysUntilPeriod {
            parts.append(days == 1 ? "period tomorrow" : "period in \(days) days")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{b7} ")
    }
}
