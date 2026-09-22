import Foundation

/// One card in the Garden deck. `label` is the short word or two spelled
/// out on the card's crossword; `question` is what the card asks.
struct Symptom: Identifiable, Hashable, Codable {
    let id: String
    let label: String
    let question: String

    /// The period card: swiping right asks for flow, and logging it pins
    /// down the real cycle start date.
    static let periodID = "period"

    var asksForFlow: Bool { id == Self.periodID }
}

/// How heavy the period is, picked after swiping right on the period card.
enum Flow: String, Codable, CaseIterable, Identifiable {
    case light, medium, heavy

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

extension Symptom {
    /// Today's deck, in order: the period card first (the most valuable
    /// answer for prediction), then the four mood check-ins.
    static let catalog: [Symptom] = [
        Symptom(id: periodID, label: "period", question: "Is your period happening today?"),
        Symptom(id: "low", label: "feeling low", question: "Feeling low or down today?"),
        Symptom(id: "anxious", label: "anxious", question: "Anxious or on edge today?"),
        Symptom(id: "moody", label: "mood swings", question: "Did your mood swing around today?"),
        Symptom(id: "irritable", label: "irritable", question: "Snappy or irritable today?"),
    ]
}
