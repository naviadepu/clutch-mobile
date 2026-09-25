import SwiftUI
import UIKit

// The cycle questions that follow the age screen. Each writes its answer
// into the shared `CycleProfile`; the payoff screen saves it and opens the
// Garden.

/// "When did your last period start?" — a calendar, or "Not sure".
struct LastPeriodView: View {
    let signature: UIImage?
    @Binding var profile: CycleProfile

    @State private var date = Calendar.current.startOfDay(for: .now)
    @State private var notSure = false
    @State private var goNext = false

    private var earliest: Date {
        Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .distantPast
    }

    var body: some View {
        OnboardingPage(title: "When did your last period start?", step: 3, onNext: next) {
            VStack(spacing: 16) {
                DatePicker("Last period start", selection: $date, in: earliest...Date.now, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(OnboardingStyle.plum)
                    .environment(\.colorScheme, .light)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .opacity(notSure ? 0.4 : 1)
                    .auraGlass(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .onChange(of: date) { notSure = false }

                GlassChoiceChip(title: "Not sure", isSelected: notSure) {
                    notSure.toggle()
                }

                if notSure {
                    Text("No worries. Log it when your next period starts, and Clutch will take it from there.")
                        .font(.custom("Quicksand-Regular", size: 15))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(OnboardingStyle.plum)
                        .padding(.horizontal, 12)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: notSure)
        }
        .navigationDestination(isPresented: $goNext) {
            CycleLengthView(signature: signature, profile: $profile)
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func next() {
        profile.lastPeriodStart = notSure ? nil : date
        goNext = true
    }
}

/// "How long is your cycle usually?" — 20 to 45 days, or "Not sure",
/// which is where it starts.
struct CycleLengthView: View {
    let signature: UIImage?
    @Binding var profile: CycleProfile

    @State private var length = CycleProfile.typicalCycleLength
    @State private var notSure = true
    @State private var goNext = false

    var body: some View {
        OnboardingPage(
            title: "How long is your cycle usually?",
            subtitle: "From the first day of one period to the first day of the next.",
            step: 4,
            onNext: next
        ) {
            NumberQuestion(
                label: "Your cycle",
                range: 20...45,
                value: $length,
                notSure: $notSure,
                notSureTitle: "Not sure, learn it for me",
                notSureNote: "Clutch will learn it from your logs."
            )
        }
        .navigationDestination(isPresented: $goNext) {
            OnboardingPayoffView(signature: signature, profile: $profile)
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func next() {
        profile.cycleLength = notSure ? nil : length
        goNext = true
    }
}

/// The end of onboarding: where she probably is in her cycle, and the
/// first flower of her bouquet. Saves the profile and opens the Garden.
struct OnboardingPayoffView: View {
    let signature: UIImage?
    @Binding var profile: CycleProfile

    @State private var goToGarden = false

    /// Today's first flower — the same one her first answer will grow.
    private let firstFlower: PlantedFlower = {
        var generator = BouquetGenerator(seed: DayLogStore.loadOrCreate(for: .now).seed)
        return generator.next()
    }()

    var body: some View {
        OnboardingPage(title: "You're all set", onNext: finish) {
            VStack(spacing: 18) {
                Bouquet(flowers: [firstFlower], reduceMotion: true, signature: signature)
                    .scaleEffect(0.42, anchor: .bottom)
                    .frame(width: Bouquet.size.width * 0.42, height: Bouquet.size.height * 0.42, alignment: .bottom)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Your first flower")

                VStack(spacing: 8) {
                    Text(phaseTitle)
                        .font(.custom("HelveticaNeue-Medium", size: 20))
                        .tracking(-0.5)
                    Text(phaseNote)
                        .font(.custom("Quicksand-Regular", size: 15))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .shadow(color: OnboardingStyle.plum.opacity(0.25), radius: 6, y: 1)
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
                .auraGlass(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
        }
        .navigationDestination(isPresented: $goToGarden) {
            GardenView(signature: signature)
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var phase: EstimatedPhase? {
        EstimatedPhase(profile: profile, on: .now)
    }

    private var phaseTitle: String {
        phase.map { "Day \($0.cycleDay): \($0.name)" } ?? "Here's your first flower"
    }

    private var phaseNote: String {
        guard let phase else {
            return "Clutch will learn your cycle after your next period. Log a little each day and your bouquet grows."
        }
        let estimate = profile.cycleLength == nil
            ? "An estimate from a typical \(CycleProfile.typicalCycleLength)-day cycle."
            : "An estimate for now."
        return "\(phase.note) \(estimate) Clutch gets more accurate as you log."
    }

    private func finish() {
        profile.onboardingComplete = true
        profile.onboardedOn = Calendar.current.startOfDay(for: .now)
        profile.save()
        goToGarden = true
    }
}

/// A rough phase from her last start and usual length, for the payoff
/// screen only. Plain words, no medical claims.
struct EstimatedPhase: Equatable {
    let cycleDay: Int
    let name: String
    let note: String

    init?(profile: CycleProfile, on date: Date, calendar: Calendar = .current) {
        guard let start = profile.lastPeriodStart else { return nil }
        let length = profile.effectiveCycleLength
        let elapsed = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: date)).day ?? 0
        guard elapsed >= 0 else { return nil }
        let day = elapsed % length + 1
        let ovulation = length - 14
        cycleDay = day
        switch day {
        case ...profile.effectivePeriodLength:
            name = "your period"
            note = "Go easy on yourself these days."
        case ..<(ovulation - 1):
            name = "rising days"
            note = "Energy often builds after a period."
        case (ovulation - 1)...(ovulation + 1):
            name = "mid-cycle"
            note = "Many people feel their strongest around now."
        default:
            name = "pre-period days"
            note = "Some people feel lower or more tired in this stretch."
        }
    }
}

/// The dot-scale picker plus a "Not sure" chip. Choosing "Not sure" dims
/// the scale; dragging it again clears the chip.
private struct NumberQuestion: View {
    let label: String
    let range: ClosedRange<Int>
    @Binding var value: Int
    @Binding var notSure: Bool
    var notSureTitle = "Not sure"
    let notSureNote: String

    var body: some View {
        VStack(spacing: 16) {
            DotScaleCard(label: label, range: range, value: $value, unit: "days", dimmed: notSure)
                .onChange(of: value) { notSure = false }

            GlassChoiceChip(title: notSureTitle, isSelected: notSure) {
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
