import SwiftUI
import UIKit

/// The questions after the name scribble, on v1's clean aura gradient
/// with the iridescent orb glowing in the middle. Answers are v1's
/// transparent glass, which refracts the page (orb included). Every
/// question is one tap and moves on by itself; "Not sure" is an answer.
/// Ends on her own cycle wheel.
struct OnboardingFlow: View {
    let signature: UIImage?

    @Environment(\.dismiss) private var dismiss
    @State private var plan = OnboardingPlan()
    @State private var step: OnboardingPlan.Step = .age
    @State private var forward = true
    @State private var done = false
    @State private var goToGarden = false
    @State private var pageSize: CGSize = .zero

    init(signature: UIImage?, startAt step: OnboardingPlan.Step = .age, ready: Bool = false) {
        self.signature = signature
        _step = State(initialValue: step)
        _done = State(initialValue: ready)
    }

    var body: some View {
        ZStack {
            Group {
                if done {
                    OnboardingReady(onStart: finish)
                } else {
                    page(for: step)
                }
            }
            .id(done ? "done" : step.rawValue)
            .transition(.asymmetric(
                insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
            ))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            GeometryReader { geo in
                ZStack {
                    AuraArtwork(size: geo.size)
                    GrainOverlay().blendMode(.overlay).opacity(0.2)
                }
                .onAppear { pageSize = geo.size }
                .onChange(of: geo.size) { _, size in pageSize = size }
            }
            .ignoresSafeArea()
        }
        .environment(\.auraPageSize, pageSize)
        .environment(\.auraShowsOrb, true)
        .navigationDestination(isPresented: $goToGarden) {
            GardenView(signature: signature)
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Navigation

    private func advance() {
        forward = true
        withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
            if let next = plan.step(after: step) {
                step = next
            } else {
                var profile = CycleProfile.load() ?? CycleProfile()
                plan.apply(to: &profile)
                profile.save()
                done = true
            }
        }
    }

    private func back() {
        forward = false
        if let previous = plan.step(before: step) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { step = previous }
        } else {
            dismiss()
        }
    }

    /// A beat so she sees her pick land, then on.
    private func answer(_ apply: () -> Void) {
        apply()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { advance() }
    }

    private func finish() {
        var profile = CycleProfile.load() ?? CycleProfile()
        profile.onboardingComplete = true
        profile.onboardedOn = Calendar.current.startOfDay(for: .now)
        profile.save()
        WidgetBridge.refresh()
        goToGarden = true
    }

    // MARK: Pages

    @ViewBuilder
    private func page(for step: OnboardingPlan.Step) -> some View {
        let number = (OnboardingPlan.Step.allCases.firstIndex(of: step) ?? 0) + 1
        switch step {
        case .age:
            OnboardingQuestion(title: "How old are you?", step: number, onBack: back) {
                VStack(spacing: 12) {
                    ForEach(AgeRange.allCases) { range in
                        GlassAnswer(title: range.title, selected: plan.ageRange == range) {
                            answer { plan.ageRange = range }
                        }
                    }
                }
            }

        case .lastPeriod:
            OnboardingQuestion(title: "When did your last period start?", step: number, onBack: back) {
                VStack(spacing: 14) {
                    RecentDaysPicker(selected: plan.lastPeriodStart) { day in
                        answer {
                            plan.lastPeriodStart = day
                            plan.lastPeriodNotSure = false
                        }
                    }
                    GlassAnswer(title: "Not sure", selected: plan.lastPeriodNotSure, pill: true) {
                        answer {
                            plan.lastPeriodStart = nil
                            plan.lastPeriodNotSure = true
                        }
                    }
                }
            }

        case .cycleLength:
            OnboardingQuestion(title: "How long is your cycle?", subtitle: "First day of one period to the first day of the next.", step: number, onBack: back) {
                VStack(spacing: 12) {
                    ForEach(Self.cycleChoices, id: \.days) { choice in
                        GlassAnswer(title: choice.title, selected: plan.cycleLength == choice.days) {
                            answer {
                                plan.cycleLength = choice.days
                                plan.cycleLengthNotSure = false
                            }
                        }
                    }
                    GlassAnswer(title: "Not sure", selected: plan.cycleLengthNotSure, pill: true) {
                        answer {
                            plan.cycleLength = nil
                            plan.cycleLengthNotSure = true
                        }
                    }
                }
            }
        }
    }

    private static let cycleChoices: [(title: String, days: Int)] = [
        ("Under 26 days", 24), ("26 to 32 days", 29), ("Over 32 days", 35),
    ]
}

// MARK: - Question page

