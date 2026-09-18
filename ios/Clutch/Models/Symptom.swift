import Foundation

/// One loggable symptom card in the Garden deck.
struct Symptom: Identifiable, Hashable, Codable {
    let id: String
    let label: String
}

extension Symptom {
    /// The full catalog the Garden deck draws from. Order here is only the
    /// fallback tier — see `rankedDeck` for how the deck is actually ordered.
    static let catalog: [Symptom] = [
        Symptom(id: "cramps", label: "cramps"),
        Symptom(id: "bloated", label: "bloated"),
        Symptom(id: "tired", label: "tired"),
        Symptom(id: "anxious", label: "anxious"),
        Symptom(id: "headache", label: "headache"),
        Symptom(id: "tender", label: "tender breasts"),
        Symptom(id: "acne", label: "acne"),
        Symptom(id: "cravings", label: "cravings"),
        Symptom(id: "moody", label: "mood swings"),
        Symptom(id: "slept-well", label: "slept well"),
    ]
}

/// Where the user is in their cycle, used to bias which symptoms surface
/// first in the deck.
enum CyclePhase: String, Codable {
    case menstrual, follicular, ovulation, luteal

    /// Symptom ids commonly reported during this phase, most-likely first.
    var commonSymptomIDs: [String] {
        switch self {
        case .menstrual: ["cramps", "tired", "bloated", "headache"]
        case .follicular: ["slept-well", "cravings"]
        case .ovulation: ["tender", "cravings"]
        case .luteal: ["moody", "bloated", "anxious", "acne"]
        }
    }
}

/// Builds the deck order per the brief: yesterday's logged symptoms first,
/// then symptoms common for the current phase, then everything else —
/// so the deck never opens with a run of misses.
func rankedDeck(catalog: [Symptom], yesterday: [String], phase: CyclePhase) -> [Symptom] {
    var seen = Set<String>()
    var ordered: [Symptom] = []

    func add(_ id: String) {
        guard !seen.contains(id), let symptom = catalog.first(where: { $0.id == id }) else { return }
        seen.insert(id)
        ordered.append(symptom)
    }

    yesterday.forEach(add)
    phase.commonSymptomIDs.forEach(add)
    catalog.forEach { add($0.id) }

    return ordered
}
