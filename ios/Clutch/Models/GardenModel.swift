import Combine
import CoreGraphics
import Foundation

/// One flower in the day's bouquet: which photographed stem it is and how
/// it sits. Every value is drawn once from the day's seeded RNG, never on
/// render, so a bouquet never rearranges itself — yet no two days match.
struct PlantedFlower: Identifiable {
    let id = UUID()
    /// Which of the flower photos (`flower-1` … `flower-6`).
    let art: Int
    let flipped: Bool
    /// A few degrees of lean on top of its place in the fan.
    let tilt: Double
    /// Small nudge to its height, so heads don't line up.
    let heightOffset: CGFloat
    let swayPeriod: Double
}

/// Grows a day's flowers from its stored seed, one at a time, so the same
/// day always yields the same bouquet — live in the Garden, and rebuilt
/// later in the collection without storing any images.
struct BouquetGenerator {
    private var rng: SeededGenerator
    /// The photos in a shuffled order for this bouquet.
    private let artOrder: [Int]
    private(set) var count = 0

    static let artCount = 6

    /// A bouquet stops adding flowers past this many — a dense bunch reads
    /// as a hedge — though answering cards keeps counting past the cap.
    static let maxFlowers = 6

    /// The two photos that are soft in the original (a motion-blurred
    /// poppy, a shallow-focus bloom) read as depth only at the back.
    static let softArts: Set<Int> = [1, 2]
    /// Positions in the adding order that `Bouquet` lays out in its back row.
    static let backPositions = [0, 2, 4]

    init(seed: Int) {
        var rng = SeededGenerator(seed: seed)
        let shuffled = Array(1...Self.artCount).shuffled(using: &rng)
        // Soft photos take back positions first; the rest fill in order.
        var backQueue = shuffled.filter { Self.softArts.contains($0) } + shuffled.filter { !Self.softArts.contains($0) }
        var order = [Int](repeating: 0, count: Self.artCount)
        for position in Self.backPositions {
            order[position] = backQueue.removeFirst()
        }
        for position in order.indices where order[position] == 0 {
            order[position] = backQueue.removeFirst()
        }
        artOrder = order
        self.rng = rng
    }

    mutating func next() -> PlantedFlower {
        let flower = PlantedFlower(
            art: artOrder[count % artOrder.count],
            flipped: Bool.random(using: &rng),
            tilt: Double.random(in: -3...3, using: &rng),
            heightOffset: CGFloat.random(in: -12...12, using: &rng),
            swayPeriod: Double.random(in: 7...11, using: &rng)
        )
        count += 1
        return flower
    }

    /// The flowers a day's log grew: one per card answered, up to the cap.
    static func flowers(for log: DayLog) -> [PlantedFlower] {
        var generator = BouquetGenerator(seed: log.seed)
        let count = min(log.planted, maxFlowers)
        return (0..<count).map { _ in generator.next() }
    }
}

/// How a day's answers shape its bouquet, on top of the photos: flow
/// deepens the petal colour, energy lengthens the stems, and each symptom
/// she said yes to adds a leaf. A "Nothing today" log plants a seed.
/// (Mood can't open or close photographed petals, so it doesn't change
/// the art.)
struct BouquetStyle: Equatable {
    /// 0 (no flow) … 1 (heavy).
    var colorDepth: Double = 0
    /// Extra stem, in bouquet points.
    var stemBoost: CGFloat = 0
    var leaves = 0
    var hasSeed = false

    static let plain = BouquetStyle()

    init() {}

    init(log: DayLog) {
        switch log.flow {
        case .light: colorDepth = 0.35
        case .medium: colorDepth = 0.65
        case .heavy: colorDepth = 1
        case .noFlow, nil: colorDepth = 0
        }
        stemBoost = log.energy.map { CGFloat($0 - 3) * 10 } ?? 0
        leaves = min(log.symptoms.count, Symptom.catalog.count)
        hasSeed = log.nothingToday
    }
}

/// What the card back shows after a yes swipe.
struct FlipInsight: Identifiable, Equatable {
    let id = UUID()
    let symptom: Symptom
    /// `nil` when only the support line is left to say.
    let insight: CycleEngine.SymptomInsight?
    let text: String
    let action: SymptomTips.Action?
    let laterActions: [String]
    /// Five or more low days in a row.
    let showsSupport: Bool

