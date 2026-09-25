import Foundation

/// One yes/no swipe in the daily log. `label` is the short word or two
/// spelled out on the card's crossword; `question` is what the card asks.
struct Symptom: Identifiable, Hashable, Codable {
    let id: String
    let label: String
    let question: String
}

extension Symptom {
    /// The swipe cards, in their default order. Once there are three weeks
    /// of logs, `DeckPlanner` puts her most common ones first.
    static let catalog: [Symptom] = [
        Symptom(id: "anxious", label: "anxious", question: "Anxious or on edge today?"),
        Symptom(id: "low", label: "feeling low", question: "Feeling low or down today?"),
        Symptom(id: "irritable", label: "irritable", question: "Snappy or irritable today?"),
        Symptom(id: "cramps", label: "cramps", question: "Any cramps today?"),
        Symptom(id: "bloating", label: "bloating", question: "Feeling bloated today?"),
        Symptom(id: "headache", label: "headache", question: "Got a headache today?"),
        Symptom(id: "poor-sleep", label: "poor sleep", question: "Sleep badly last night?"),
        Symptom(id: "cravings", label: "cravings", question: "Any cravings today?"),
    ]

    static func named(_ id: String) -> Symptom? {
        catalog.first { $0.id == id }
    }

    /// Two or more of these in one day makes it a hard day.
    static let hardDayIDs: Set<String> = ["low", "anxious", "irritable", "cramps"]

    /// Logging any of these asks "what helped?" the next morning.
    static let followUpIDs: Set<String> = ["cramps", "headache", "poor-sleep"]

    /// Cards from the first version of the deck. They're gone from the deck
    /// but still appear in old logs.
    static let legacyPeriodID = "period"
    static let legacyMoodSwingsID = "moody"
}

/// How heavy the period is today. `noFlow` is a real answer ("no period
/// today"), unlike a `nil` flow, which means the card wasn't answered.
enum Flow: String, Codable, CaseIterable, Identifiable {
    case noFlow = "none"
    case light, medium, heavy

    var id: String { rawValue }
    var isBleeding: Bool { self != .noFlow }

    var title: String {
        switch self {
        case .noFlow: "None"
        default: rawValue.capitalized
        }
    }
}

/// What made a hard day easier. `nothingReally` is only offered on the
/// next-day follow-up.
enum Helper: String, Codable, CaseIterable, Identifiable {
    case nap
    case walk
    case heatingPad = "heating-pad"
    case painRelief = "pain-relief"
    case rest
    case talkedToSomeone = "talked-to-someone"
    case nothingReally = "nothing-really"

    var id: String { rawValue }

    /// The choices on the What helped card.
    static let options: [Helper] = allCases.filter { $0 != .nothingReally }

    var title: String {
        switch self {
        case .nap: "Nap"
        case .walk: "Walk"
        case .heatingPad: "Heating pad"
        case .painRelief: "Pain relief"
        case .rest: "Rest"
        case .talkedToSomeone: "Talked to someone"
        case .nothingReally: "Nothing really"
        }
    }

    /// For sentences: "A heating pad helped you…".
    var phrase: String {
        switch self {
        case .nap: "a nap"
        case .walk: "a walk"
        case .heatingPad: "a heating pad"
        case .painRelief: "pain relief"
        case .rest: "rest"
        case .talkedToSomeone: "talking to someone"
        case .nothingReally: "nothing"
        }
    }
}

/// The 1–5 scales on the Mood and Energy cards.
enum LevelScale {
    static let range = 1...5

    static let moodTitles = ["Awful", "Low", "Okay", "Good", "Great"]
    static let energyTitles = ["Drained", "Low", "Okay", "Good", "Buzzing"]
}
