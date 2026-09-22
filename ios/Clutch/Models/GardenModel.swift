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
        let count = min(log.answeredCount, maxFlowers)
        return (0..<count).map { _ in generator.next() }
    }
}

/// Drives the Garden screen: the deck, swipe progress, and the
/// flowers that swiping plants — logging and skipping both grow one, so
/// showing up for a card counts even when the answer is "no." A stored
/// per-day seed keeps the garden's randomness deterministic, and today's
/// progress is restored on relaunch.
@MainActor
final class GardenModel: ObservableObject {
    @Published private(set) var deck: [Symptom]
    @Published private(set) var currentIndex = 0
    @Published private(set) var flowers: [PlantedFlower] = []

    private var dayLog: DayLog
    private var generator: BouquetGenerator
    private let yesterdayHadPeriod: Bool

    var currentSymptom: Symptom? { currentIndex < deck.count ? deck[currentIndex] : nil }
    var isFinished: Bool { currentIndex >= deck.count }
    var hasBloomed: Bool { !flowers.isEmpty }
    var totalLoggedCount: Int { dayLog.answeredCount }

    init(date: Date = Date()) {
        let calendar = Calendar.current
        let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        let yesterday = DayLogStore.load(for: yesterdayDate)
        let today = DayLogStore.loadOrCreate(for: date)

        dayLog = today
        yesterdayHadPeriod = yesterday?.symptoms.contains(Symptom.periodID) ?? false
        deck = Symptom.catalog

        // Pick up where today left off: replaying the seed regrows the same
        // flowers and leaves the generator ready for the next one.
        generator = BouquetGenerator(seed: today.seed)
        let answered = min(today.answeredCount, deck.count)
        currentIndex = answered
        flowers = (0..<min(answered, BouquetGenerator.maxFlowers)).map { _ in generator.next() }
    }

    func upcoming(_ count: Int) -> [Symptom] {
        guard currentIndex < deck.count else { return [] }
        let end = min(currentIndex + count, deck.count)
        return Array(deck[currentIndex..<end])
    }

    /// `flow` is only meaningful for the period card.
    func logCurrent(flow: Flow? = nil) {
        guard let symptom = currentSymptom else { return }
        dayLog.symptoms.append(symptom.id)
        if symptom.asksForFlow {
            dayLog.flow = flow
            recordPeriodStart()
        }
        plant()
        advance()
    }

    func skipCurrent() {
        guard let symptom = currentSymptom else { return }
        dayLog.skipped.append(symptom.id)
        // A flower still grows on skip — showing up at all is worth
        // something on its own, not just logging a symptom.
        plant()
        advance()
    }

    /// Bleeding today gives an exact cycle start date — overriding an
    /// estimate or an earlier "I don't remember" — unless it's just another
    /// day of a period that's already underway.
    private func recordPeriodStart() {
        var profile = CycleProfile.load() ?? CycleProfile()
        guard let start = CycleProfile.newPeriodStart(
            loggedOn: dayLog.date,
            yesterdayHadPeriod: yesterdayHadPeriod,
            currentStart: profile.lastPeriodStart,
            periodLength: profile.effectivePeriodLength
        ) else { return }
        profile.lastPeriodStart = start
        profile.save()
    }

    private func advance() {
        currentIndex += 1
        DayLogStore.save(dayLog)
    }

    private func plant() {
        guard flowers.count < BouquetGenerator.maxFlowers else { return }
        flowers.append(generator.next())
    }
}
