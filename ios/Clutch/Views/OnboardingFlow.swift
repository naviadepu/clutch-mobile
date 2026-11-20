import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The questions after the name scribble, on the blush-to-peach gradient
/// picture, with clear iOS glass answers. Every
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
        .background { OnboardingGradientBackdrop() }
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
        let number = (plan.steps.firstIndex(of: step) ?? 0) + 1
        let total = plan.steps.count + 1
        switch step {
        case .age:
            OnboardingQuestion(title: "How old are you?", step: number, total: total, onBack: back) {
                VStack(spacing: 12) {
                    ForEach(AgeRange.allCases) { range in
                        GlassAnswer(title: range.title, selected: plan.ageRange == range) {
                            answer { plan.ageRange = range }
                        }
                    }
                }
            }

        case .tracker:
            OnboardingQuestion(title: "Do you track your period with another app?", subtitle: "Bring your history and predictions start sharp.", step: number, total: total, onBack: back) {
                VStack(spacing: 12) {
                    ForEach(OnboardingPlan.Tracker.allCases, id: \.self) { tracker in
                        GlassAnswer(title: tracker.title, selected: plan.tracker == tracker) {
                            answer {
                                plan.tracker = tracker
                                if tracker == .none { plan.imported = false }
                            }
                        }
                    }
                }
            }

        case .importHistory:
            OnboardingImportStep(plan: $plan, step: number, total: total, onBack: back, onNext: advance)

        case .lastPeriod:
            OnboardingQuestion(title: "When did your last period start?", step: number, total: total, onBack: back) {
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
            OnboardingQuestion(title: "How long is your cycle?", subtitle: "First day of one period to the first day of the next.", step: number, total: total, onBack: back) {
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
    var total = OnboardingPlan.Step.allCases.count + 1
    let onBack: () -> Void
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(OnboardingStyle.plum)
                        .frame(width: 38, height: 38)
                        .liveGlass(Circle())
                }
                .accessibilityLabel("Back")
                OnboardingProgressBar(step: step, total: total)
                    .id(step)
            }
            .padding(.top, 8)

            VStack(spacing: 10) {
                Text(title)
                    .font(.custom("HelveticaNeue-Medium", size: 30))
                    .tracking(-1)
                    .foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.custom("Quicksand-Regular", size: 15))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .shadow(color: OnboardingStyle.plum.opacity(0.45), radius: 10, y: 2)
            .padding(.top, 48)
            .padding(.bottom, 30)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 10)

            content
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : 22)
                .animation(.spring(response: 0.6, dampingFraction: 0.85).delay(reduceMotion ? 0 : 0.12), value: appeared)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) { appeared = true }
        }
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
                .foregroundStyle(OnboardingStyle.plum)
                .frame(maxWidth: pill ? nil : .infinity)
                .padding(.horizontal, pill ? 24 : 20)
                .padding(.vertical, pill ? 11 : 18)
                .background {
                    if selected { Capsule().fill(.white.opacity(0.92)) }
                }
                .liveGlass(Capsule())
                .overlay { GlassShine(trigger: selected).clipShape(Capsule()).allowsHitTesting(false) }
                .scaleEffect(selected ? 1.02 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selected)
        }
        .buttonStyle(GlassPressStyle())
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
                        .foregroundStyle(OnboardingStyle.plum.opacity(0.6))
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
        .liveGlass(RoundedRectangle(cornerRadius: 30, style: .continuous))
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
            .foregroundStyle(OnboardingStyle.plum)
            .frame(width: 38, height: 38)
            .background(Circle().fill(isSelected ? .white.opacity(0.95) : .white.opacity(0.3)))
            .overlay(Circle().strokeBorder(OnboardingStyle.plum.opacity(isToday && !isSelected ? 0.55 : 0), lineWidth: 1.2))
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
                .foregroundStyle(.white)
                .shadow(color: OnboardingStyle.plum.opacity(0.45), radius: 10, y: 2)
                .padding(.top, 70)

            Spacer(minLength: 12)

            if model.cycleDay != nil {
                CycleWheel(model: model, diameter: 230)
            } else {
                FuzzyCloud(face: .happy).frame(width: 190)
                Text("Tap \u{201C}My period started\u{201D} when it comes, and Clutch will take it from there.")
                    .font(.custom("Quicksand-Regular", size: 15))
                    .foregroundStyle(.white)
                    .shadow(color: OnboardingStyle.plum.opacity(0.45), radius: 6, y: 1)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                    .padding(.top, 12)
            }

            Spacer(minLength: 12)

            Button(action: onStart) {
                Text("Start my garden")
                    .font(.custom("Quicksand-Regular", size: 18))
                    .foregroundStyle(OnboardingStyle.plum)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .liveGlass(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 28)
    }
}

