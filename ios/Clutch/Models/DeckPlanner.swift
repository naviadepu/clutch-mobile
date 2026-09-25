import Foundation

/// One card in the daily log.
enum DeckCard: Hashable, Identifiable {
    /// A one-time question about her, from day 2 on.
    case oneTime(OneTimeQuestion)
    /// "Yesterday you had cramps. What helped?" — answers go to `day`'s log.
    case followUp(day: Date, symptomIDs: [String], daysAgo: Int)
    case flow
    case mood
    case energy
    case symptom(Symptom)
    /// Only on a hard day, after the symptom swipes.
    case helped

    var id: String {
        switch self {
        case let .oneTime(question): question.id
        case .followUp: "followup"
        case .flow: "flow"
        case .mood: "mood"
        case .energy: "energy"
        case let .symptom(symptom): Self.symptomCardID(symptom.id)
        case .helped: "helped"
        }
    }

    static func symptomCardID(_ symptomID: String) -> String { "symptom.\(symptomID)" }

    /// Swipe right/left; every other card is tapped.
    var isSwipe: Bool {
        if case .symptom = self { return true }
        return false
    }
}

/// Decides what's in today's deck and in what order: at most one lead
/// card (a one-time question or a follow-up), then Flow, Mood, Energy and
/// the symptom swipes. What helped is added by `GardenModel` once the
/// swipes make it a hard day.
struct DeckPlanner {
    /// Symptoms are reordered by how often she has them once her logs go
    /// back this far.
    static let reorderAfterDays = 21

    let engine: CycleEngine
    var profile: CycleProfile { engine.profile }
    var calendar: Calendar { engine.calendar }

    // MARK: - Symptom order

    func symptomOrder(on date: Date) -> [Symptom] {
        let history = engine.logs.filter { $0.date < calendar.startOfDay(for: date) }
        guard let first = history.first, engine.days(from: first.date, to: date) >= Self.reorderAfterDays else {
            return Symptom.catalog
        }
        let counts = Dictionary(uniqueKeysWithValues: Symptom.catalog.map { symptom in
            (symptom.id, history.filter { $0.said(symptom.id) }.count)
        })
        // Stable: ties keep the default order.
        return Symptom.catalog.enumerated()
            .sorted { (counts[$0.element.id] ?? 0, -$0.offset) > (counts[$1.element.id] ?? 0, -$1.offset) }
            .map(\.element)
    }

    // MARK: - Lead card

    /// Day 1 is the day she finished onboarding.
    func dayNumber(on date: Date) -> Int? {
        profile.onboardedOn.map { engine.days(from: $0, to: date) + 1 }
    }

    /// The first one-time question that's due: its day has come, it isn't
    /// answered, and it hasn't been skipped (or was skipped once, at least a
    /// week ago).
    func dueOneTimeQuestion(on date: Date) -> OneTimeQuestion? {
        guard let dayNumber = dayNumber(on: date) else { return nil }
        return OneTimeQuestion.allCases.first { question in
            guard dayNumber >= question.day else { return false }
            let state = profile.oneTimeCards[question.id] ?? OneTimeCardState()
            if state.answered { return false }
            switch state.skips.count {
            case 0: return true
            case 1: return engine.days(from: state.skips[0], to: date) >= 7
            default: return false
            }
        }
    }

    /// A day `daysAgo` back that earned a "what helped?" follow-up: a hard
    /// day, or cramps, headache or poor sleep — and not followed up yet.
    func followUpCard(on date: Date, daysAgo: Int) -> DeckCard? {
        guard let log = engine.log(on: engine.day(-daysAgo, from: date)),
              !log.nothingToday, log.helpedNextDay == nil
        else { return nil }
        let asked = Symptom.catalog.map(\.id).filter { log.said($0) && Symptom.followUpIDs.contains($0) }
        guard !asked.isEmpty || engine.isHardDay(log) else { return nil }
        return .followUp(day: calendar.startOfDay(for: log.date), symptomIDs: asked, daysAgo: daysAgo)
    }

    /// One-time questions come first. When one bumps yesterday's
    /// follow-up, that follow-up gets its turn the next day, ahead of the
    /// next one-time question.
    func chooseLead(on date: Date) -> DeckCard? {
        let yesterdayLead = engine.log(on: engine.day(-1, from: date))?.leadCard ?? ""
        if yesterdayLead.hasPrefix("onetime."), let deferred = followUpCard(on: date, daysAgo: 2) {
            return deferred
        }
        if let question = dueOneTimeQuestion(on: date) { return .oneTime(question) }
        return followUpCard(on: date, daysAgo: 1)
    }

    /// How a chosen lead is stored in the day's log, and read back.
    static func code(for lead: DeckCard?) -> String {
        switch lead {
        case let .oneTime(question): question.id
        case let .followUp(_, _, daysAgo): "followup.\(daysAgo)"
        default: ""
        }
    }

    func lead(fromCode code: String, on date: Date) -> DeckCard? {
        if let question = OneTimeQuestion.allCases.first(where: { $0.id == code }) { return .oneTime(question) }
        if code.hasPrefix("followup."), let daysAgo = Int(code.dropFirst("followup.".count)) {
            return followUpCard(on: date, daysAgo: daysAgo) ?? {
                // Already answered today: rebuild it so the deck still lines up.
                let day = engine.day(-daysAgo, from: date)
                return .followUp(day: day, symptomIDs: [], daysAgo: daysAgo)
            }()
        }
        return nil
    }

    // MARK: - Deck

    func deck(lead: DeckCard?, on date: Date) -> [DeckCard] {
        (lead.map { [$0] } ?? []) + [.flow, .mood, .energy] + symptomOrder(on: date).map(DeckCard.symptom)
    }
}
