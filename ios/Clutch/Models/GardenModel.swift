import Combine
import CoreGraphics
import Foundation

/// One flower planted in the garden. Every value here is randomised once,
/// at plant time, from the day's seeded RNG — never regenerated on render —
/// so the garden doesn't rearrange itself and no two gardens look alike.
struct PlantedFlower: Identifiable {
    let id = UUID()
    /// Small random nudge off the bouquet's neat fan position, so the
    /// cluster reads as gathered-by-hand rather than a perfect arc.
    let jitter: CGFloat
    /// The stem is drawn separately from the bloom photo now (a soft
    /// curved path, not baked into the image), so head and stem size
    /// independently.
    let stemHeight: CGFloat
    let bloomWidth: CGFloat
    let rotation: Double
    let paletteIndex: Int
    let swayPeriod: Double
    /// How far the stem's curve control point sits off the vertical,
    /// signed so it bows to one side or the other — derived from the
    /// day seed, like everything else here.
    let stemCurveOffset: CGFloat
}

/// Drives the Garden screen: the ranked deck, swipe progress, and the
/// flowers that swiping plants — logging and skipping both grow one, so
/// showing up for a card counts even when the answer is "no." A stored
/// per-day seed keeps the garden's randomness deterministic across
/// relaunches.
@MainActor
final class GardenModel: ObservableObject {
    @Published private(set) var deck: [Symptom]
    @Published private(set) var currentIndex = 0
    @Published private(set) var flowers: [PlantedFlower] = []

    /// TODO: derive the real phase (and a real cycle day) once the
    /// cycle-date onboarding step persists a start date — hardcoded for now,
    /// same placeholder the deck ranking already used.
    let phase: CyclePhase = .luteal

    private var dayLog: DayLog
    private var rng: SeededGenerator

    /// The bouquet stops adding flowers past this many — a dense screen
    /// reads as a hedge, not a garden — but logging/skipping keeps working
    /// and `totalLoggedCount` keeps counting past the cap.
    static let maxVisibleFlowers = 6

    var currentSymptom: Symptom? { currentIndex < deck.count ? deck[currentIndex] : nil }
    var isFinished: Bool { currentIndex >= deck.count }
    var hasBloomed: Bool { !flowers.isEmpty }
    var totalLoggedCount: Int { dayLog.symptoms.count + dayLog.skipped.count }

    init(date: Date = Date()) {
        let calendar = Calendar.current
        let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        let yesterday = DayLogStore.load(for: yesterdayDate)
        let today = DayLogStore.loadOrCreate(for: date)

        dayLog = today
        rng = SeededGenerator(seed: today.seed)
        deck = rankedDeck(catalog: Symptom.catalog, yesterday: yesterday?.symptoms ?? [], phase: phase)
    }

    func upcoming(_ count: Int) -> [Symptom] {
        guard currentIndex < deck.count else { return [] }
        let end = min(currentIndex + count, deck.count)
        return Array(deck[currentIndex..<end])
    }

    func logCurrent() {
        guard let symptom = currentSymptom else { return }
        dayLog.symptoms.append(symptom.id)
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

    private func advance() {
        currentIndex += 1
        DayLogStore.save(dayLog)
    }

    private func plant() {
        // Past the cap we still want a fresh RNG draw per log/skip so later
        // flowers (if the cap ever changes) don't retroactively shift — but
        // there's nothing to size yet, so just stop.
        guard flowers.count < Self.maxVisibleFlowers else { return }

        let index = flowers.count
        let curveMagnitude = CGFloat.random(in: 6...10, using: &rng)
        let curveSign: CGFloat = Bool.random(using: &rng) ? 1 : -1
        let flower = PlantedFlower(
            jitter: CGFloat.random(in: -14...14, using: &rng),
            stemHeight: CGFloat.random(in: 110...160, using: &rng),
            bloomWidth: CGFloat.random(in: 70...95, using: &rng),
            rotation: Double.random(in: -8...8, using: &rng),
            paletteIndex: index % 5,
            swayPeriod: Double.random(in: 5.2...7.6, using: &rng),
            stemCurveOffset: curveMagnitude * curveSign
        )
        flowers.append(flower)
    }
}