/// v1's page: the blush-to-lavender progress line, a centered plum
/// heading, and the answers below.
struct OnboardingQuestion<Content: View>: View {
    let title: String
    var subtitle: String?
    let step: Int
    let onBack: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.white)
                        .shadow(color: OnboardingStyle.plum.opacity(0.5), radius: 3)
                        .frame(width: 38, height: 38)
                        .auraGlass(Circle(), blur: 14)
                }
                .accessibilityLabel("Back")
                OnboardingProgressBar(step: step, total: OnboardingPlan.Step.allCases.count + 1)
                    .id(step)
            }
            .padding(.top, 8)

            VStack(spacing: 10) {
                Text(title)
                    .font(.custom("HelveticaNeue-Medium", size: 30))
                    .tracking(-1)
                    .foregroundStyle(OnboardingStyle.plum)
                if let subtitle {
                    Text(subtitle)
                        .font(.custom("Quicksand-Regular", size: 15))
                        .foregroundStyle(OnboardingStyle.plum.opacity(0.75))
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 48)
            .padding(.bottom, 30)

            content

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
    }
}

/// An answer in v1's glass: clear, refracting the page, with an
/// iridescent rim. Chosen, it fills with white.
struct GlassAnswer: View {
    let title: String
    let selected: Bool
    /// A smaller pill, for "Not sure".
    var pill = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.custom("Quicksand-Regular", size: pill ? 15 : 18))
                .foregroundStyle(selected ? OnboardingStyle.plum : .white)
                .shadow(color: OnboardingStyle.plum.opacity(selected ? 0 : 0.5), radius: 4, y: 1)
                .frame(maxWidth: pill ? nil : .infinity)
                .padding(.horizontal, pill ? 24 : 20)
                .padding(.vertical, pill ? 11 : 18)
                .background {
                    if selected { Capsule().fill(.white.opacity(0.92)) }
                }
                .auraGlass(Capsule(), blur: 16)
                .scaleEffect(selected ? 1.02 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Last period

/// The last five weeks as clear glass days, so she taps instead of working
/// a date picker. Today has a ring.
struct RecentDaysPicker: View {
    let selected: Date?
    let onPick: (Date) -> Void

    private let calendar = Calendar.current

    var body: some View {
        let today = calendar.startOfDay(for: .now)
        let days = Self.days(endingOn: today, calendar: calendar)
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(Array(calendar.veryShortStandaloneWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.custom("Quicksand-Regular", size: 12))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                ForEach(days.indices, id: \.self) { i in
                    if let day = days[i] { cell(day, today: today) } else { Color.clear.frame(height: 38) }
                }
            }
        }
        .padding(16)
        .auraGlass(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private func cell(_ day: Date, today: Date) -> some View {
        let isSelected = selected.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let isToday = calendar.isDate(day, inSameDayAs: today)
        let isFirst = calendar.component(.day, from: day) == 1
        return Button { onPick(day) } label: {
            VStack(spacing: 0) {
                if isFirst {
                    Text(day.formatted(.dateTime.month(.abbreviated)).uppercased())
                        .font(.custom("Quicksand-Regular", size: 7))
                }
                Text("\(calendar.component(.day, from: day))")
                    .font(.custom("Quicksand-Regular", size: 15))
            }
            .foregroundStyle(isSelected ? OnboardingStyle.plum : .white)
            .frame(width: 38, height: 38)
            .background(Circle().fill(isSelected ? .white.opacity(0.95) : .white.opacity(0.12)))
            .overlay(Circle().strokeBorder(.white.opacity(isToday && !isSelected ? 0.9 : 0), lineWidth: 1.2))
            .scaleEffect(isSelected ? 1.08 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + (isToday ? ", today" : ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Five weeks back from the end of this week, with blanks after today.
    static func days(endingOn today: Date, calendar: Calendar) -> [Date?] {
        let weekday = (calendar.component(.weekday, from: today) - calendar.firstWeekday + 7) % 7
        guard let weekStart = calendar.date(byAdding: .day, value: -weekday, to: today),
              let first = calendar.date(byAdding: .day, value: -28, to: weekStart) else { return [] }
        return (0..<35).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: first) else { return nil }
            return day <= today ? day : nil
        }
    }
}

// MARK: - Ready

/// Her answers, used straight away: her cycle wheel when Clutch knows her
/// last period, then into the Garden.
struct OnboardingReady: View {
    let onStart: () -> Void

    @StateObject private var model = TrackerModel()

    var body: some View {
        VStack(spacing: 0) {
            Text("You're all set")
                .font(.custom("HelveticaNeue-Medium", size: 30))
                .tracking(-1)
                .foregroundStyle(OnboardingStyle.plum)
                .padding(.top, 70)

            Spacer(minLength: 12)

            if model.cycleDay != nil {
                CycleWheel(model: model, diameter: 230)
            } else {
                FuzzyCloud(face: .happy).frame(width: 190)
                Text("Tap \u{201C}My period started\u{201D} when it comes, and Clutch will take it from there.")
                    .font(.custom("Quicksand-Regular", size: 15))
                    .foregroundStyle(OnboardingStyle.plum)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                    .padding(.top, 12)
            }

            Spacer(minLength: 12)

            Button(action: onStart) {
                Text("Start my garden")
                    .font(.custom("Quicksand-Regular", size: 18))
                    .foregroundStyle(.white)
                    .shadow(color: OnboardingStyle.plum.opacity(0.3), radius: 3, y: 1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .auraGlass(Capsule(), blur: 16)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 28)
    }
}
