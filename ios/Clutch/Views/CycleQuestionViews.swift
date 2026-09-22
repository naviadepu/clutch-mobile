import SwiftUI
import UIKit

// The cycle questions that follow the age screen. Each writes its answer
// into the shared `CycleProfile`; the last one saves it and opens the Garden.

/// "When did your last period start?" — a calendar, or "I don't remember".
struct LastPeriodView: View {
    let signature: UIImage?
    @Binding var profile: CycleProfile

    @State private var date = Calendar.current.startOfDay(for: .now)
    @State private var dontRemember = false
    @State private var goNext = false

    private var earliest: Date {
        Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .distantPast
    }

    var body: some View {
        OnboardingPage(title: "When did your last period start?", step: 2, onNext: next) {
            VStack(spacing: 16) {
                DatePicker("Last period start", selection: $date, in: earliest...Date.now, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(OnboardingStyle.plum)
                    .environment(\.colorScheme, .light)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .opacity(dontRemember ? 0.4 : 1)
                    .auraGlass(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .onChange(of: date) { dontRemember = false }

                GlassChoiceChip(title: "I don't remember", isSelected: dontRemember) {
                    dontRemember.toggle()
                }

                if dontRemember {
                    Text("No worries. Log it when your next period starts, and we'll take it from there.")
                        .font(.custom("Quicksand-Regular", size: 15))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(OnboardingStyle.plum)
                        .padding(.horizontal, 12)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: dontRemember)
        }
        .navigationDestination(isPresented: $goNext) {
            CycleLengthView(signature: signature, profile: $profile)
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func next() {
        profile.lastPeriodStart = dontRemember ? nil : date
        goNext = true
    }
}

/// "How long is your cycle usually?" — 20 to 45 days, or "Not sure".
struct CycleLengthView: View {
    let signature: UIImage?
    @Binding var profile: CycleProfile

    @State private var length = CycleProfile.typicalCycleLength
    @State private var notSure = false
    @State private var goNext = false

    var body: some View {
        OnboardingPage(
            title: "How long is your cycle usually?",
            subtitle: "From the first day of one period to the first day of the next.",
            step: 3,
            onNext: next
        ) {
            NumberQuestion(
                label: "Your cycle",
                range: 20...45,
                value: $length,
                notSure: $notSure,
                notSureNote: "We'll start with a typical \(CycleProfile.typicalCycleLength)-day cycle."
            )
        }
        .navigationDestination(isPresented: $goNext) {
            PeriodLengthView(signature: signature, profile: $profile)
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func next() {
        profile.cycleLength = notSure ? nil : length
        goNext = true
    }
}

/// "How many days does your period usually last?" — 1 to 10, or "Not sure".
struct PeriodLengthView: View {
    let signature: UIImage?
    @Binding var profile: CycleProfile

    @State private var length = CycleProfile.typicalPeriodLength
    @State private var notSure = false
    @State private var goNext = false

    var body: some View {
        OnboardingPage(title: "How many days does your period usually last?", step: 4, onNext: next) {
            NumberQuestion(
                label: "Your period",
                range: 1...10,
                value: $length,
                notSure: $notSure,
                notSureNote: "We'll start with a typical \(CycleProfile.typicalPeriodLength) days."
            )
        }
        .navigationDestination(isPresented: $goNext) {
            BirthControlView(signature: signature, profile: $profile)
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func next() {
        profile.periodLength = notSure ? nil : length
        goNext = true
    }
}

/// "Are you using any birth control?" — a single-choice glass list. Saves
/// the finished profile and opens the Garden.
struct BirthControlView: View {
    let signature: UIImage?
    @Binding var profile: CycleProfile

    @State private var choice: BirthControl?
    @State private var goToGarden = false

    var body: some View {
        OnboardingPage(
            title: "Are you using any birth control?",
            subtitle: "This helps us read your cycle correctly.",
            canContinue: choice != nil,
            step: 5,
            onNext: next
        ) {
            VStack(spacing: 0) {
                ForEach(BirthControl.allCases) { option in
                    Button {
                        choice = option
                    } label: {
                        HStack {
                            Text(option.title)
                                .font(.custom("Quicksand-Regular", size: 16))
                            Spacer()
                            if choice == option {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 13)
                        .background(choice == option ? Color.white.opacity(0.2) : .clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(choice == option ? .isSelected : [])

                    if option != BirthControl.allCases.last {
                        Rectangle()
                            .fill(.white.opacity(0.3))
                            .frame(height: 0.5)
                            .padding(.horizontal, 22)
                    }
                }
            }
            .shadow(color: OnboardingStyle.plum.opacity(0.25), radius: 6, y: 1)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .auraGlass(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .animation(.easeInOut(duration: 0.15), value: choice)
        }
        .navigationDestination(isPresented: $goToGarden) {
            GardenView(signature: signature)
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func next() {
        guard let choice else { return }
        profile.birthControl = choice
        profile.save()
        goToGarden = true
    }
}

/// The dot-scale picker plus a "Not sure" chip. Choosing "Not sure" dims
/// the scale; dragging it again clears the chip.
private struct NumberQuestion: View {
    let label: String
    let range: ClosedRange<Int>
    @Binding var value: Int
    @Binding var notSure: Bool
    let notSureNote: String

    var body: some View {
        VStack(spacing: 16) {
            DotScaleCard(label: label, range: range, value: $value, unit: "days", dimmed: notSure)
                .onChange(of: value) { notSure = false }

            GlassChoiceChip(title: "Not sure", isSelected: notSure) {
                notSure.toggle()
            }

            if notSure {
                Text(notSureNote)
                    .font(.custom("Quicksand-Regular", size: 15))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(OnboardingStyle.plum)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: notSure)
    }
}
