import Foundation

/// One card in the daily log. Never more than four: Mood, Energy,
/// "Anything else?", and at most one contextual card.
enum DeckCard: Hashable, Identifiable {
    case mood
    case energy
    /// "Anything else?" — every symptom as a tappable chip, plus None.
    case chips
    /// Only while she's on her period: light, medium, heavy, or ended.
    case flow
    /// "Yesterday was rough. What helped?" — answers go to `day`'s log.
    case followUp(day: Date)

    var id: String {
        switch self {
        case .mood: "mood"
        case .energy: "energy"
        case .chips: "chips"
        case .flow: "flow"
        case .followUp: "followup"
        }
    }

    static let maxCards = 4
}

/// Decides today's deck: Mood, Energy and "Anything else?" every day, then
/// the first contextual card that applies — Flow while she's on her
/// period, otherwise yesterday's follow-up — or nothing. Also picks the
/// one question a day the details page asks.
struct DeckPlanner {
    /// Chips are reordered by how often she has them once her logs go back
    /// this far.
    static let reorderAfterDays = 21

    let engine: CycleEngine
    var profile: CycleProfile { engine.profile }
    var calendar: Calendar { engine.calendar }

    func deck(on date: Date) -> [DeckCard] {
        dailyCards + (contextualCard(on: date).map { [$0] } ?? [])
    }

    /// Mood, Energy and "Anything else?", led by what she said onboarding
    /// she's here for: cramps first for pain, energy first for energy.
    private var dailyCards: [DeckCard] {
        let goals = Set(profile.goals ?? [])
        if goals.contains(.mood) || goals.isEmpty { return [.mood, .energy, .chips] }
        if goals.contains(.pain) { return [.chips, .mood, .energy] }
        if goals.contains(.energy) { return [.energy, .mood, .chips] }
        return [.mood, .energy, .chips]
    }

    func contextualCard(on date: Date) -> DeckCard? {
        if engine.isOnPeriod(date) { return .flow }
        return followUpDay(on: date).map(DeckCard.followUp)
    }

    /// Yesterday, if it was a hard day or had cramps, headache or poor
    /// sleep, and hasn't been followed up yet.
    func followUpDay(on date: Date) -> Date? {
        guard let yesterday = engine.log(on: engine.day(-1, from: date)),
              !yesterday.nothingToday, yesterday.helpedNextDay == nil
        else { return nil }
        let rough = engine.isHardDay(yesterday) || !Set(yesterday.symptoms).isDisjoint(with: Symptom.followUpIDs)
        return rough ? calendar.startOfDay(for: yesterday.date) : nil
    }

    // MARK: - Chip order

    func symptomOrder(on date: Date) -> [Symptom] {
        let history = engine.logs.filter { $0.date < calendar.startOfDay(for: date) }
        guard let first = history.first, engine.days(from: first.date, to: date) >= Self.reorderAfterDays else {
            return goalOrder
        }
        let counts = Dictionary(uniqueKeysWithValues: Symptom.catalog.map { symptom in
            (symptom.id, history.filter { $0.said(symptom.id) }.count)
        })
        // Stable: ties keep the default order.
        return Symptom.catalog.enumerated()
            .sorted { (counts[$0.element.id] ?? 0, -$0.offset) > (counts[$1.element.id] ?? 0, -$1.offset) }
            .map(\.element)
    }

    /// Before her own history says otherwise, the symptoms behind her
    /// goals come first.
    private var goalOrder: [Symptom] {
        let goals = profile.goals ?? []
        var first: [String] = []
        if goals.contains(.pain) { first += ["cramps", "headache", "bloating"] }
        if goals.contains(.mood) { first += ["low", "anxious", "irritable"] }
        if goals.contains(.energy) { first += ["poor-sleep"] }
        let rank = { (id: String) in first.firstIndex(of: id) ?? first.count }
        return Symptom.catalog.enumerated()
            .sorted { (rank($0.element.id), $0.offset) < (rank($1.element.id), $1.offset) }
            .map(\.element)
    }

    // MARK: - Help Clutch know you

    /// The questions the details page asks, in order. Onboarding doesn't
    /// ask any of them.
    static let questionOrder: [OneTimeQuestion] = [.birthControl, .periodLength, .products, .student, .goals]

    /// Today's question: the first one not yet answered (a skipped one
    /// comes back once, a week later). One a day — none once she's
    /// answered or skipped one today.
    func dueQuestion(on date: Date) -> OneTimeQuestion? {
        let states = profile.oneTimeCards.values
        let actedToday = states.contains { state in
            state.answeredOn.map { calendar.isDate($0, inSameDayAs: date) } == true
                || state.skips.contains { calendar.isDate($0, inSameDayAs: date) }
        }
        guard !actedToday else { return nil }
        return Self.questionOrder.first { question in
            let state = profile.oneTimeCards[question.id] ?? OneTimeCardState()
            if state.answered { return false }
            switch state.skips.count {
            case 0: return true
            case 1: return engine.days(from: state.skips[0], to: date) >= 7
            default: return false
            }
        }
    }
}