// MARK: - Backdrop

/// The blush-to-peach gradient picture with a fine grain, drifting very
/// slowly so the page feels alive without moving under the words.
struct OnboardingGradientBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Image("onboarding-bg")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(drift ? 1.12 : 1.04)
                    .offset(x: drift ? -10 : 10)
                // A touch of plum keeps white words readable on the pale side.
                LinearGradient(colors: [OnboardingStyle.plum.opacity(0.22), OnboardingStyle.plum.opacity(0.08), OnboardingStyle.plum.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                GrainOverlay().blendMode(.overlay).opacity(0.18)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

extension View {
    /// v1's glass, made of real iOS material so it blurs whatever moves
    /// behind it: a rose tint, light on the top edge, a soft inner glow and
    /// an iridescent rim.
    func liveGlass<S: InsettableShape>(_ shape: S) -> some View {
        background {
            ZStack {
                shape.fill(.ultraThinMaterial)
                // White glass: a milky pane with light across its top.
                shape.fill(.white.opacity(0.32))
                shape.fill(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.08), .clear], startPoint: .top, endPoint: .center))
                shape.strokeBorder(.white.opacity(0.7), lineWidth: 8).blur(radius: 8)
                shape.strokeBorder(
                    AngularGradient(
                        colors: [
                            .white.opacity(0.9),
                            OnboardingStyle.lavender.opacity(0.7),
                            Color(red: 0.72, green: 0.93, blue: 0.88).opacity(0.6),
                            Color(red: 1.0, green: 0.90, blue: 0.68).opacity(0.6),
                            .white.opacity(0.3),
                            .white.opacity(0.9),
                        ],
                        center: .center
                    ),
                    lineWidth: 1
                )
            }
            .clipShape(shape)
            .shadow(color: OnboardingStyle.plum.opacity(0.12), radius: 20, y: 10)
            .allowsHitTesting(false)
        }
        .contentShape(shape)
    }
}

// MARK: - Import

/// Bring her history from her old app: Apple Health (Clue, Flo and most
/// others can save there) or Clue's data download. Skippable; once
/// something lands, the cycle questions are skipped.
struct OnboardingImportStep: View {
    @Binding var plan: OnboardingPlan
    let step: Int
    let total: Int
    let onBack: () -> Void
    let onNext: () -> Void

    @State private var working = false
    @State private var pickingFile = false
    @State private var cycles: Int?
    @State private var problem: String?
    @State private var lockedZip: Data?
    @State private var password = ""