    /// Tiers 3 and 4 ask "Does this match you?".
    var asksForMatch: Bool { (insight?.tier ?? 0) >= 3 }

    static func == (lhs: FlipInsight, rhs: FlipInsight) -> Bool { lhs.id == rhs.id }
}

/// Drives the Garden screen: today's deck, progress through it, and the
/// flowers answering grows — every card answered plants one, whatever the
/// answer, so showing up counts. "Nothing today" ends the log in one tap
/// and plants a seed instead. A stored per-day seed keeps the bouquet
/// deterministic, and today's progress is restored on relaunch.
@MainActor
final class GardenModel: ObservableObject {
    @Published private(set) var deck: [DeckCard]
    @Published private(set) var currentIndex = 0
    @Published private(set) var flowers: [PlantedFlower] = []
    @Published private(set) var log: DayLog
    @Published private(set) var profile: CycleProfile

    /// Every day before today, oldest first.
    private let history: [DayLog]
    private var generator: BouquetGenerator
    private let yesterdayHadPeriod: Bool
    private let tips = SymptomTips.shared

    var currentCard: DeckCard? { isFinished ? nil : deck[currentIndex] }
    var isFinished: Bool { log.nothingToday || currentIndex >= deck.count }
    var hasBloomed: Bool { !flowers.isEmpty || log.nothingToday }
    var totalLoggedCount: Int { log.planted }
    var style: BouquetStyle { BouquetStyle(log: log) }

    /// The engine over everything, today's answers so far included.
    var engine: CycleEngine { CycleEngine(logs: history + [log], profile: profile) }

