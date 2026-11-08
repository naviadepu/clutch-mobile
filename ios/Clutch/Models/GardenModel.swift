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
    /// A streak milestone or a full cycle: one glowing extra flower.
    var hasSpecialFlower = false

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
        hasSpecialFlower = log.milestone != nil
    }
}

/// Drives the Garden screen: today's deck (four cards at most), progress
/// through it, and the flowers answering grows — every card answered or
/// swiped past plants one, so showing up counts. "Nothing today" ends the
/// log in one tap and plants a seed instead. A stored per-day seed keeps
/// the bouquet deterministic, and today's progress is restored on relaunch.
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

    var currentCard: DeckCard? { isFinished ? nil : deck[currentIndex] }
    var isFinished: Bool { log.completed || log.nothingToday || currentIndex >= deck.count }
    var hasBloomed: Bool { !flowers.isEmpty || log.nothingToday }
    var totalLoggedCount: Int { log.planted }
    var style: BouquetStyle { BouquetStyle(log: log) }

    /// The engine over everything, today's answers so far included.
    var engine: CycleEngine { CycleEngine(logs: history + [log], profile: profile) }
    var planner: DeckPlanner { DeckPlanner(engine: engine) }

    init(date: Date = Date()) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let today = DayLogStore.loadOrCreate(for: date)
        var profile = CycleProfile.load() ?? CycleProfile()
        let history = DayLogStore.allLogs().filter { calendar.startOfDay(for: $0.date) < dayStart }
        // Onboarded before this was tracked: count from her first log.
        if profile.onboardingComplete && profile.onboardedOn == nil {
            profile.onboardedOn = history.first?.date ?? dayStart
            profile.save()
        }

        self.history = history
        self.profile = profile
        self.log = today
        let planner = DeckPlanner(engine: CycleEngine(logs: history + [today], profile: profile))
        deck = planner.deck(on: date)

        // Pick up where today left off: replaying the seed regrows the same
        // flowers and leaves the generator ready for the next one.
        generator = BouquetGenerator(seed: today.seed)
        let answered = Set(today.answeredCards)
        currentIndex = today.completed ? deck.count : (deck.firstIndex { !answered.contains($0.id) } ?? deck.count)
        flowers = (0..<min(today.planted, BouquetGenerator.maxFlowers)).map { _ in generator.next() }
    }

    /// Chips in her order: most common first once there are three weeks.
    var chipOrder: [Symptom] { planner.symptomOrder(on: log.date) }

    func upcoming(_ count: Int) -> [DeckCard] {
        guard !isFinished else { return [] }
        return Array(deck[currentIndex..<min(currentIndex + count, deck.count)])
    }

    // MARK: - Answers

    func answerMood(_ level: Int) {
        log.mood = level
        complete(.mood)
    }

    func answerEnergy(_ level: Int) {
        log.energy = level
        complete(.energy)
    }

    /// "Anything else?": the chips she picked are yes, the rest no. None
    /// is an empty pick.
    func answerChips(_ symptomIDs: [String]) {
        log.symptoms = Symptom.catalog.map(\.id).filter(symptomIDs.contains)
        log.skipped = Symptom.catalog.map(\.id).filter { !symptomIDs.contains($0) }
        complete(.chips)
    }

    func answerFlow(_ flow: Flow) {
        log.flow = flow
        complete(.flow)
    }

    /// "Ended" on the Flow card: today is the period's last day.
    func answerPeriodEnded() {
        log.periodEnded = true
        log.flow = .noFlow
        complete(.flow)
    }

    /// Saved to the day it's about, not today.
    func answerFollowUp(_ helpers: [Helper], about day: Date) {
        if var earlier = DayLogStore.load(for: day) {
            earlier.helpedNextDay = helpers.map(\.rawValue)
            DayLogStore.save(earlier)
        }
        if let card = currentCard { complete(card) }
    }

    /// A swipe moves on without answering. Still counts as showing up.
    func skipCurrent() {
        guard let card = currentCard else { return }
        complete(card)
    }

    /// Ends today's log in one tap. The day still counts for the streak,
    /// and a seed goes in the bouquet in place of a flower.
    func nothingToday() {
        log.nothingToday = true
        log.completed = true
        DayLogStore.save(log)
    }

    // MARK: - Period

    /// "My period started" shows within 3 days of her predicted window.
    var offersPeriodStart: Bool { engine.isNearPredictedPeriod(log.date) }
    var isOnPeriod: Bool { engine.isOnPeriod(log.date) }

    /// Today starts a new period. Flow becomes card 4 from now until she
    /// taps Ended or her usual length passes.
    func startPeriod() {
        log.periodStarted = true
        log.periodEnded = false
        profile.lastPeriodStart = Calendar.current.startOfDay(for: log.date)
        profile.save()
        DayLogStore.save(log)
        guard !log.completed, !log.nothingToday, !deck.contains(.flow) else { return }
        // Flow is the first contextual rule, so it replaces a follow-up
        // that hasn't been answered yet.
        if let last = deck.last, case .followUp = last, !log.answeredCards.contains(last.id) {
            deck.removeLast()
        }
        if deck.count < DeckCard.maxCards { deck.append(.flow) }
    }

    // MARK: - After the log

    /// The one line under the bloomed bouquet.
    var todayLine: CycleEngine.TodayLine { engine.todayLine(for: log) }

    /// Marks today's milestone so the bouquet keeps its special flower.
    func recordMilestone(_ milestone: String) {
        log.milestone = milestone
        DayLogStore.save(log)
    }

    // MARK: - Private

    private func complete(_ card: DeckCard) {
        log.answeredCards.append(card.id)
        log.planted += 1
        plant()
        currentIndex += 1
        if currentIndex >= deck.count { log.completed = true }
        DayLogStore.save(log)
    }

    private func plant() {
        guard flowers.count < BouquetGenerator.maxFlowers else { return }
        flowers.append(generator.next())
    }
}