    var body: some View {
        OnboardingQuestion(
            title: cycles == nil ? "Bring your history" : "Got it",
            subtitle: cycles == nil ? hint : nil,
            step: step,
            total: total,
            onBack: onBack
        ) {
            VStack(spacing: 12) {
                if let cycles {
                    VStack(spacing: 2) {
                        Text("\(cycles)")
                            .font(.custom("InterTight-SemiBold", size: 64))
                            .tracking(-2)
                        Text(cycles == 1 ? "cycle imported" : "cycles imported")
                            .font(.custom("Quicksand-Regular", size: 17))
                    }
                    .foregroundStyle(.white)
                    .shadow(color: OnboardingStyle.plum.opacity(0.45), radius: 8, y: 2)
                    .padding(.vertical, 10)
                    GlassAnswer(title: "Continue", selected: true) { onNext() }
                } else {
                    if HealthSync.isAvailable {
                        GlassAnswer(title: "Connect Apple Health", selected: false) { connectHealth() }
                    }
                    if plan.tracker == .clue || plan.tracker == .other {
                        GlassAnswer(title: plan.tracker == .clue ? "Pick my Clue download" : "Pick an export file", selected: false) { pickingFile = true }
                    }
                    if working { ProgressView().tint(.white).padding(.top, 6) }
                    if let problem {
                        Text(problem)
                            .font(.custom("Quicksand-Regular", size: 14))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .shadow(color: OnboardingStyle.plum.opacity(0.5), radius: 4)
                    }
                    GlassAnswer(title: "Skip for now", selected: false, pill: true) { onNext() }
                        .padding(.top, 6)
                }
            }
            .disabled(working)
        }
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.zip, .folder, .json, .commaSeparatedText, .plainText, .data]) { picked in
            if case let .success(url) = picked { importFile(url) }
        }
        .alert("Clue's password", isPresented: Binding(get: { lockedZip != nil }, set: { if !$0 { lockedZip = nil } })) {
            SecureField("Password", text: $password)
            Button("Import") {
                if let zip = lockedZip { importData(zip, password: password) }
                lockedZip = nil
            }
            Button("Cancel", role: .cancel) { lockedZip = nil }
        } message: {
            Text("Clue showed you a password when you asked to download your data.")
        }
    }

    private var hint: String {
        plan.tracker == .clue
            ? "Turn on Apple Health in Clue and connect, or download your data in Clue (Settings \u{203A} Download my data) and pick the zip."
            : "If your app saves to Apple Health (Flo and most do), connect it. You can always do this later."
    }

    private func connectHealth() {
        problem = nil
        working = true
        Task {
            _ = try? await HealthSync.shared.connect()
            working = false
            land(emptyMessage: "Nothing in Apple Health yet. Turn on sharing in your app, or skip for now.")
        }
    }

    private func importFile(_ url: URL) {
        problem = nil
        do {
            importData(try ClueImport.readPicked(url), password: nil)
        } catch {
            problem = "Couldn't open that (\(error.localizedDescription)). Pick the zip from Clue's email."
        }
    }

    private func importData(_ data: Data, password entered: String?) {
        problem = nil
        do {
            let days = try ClueImport.days(from: data, password: entered)
            PeriodImport.merge(days, source: .clue)
            password = ""
            land(emptyMessage: "That file didn't have any periods in it.")
        } catch ZipReader.Failure.needsPassword {
            password = ""
            lockedZip = data
        } catch ZipReader.Failure.wrongPassword {
            problem = "That password didn't work. It's the one Clue showed when you asked for your data."
            password = ""
            lockedZip = data
        } catch ClueImport.Failure.noPeriodData {
            problem = "That file didn't have any periods in it."
        } catch {
            // The reason, so a beta tester can tell us what went wrong.
            problem = "Couldn't read that (\(String(describing: error))). Pick the zip from Clue's email."
        }
    }

    /// Whatever arrived answers the cycle questions.
    private func land(emptyMessage: String) {
        let engine = CycleEngine(logs: DayLogStore.allLogs(), profile: CycleProfile())
        guard let latest = engine.periodStarts.last else {
            problem = emptyMessage
            return
        }
        let lengths = engine.plausibleCycles.map(\.length)
        let average = lengths.isEmpty ? nil : Int((Double(lengths.reduce(0, +)) / Double(lengths.count)).rounded())
        var profile = CycleProfile.load() ?? CycleProfile()
        profile.lastPeriodStart = latest
        if let average { profile.cycleLength = average }
        profile.save()
        withAnimation(.easeInOut(duration: 0.3)) {
            plan.imported = true
            plan.lastPeriodStart = latest
            plan.cycleLength = average
            cycles = lengths.count
        }
    }
}

/// Glass gives a little under a finger.
struct GlassPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? 0.03 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// A band of light that sweeps across the glass once when it's picked.
struct GlassShine: View {
    let trigger: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var x: CGFloat = -1.2

    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: geo.size.width * 0.35)
                .rotationEffect(.degrees(18))
                .offset(x: x * geo.size.width)
                .blendMode(.plusLighter)
        }
        .onChange(of: trigger) { _, on in
            guard on, !reduceMotion else { return }
            x = -0.5
            withAnimation(.easeInOut(duration: 0.7)) { x = 1.2 }
        }
    }
}
