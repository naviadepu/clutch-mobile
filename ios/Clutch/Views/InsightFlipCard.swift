import SwiftUI
import UIKit

/// After a yes swipe, the symptom card turns over to show one insight and
/// one action. It stays until she taps or swipes it away — no timer.
struct InsightFlipCard: View {
    let flip: FlipInsight
    /// Today's bouquet, for the soft-day share (a picture, no health data).
    let flowers: [PlantedFlower]
    let style: BouquetStyle
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle: Double = 0
    @State private var matchAnswer: Bool?
    @State private var actionState = ActionState.idle
    @State private var snack = ""
    @State private var dragOffset: CGFloat = 0

    private enum ActionState: Equatable {
        case idle, breathing, snackEntry
        case done(String)
    }

    var body: some View {
        FlipView(angle: angle, front: CrosswordCard(symptom: flip.symptom), back: back)
            .offset(x: dragOffset)
            .contentShape(Rectangle())
            .onTapGesture(perform: onContinue)
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { dragOffset = $0.translation.width }
                    .onEnded { value in
                        if abs(value.translation.width) > 80 {
                            onContinue()
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { dragOffset = 0 }
                        }
                    }
            )
            .onAppear {
                if reduceMotion {
                    angle = 180
                } else {
                    withAnimation(.easeInOut(duration: 0.55)) { angle = 180 }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: "Continue", onContinue)
    }

    private var back: some View {
        LogCardFrame(question: flip.symptom.label.prefix(1).uppercased() + flip.symptom.label.dropFirst(), footer: "tap anywhere to continue") {
            VStack(alignment: .leading, spacing: 10) {
                Text(flip.text)
                    .font(.custom("HelveticaNeue", size: 15))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if flip.showsSupport {
                    supportLine
                }

                Spacer(minLength: 0)

                if let action = flip.action {
                    actionArea(action)
                }

                ForEach(flip.laterActions, id: \.self) { title in
                    CardLink(title: title) {}
                }

                if flip.asksForMatch {
                    matchRow
                }
            }
        }
    }

    private var supportLine: some View {
        let support = SymptomTips.shared.supportLink
        return VStack(alignment: .leading, spacing: 4) {
            Text(support.text)
                .font(.custom("HelveticaNeue", size: 12))
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: support.url) {
                Text(support.linkTitle)
                    .font(.custom("HelveticaNeue-Medium", size: 12))
                    .underline()
                    .foregroundStyle(CrosswordStyle.ink)
            }
        }
    }

    // MARK: - Action

    @ViewBuilder
    private func actionArea(_ action: SymptomTips.Action) -> some View {
        switch actionState {
        case .idle:
            CardLink(title: action.title, emphasized: true) { run(action) }
        case .breathing:
            BreathingCircle(seconds: 60) {
                actionState = .done("That's a minute, just for you.")
            }
            .frame(maxWidth: .infinity)
        case .snackEntry:
            HStack(spacing: 8) {
                TextField("What are you craving?", text: $snack)
                    .font(.custom("HelveticaNeue", size: 14))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .overlay(Rectangle().strokeBorder(.black.opacity(0.35), lineWidth: 0.6))
                    .submitLabel(.done)
                    .onSubmit(saveSnack)
                CardLink(title: "Add", emphasized: true, action: saveSnack)
            }
        case let .done(message):
            Text(message)
                .font(.custom("HelveticaNeue", size: 12))
                .opacity(0.8)
        }
    }

    private func run(_ action: SymptomTips.Action) {
        switch action.kind {
        case .breathe:
            actionState = .breathing
        case .shareSoftDay:
            let image = BouquetSnapshot.image(of: flowers, style: style) ?? UIImage()
            BouquetSharing.presentShareSheet(image, text: action.shareText ?? action.title)
            actionState = .done("Soft day, shared.")
        case .reminder:
            Task {
                let scheduled = await LocalReminders.schedule(action)
                actionState = .done(scheduled ? "Reminder set." : "Turn on notifications for Clutch in Settings to get reminders.")
            }
        case .addSnack:
            actionState = .snackEntry
        }
    }

    private func saveSnack() {
        guard !snack.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        InsightStore.addSnack(snack)
        actionState = .done("Added to your snack list.")
    }

    // MARK: - Does this match you?

    @ViewBuilder
    private var matchRow: some View {
        if let matchAnswer {
            Text(matchAnswer ? "Glad it fits. Thanks." : "Thanks, Clutch will keep learning.")
                .font(.custom("HelveticaNeue", size: 11))
                .opacity(0.7)
        } else {
            HStack(spacing: 8) {
                Text("Does this match you?")
                    .font(.custom("HelveticaNeue", size: 11))
                Spacer(minLength: 0)
                CardLink(title: "Yes") { answerMatch(true) }
                CardLink(title: "No") { answerMatch(false) }
            }
        }
    }

    private func answerMatch(_ matches: Bool) {
        InsightStore.record(.init(
            date: .now,
            insight: "tier\(flip.insight?.tier ?? 0).\(flip.symptom.id)",
            text: flip.text,
            matches: matches
        ))
        withAnimation(.easeInOut(duration: 0.2)) { matchAnswer = matches }
    }
}

/// Front until the turn passes 90°, then the back (mirrored so it reads
/// the right way round).
private struct FlipView<Front: View, Back: View>: View, Animatable {
    var angle: Double
    let front: Front
    let back: Back

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        ZStack {
            if angle < 90 {
                front
            } else {
                back.rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
    }
}

/// A minute of slow breathing: the circle grows for four seconds, shrinks
/// for four.
struct BreathingCircle: View {
    let seconds: Int
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var remaining: Int
    @State private var inhale = false

    init(seconds: Int, onDone: @escaping () -> Void) {
        self.seconds = seconds
        self.onDone = onDone
        _remaining = State(initialValue: seconds)
    }

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(CrosswordStyle.tilePink)
                .overlay(Circle().strokeBorder(.black.opacity(0.35), lineWidth: 0.6))
                .frame(width: 44, height: 44)
                .scaleEffect(reduceMotion ? 1 : (inhale ? 1.25 : 0.7))
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(inhale ? "Breathe in" : "Breathe out")
                    .font(.custom("HelveticaNeue-Medium", size: 14))
                Text("\(remaining)s")
                    .font(.custom("HelveticaNeue", size: 11))
                    .opacity(0.7)
                    .monospacedDigit()
            }
        }
        .task {
            while remaining > 0 {
                if remaining % 4 == 0 || remaining == seconds {
                    withAnimation(.easeInOut(duration: 4)) { inhale.toggle() }
                }
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                remaining -= 1
            }
            onDone()
        }
        .accessibilityElement(children: .combine)
    }
}