    init(date: Date = Date()) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        var today = DayLogStore.loadOrCreate(for: date)
        var profile = CycleProfile.load() ?? CycleProfile()
        let history = DayLogStore.allLogs().filter { calendar.startOfDay(for: $0.date) < dayStart }
        // Onboarded before this was tracked: count from her first log, so
        // the one-time questions she never saw start coming up.
        if profile.onboardingComplete && profile.onboardedOn == nil {
            profile.onboardedOn = history.first?.date ?? dayStart
            profile.save()
        }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: dayStart).flatMap(DayLogStore.load(for:))

        let planner = DeckPlanner(engine: CycleEngine(logs: history, profile: profile))
        // The lead card is picked once a day, so a relaunch keeps it.
        if today.leadCard == nil {
            today.leadCard = DeckPlanner.code(for: planner.chooseLead(on: date))
            DayLogStore.save(today)
        }
        var deck = planner.deck(lead: planner.lead(fromCode: today.leadCard ?? "", on: date), on: date)
        if today.answeredCards.contains(DeckCard.helped.id) { deck.append(.helped) }

        self.history = history
        self.profile = profile
        self.log = today
        self.deck = deck
        yesterdayHadPeriod = yesterday?.flow?.isBleeding ?? yesterday?.legacySymptoms?.contains(Symptom.legacyPeriodID) ?? false

        // Pick up where today left off: replaying the seed regrows the same
        // flowers and leaves the generator ready for the next one.
        generator = BouquetGenerator(seed: today.seed)
        let answered = Set(today.answeredCards)
        currentIndex = today.completed ? deck.count : (deck.firstIndex { !answered.contains($0.id) } ?? deck.count)
        flowers = (0..<min(today.planted, BouquetGenerator.maxFlowers)).map { _ in generator.next() }
        addHelpedIfHardDay()
    }

    func upcoming(_ count: Int) -> [DeckCard] {
        guard !isFinished else { return [] }
        return Array(deck[currentIndex..<min(currentIndex + count, deck.count)])
    }

    // MARK: - Answers

    func answerFlow(_ flow: Flow) {
        log.flow = flow
        if flow.isBleeding { recordPeriodStart() }
        complete(.flow)
    }

    func answerMood(_ level: Int) {
        log.mood = level
        complete(.mood)
    }

    func answerEnergy(_ level: Int) {
        log.energy = level
        complete(.energy)
    }

    /// Right is yes, left is no.
    func answerSymptom(_ symptom: Symptom, yes: Bool) {
        if yes { log.symptoms.append(symptom.id) } else { log.skipped.append(symptom.id) }
        complete(.symptom(symptom))
    }

    func answerHelped(_ helpers: [Helper]) {
        log.helped = helpers.map(\.rawValue)
        complete(.helped)
    }

    /// Saved to the day it's about, not today.
    func answerFollowUp(_ helpers: [Helper], about day: Date) {
        if var earlier = DayLogStore.load(for: day) {
            earlier.helpedNextDay = helpers.map(\.rawValue)
            DayLogStore.save(earlier)
        }
        if case let .some(card) = currentCard, case .followUp = card { complete(card) }
    }

    func answerOneTime(_ question: OneTimeQuestion, update: (inout CycleProfile) -> Void) {
        update(&profile)
        profile.oneTimeCards[question.id, default: OneTimeCardState()].answered = true
        profile.save()
        complete(.oneTime(question))
    }

    /// Skipped once, it comes back in a week; skipped twice, it's gone.
    func skipOneTime(_ question: OneTimeQuestion) {
        profile.oneTimeCards[question.id, default: OneTimeCardState()].skips.append(log.date)
        profile.save()
        complete(.oneTime(question))
    }

    /// Ends today's log in one tap. The day still counts for the streak,
    /// and a seed goes in the bouquet in place of a flower.
    func nothingToday() {
        log.nothingToday = true
        log.completed = true
        DayLogStore.save(log)
    }

    /// The general tip counts toward its once-a-week limit once it's shown.
    func markShown(_ flip: FlipInsight) {
        if flip.insight == .general { InsightStore.markGeneralShown(flip.symptom.id, on: log.date) }
    }

    /// The one line under the bloomed bouquet.
    var todayLine: CycleEngine.TodayLine { engine.todayLine(for: log) }

    /// What the card's back would say if she says yes to `symptom` — worked
    /// out before answering, so the card can flip rather than fly off.
    /// `nil` means nothing to flip for.
    func insightIfYes(_ symptom: Symptom) -> FlipInsight? {
        var withYes = log
        withYes.symptoms.append(symptom.id)
        let engine = CycleEngine(logs: history + [withYes], profile: profile)
        let insight = engine.symptomInsight(
            for: symptom.id, on: log.date, generalLastShown: InsightStore.generalLastShown(symptom.id)
        )
        let showsSupport = symptom.id == "low"
            && engine.currentRun(of: "low", endingOn: log.date) >= InsightCopy.supportAfterLowDays
        guard insight != nil || showsSupport, let entry = tips[symptom.id] else { return nil }
        return FlipInsight(
            symptom: symptom,
            insight: insight,
            text: insight.map { InsightCopy.text(for: $0, symptomID: symptom.id, tips: tips) } ?? entry.tip,
            action: entry.action,
            laterActions: tips.laterActions(for: symptom.id, profile: profile).map(\.title),
            showsSupport: showsSupport
        )
    }

    // MARK: - Private

    private func complete(_ card: DeckCard) {
        log.answeredCards.append(card.id)
        log.planted += 1
        plant()
        currentIndex += 1
        addHelpedIfHardDay()
        if currentIndex >= deck.count { log.completed = true }
        DayLogStore.save(log)
    }

    /// What helped joins the deck once the symptom swipes are done, if the
    /// day turned out hard.
    private func addHelpedIfHardDay() {
        guard !deck.contains(.helped), !log.completed, !log.nothingToday else { return }
        let swipesLeft = deck[min(currentIndex, deck.count)...].contains { $0.isSwipe }
        guard !swipesLeft, engine.isHardDay(log) else { return }
        deck.append(.helped)
    }

    /// Bleeding today gives an exact cycle start date — overriding an
    /// estimate or an earlier "Not sure" — unless it's just another day of
    /// a period that's already underway.
    private func recordPeriodStart() {
        guard let start = CycleProfile.newPeriodStart(
            loggedOn: log.date,
            yesterdayHadPeriod: yesterdayHadPeriod,
            currentStart: profile.lastPeriodStart,
            periodLength: profile.effectivePeriodLength
        ) else { return }
        profile.lastPeriodStart = start
        profile.save()
    }

    private func plant() {
        guard flowers.count < BouquetGenerator.maxFlowers else { return }
        flowers.append(generator.next())
    }
}
