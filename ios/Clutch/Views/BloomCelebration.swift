import SwiftUI
import UIKit

/// What plays after the last card.
struct Celebration {
    /// Today's newest flower, or `nil` on a "Nothing today" seed day.
    let flower: PlantedFlower?
    let streakBefore: Int
    let streakAfter: Int
    /// "A full cycle bouquet." and the like, on milestone days.
    let milestone: String?
    /// Today in one line.
    let line: String

    struct Milestone {
        let id: String
        let line: String
    }

    /// A full logged cycle ending today beats a streak milestone.
    static func milestone(streak: Int, engine: CycleEngine, today: DayLog) -> Milestone? {
        if today.periodStarted,
           let finished = engine.completedCycles.last,
           engine.calendar.isDate(finished.nextStart, inSameDayAs: today.date),
           engine.isUsable(finished) {
            return Milestone(id: "cycle", line: "A full cycle bouquet.")
        }
        switch streak {
        case 7: return Milestone(id: "7", line: "A 7-day bouquet. A whole week of showing up.")
        case 14: return Milestone(id: "14", line: "Two weeks of blooms.")
        case 28: return Milestone(id: "28", line: "28 days in bloom.")
        default: return nil
        }
    }
}

/// About two seconds, over the Garden: today's flower opens in the middle
/// of the screen, shrinks and arcs down into the bouquet, and the streak
/// rolls up by one with a pop. Then today's line and the way on. A tap
/// skips to the end; with Reduce Motion it's a simple crossfade.
struct BloomCelebration: View {
    let celebration: Celebration
    let style: BouquetStyle
    let onLanded: () -> Void
    let onDetails: () -> Void
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = Step.start
    @State private var streak: Int
    @State private var pop = false
    @State private var landed = false
    @State private var sequence: Task<Void, Never>?

    private enum Step: Int, Comparable {
        case start, bloom, fly, tick, settled
        static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }
    }

    init(celebration: Celebration, style: BouquetStyle, onLanded: @escaping () -> Void, onDetails: @escaping () -> Void, onDone: @escaping () -> Void) {
        self.celebration = celebration
        self.style = style
        self.onLanded = onLanded
        self.onDetails = onDetails
        self.onDone = onDone
        _streak = State(initialValue: celebration.streakBefore)
    }

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { if step < .settled { skipToEnd() } }

            streakCounter
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 64)

            newGrowth
                .allowsHitTesting(false)

            if step == .settled {
                settledPanel
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 40)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .onAppear(perform: play)
        .onDisappear { sequence?.cancel() }
        .accessibilityAction(named: "Skip") { skipToEnd() }
    }

    // MARK: - Pieces

    private var streakCounter: some View {
        VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(streak)")
                    .font(.custom("DotoRounded-Medium", size: 56))
                    .contentTransition(.numericText(value: Double(streak)))
                Text(streak == 1 ? "day" : "days")
                    .font(.custom("Quicksand-Regular", size: 16))
            }
            .scaleEffect(pop ? 1.18 : 1)

            if let milestone = celebration.milestone, step >= .tick {
                Text(milestone)
                    .font(.system(size: 15, design: .serif).italic())
                    .transition(.opacity)
            }
        }
        .foregroundStyle(Color.ink)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(streak)-day streak")
    }

    /// The flower (or seed) on its way into the bouquet.
    @ViewBuilder
    private var newGrowth: some View {
        let shown = step >= .bloom && !landed
        let flying = step >= .fly
        Group {
            if let flower = celebration.flower {
                SingleFlower(flower: flower, depth: style.colorDepth)
            } else {
                PlantedSeed().scaleEffect(2.2)
            }
        }
        // Blooms above the bouquet, then drops into it (it sits low, under
        // where the cards were).
        .scaleEffect(reduceMotion ? 0.62 : (flying ? 0.18 : (shown ? 0.62 : 0.2)))
        .offset(x: reduceMotion ? 0 : (flying ? 8 : 0), y: reduceMotion ? -120 : (flying ? 170 : -120))
        .opacity(shown ? 1 : 0)
    }

    private var settledPanel: some View {
        VStack(spacing: 16) {
            Text(celebration.line)
                .font(.system(size: 17, design: .serif).italic())
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)

        }
        .padding(.horizontal, 28)
    }

    // MARK: - Sequence

    private func play() {
        sequence = Task { @MainActor in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if reduceMotion {
                withAnimation(.easeInOut(duration: 0.4)) { step = .bloom }
                guard await pause(0.7) else { return }
                withAnimation(.easeInOut(duration: 0.4)) { land() }
                guard await pause(0.3) else { return }
                tick()
                guard await pause(0.5) else { return }
                withAnimation(.easeInOut(duration: 0.3)) { step = .settled }
                // Straight on to sharing it.
                guard await pause(1.0) else { return }
                onDone()
                return
            }

            // Bloom: 0.6 s.
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { step = .bloom }
            guard await pause(0.6) else { return }
            // Fly in: 0.6 s, arcing down into the bunch.
            withAnimation(.timingCurve(0.5, 0, 0.7, 1, duration: 0.6)) { step = .fly }
            guard await pause(0.55) else { return }
            land()
            // Streak tick: 0.4 s.
            tick()
            guard await pause(0.2) else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { pop = false }
            guard await pause(0.25) else { return }
            withAnimation(.easeInOut(duration: 0.35)) { step = .settled }
            // A beat to read the line, then straight on to sharing it.
            guard await pause(1.2) else { return }
            onDone()
        }
    }

    /// `false` once the sequence is skipped.
    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }

    private func land() {
        guard !landed else { return }
        landed = true
        onLanded()
    }

    private func tick() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
            streak = celebration.streakAfter
            step = .tick
            pop = !reduceMotion
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func skipToEnd() {
        sequence?.cancel()
        land()
        withAnimation(.easeInOut(duration: 0.25)) {
            streak = celebration.streakAfter
            pop = false
            step = .settled
        }
    }
}
