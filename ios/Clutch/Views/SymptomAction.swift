import SwiftUI
import UIKit

/// A symptom's one action on the details page: breathe, share a soft day,
/// set a reminder, or add a snack. Reminders are local notifications.
struct SymptomActionButton: View {
    let action: SymptomTips.Action
    /// Today's bouquet goes on the soft-day share (a picture, no health data).
    let today: DayLog

    @State private var state = ActionState.idle
    @State private var snack = ""

    private enum ActionState: Equatable {
        case idle, breathing, snackEntry
        case done(String)
    }

    var body: some View {
        switch state {
        case .idle:
            Button(action: run) { DetailsChip(title: action.title) }
                .buttonStyle(.plain)
        case .breathing:
            BreathingCircle(seconds: 60) { state = .done("That's a minute, just for you.") }
        case .snackEntry:
            HStack(spacing: 8) {
                TextField("What are you craving?", text: $snack)
                    .font(.custom("DMSans-Light", size: 14))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .overlay(Capsule().strokeBorder(Color.cardRule, lineWidth: 1))
                    .submitLabel(.done)
                    .onSubmit(saveSnack)
                Button(action: saveSnack) { DetailsChip(title: "Add") }
                    .buttonStyle(.plain)
            }
        case let .done(message):
            Text(message).detailsSmall()
        }
    }

    private func run() {
        switch action.kind {
        case .breathe:
            state = .breathing
        case .shareSoftDay:
            let image = BouquetSnapshot.image(of: BouquetGenerator.flowers(for: today), style: BouquetStyle(log: today)) ?? UIImage()
            BouquetSharing.presentShareSheet(image, text: action.shareText ?? action.title)
            state = .done("Soft day, shared.")
        case .reminder:
            Task {
                let scheduled = await LocalReminders.schedule(action)
                state = .done(scheduled ? "Reminder set." : "Turn on notifications for Clutch in Settings to get reminders.")
            }
        case .addSnack:
            state = .snackEntry
        }
    }

    private func saveSnack() {
        guard !snack.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        InsightStore.addSnack(snack)
        state = .done("Added to your snack list.")
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
                    .font(.custom("DMSans-Regular", size: 14))
                    .foregroundStyle(Color.cardInk)
                Text("\(remaining)s")
                    .font(.custom("DMSans-Light", size: 11))
                    .foregroundStyle(Color.cardSoft)
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
