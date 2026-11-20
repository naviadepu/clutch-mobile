import SwiftUI

/// The cloud breathing with her: it swells for four seconds, settles for
/// four. Used on the hard-time screen and in the wind-down.
struct CloudBreathing: View {
    var seconds = 60
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var remaining: Int?
    @State private var inhale = false

    var body: some View {
        VStack(spacing: 14) {
            FuzzyCloud(face: remaining == nil ? .happy : .sleepy)
                .frame(width: 170)
                .scaleEffect(reduceMotion ? 1 : (inhale ? 1.12 : 0.9))
                .frame(height: 150)
            if let remaining {
                Text(inhale ? "Breathe in with me" : "And out\u{2026}")
                    .font(.custom("DMSans-Regular", size: 16))
                    .foregroundStyle(Color.cardInk)
                Text("\(remaining)s")
                    .font(.custom("DMSans-Light", size: 12))
                    .foregroundStyle(Color.cardSoft)
                    .monospacedDigit()
            } else {
                PagePrimaryButton(title: "Breathe with me for a minute", symbol: "wind") { remaining = seconds }
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: remaining == nil) {
            guard remaining != nil else { return }
            while let left = remaining, left > 0 {
                if left % 4 == 0 || left == seconds {
                    withAnimation(.easeInOut(duration: 4)) { inhale.toggle() }
                }
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                remaining = left - 1
            }
            onDone()
        }
        .accessibilityElement(children: .combine)
    }
}

/// Tap the cloud on the Garden: its little home, what it's up to, and the
/// four things it can help with.
struct CloudHomeView: View {
    @State private var open: AppRouter.Route?
    private let moment = MascotMoment.make(at: .now, snapshot: CycleSnapshot.load())

    var body: some View {
        ClutchPage(title: "your cloud", subtitle: moment.line) {
            MascotSceneView(scene: moment.scene, hasFlower: moment.hasFlower, sparkle: moment.sparkle)
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: Color(hex: 0x4A3328).opacity(0.12), radius: 24, y: 12)
                .overlay(alignment: .bottomLeading) {
                    if let caption = moment.caption {
                        Text(caption.uppercased())
                            .font(.custom("DMSans-Regular", size: 10))
                            .tracking(1.2)
                            .foregroundStyle(Color.cardInk)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.white.opacity(0.8), in: Capsule())
                            .padding(12)
                    }
                }

            HStack(spacing: 6) {
                tile("Hard time", "heart.fill", .hardTime)
                tile("Craving", "fork.knife", .cravings)
                tile("Wind down", "moon.stars.fill", .windDown)
                tile("Cycle", "drop.fill", .tracker)
            }
            .padding(.top, 4)
        }
        .sheet(item: $open) { route in
            FeatureScreen(route: route)
        }
    }

    private func tile(_ title: String, _ symbol: String, _ route: AppRouter.Route) -> some View {
        Button { open = route } label: { IconBubble(symbol: symbol, title: title, size: 64) }
            .buttonStyle(.plain)
    }
}

/// The screen for a route, for sheets opened from anywhere.
struct FeatureScreen: View {
    let route: AppRouter.Route

    var body: some View {
        switch route {
        case .tracker: TrackerView()
        case .hardTime: HardTimeView()
        case .cravings: CravingsView()
        case .windDown: WindDownView()
        case .request: RequestView()
        case .importData: ImportView()
        case .cloud, .today: CloudHomeView()
        }
    }
}

/// "I'm having a hard time": breathe with the cloud, one line from her
/// own history, what helped before, someone to tell, and real help.
struct HardTimeView: View {
    @State private var breathed = false
    private let engine: CycleEngine
    private let today: DayLog

    init() {
        let profile = CycleProfile.load() ?? CycleProfile()
        today = DayLogStore.loadOrCreate(for: .now)
        engine = CycleEngine(logs: DayLogStore.allLogs(), profile: profile)
    }

    var body: some View {
        ClutchPage(title: "I've got you", subtitle: "Nothing needs fixing right now.") {
            Group {
                if breathed {
                    VStack(spacing: 12) {
                        FuzzyCloud(face: .happy).frame(width: 170).frame(height: 150)
                        Button { breathed = false } label: { Label("Again", systemImage: "arrow.counterclockwise") }
                            .buttonStyle(.plain)
                            .font(.custom("DMSans-Regular", size: 14))
                            .foregroundStyle(Color.cardInk)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    CloudBreathing { breathed = true }
                }
            }
            .padding(.vertical, 8)

            Text(reassurance)
                .font(.system(size: 17, design: .serif).italic())
                .foregroundStyle(Color.cardInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)

            let ranks = engine.helperRanking.prefix(3)
            if !ranks.isEmpty {
                Text("WHAT HELPED BEFORE").detailsLabel().frame(maxWidth: .infinity)
                HStack(spacing: 8) {
                    ForEach(ranks, id: \.helper) { rank in
                        IconBubble(symbol: LogIcon.helper(rank.helper), title: Self.shortName(rank.helper.phrase), size: 50)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(rank.helper.phrase) helped \(rank.count) of \(rank.outOf) times")
                    }
                }
            }

            Panel {
                HStack(spacing: 6) {
                    ShareLink(item: "Having a soft day today. Could use a little extra kindness.") {
                        IconBubble(symbol: "envelope.fill", title: "Soft note", size: 52)
                    }
                    Link(destination: URL(string: "tel:988")!) { IconBubble(symbol: "phone.fill", title: "Call 988", filled: true, size: 52) }
                    Link(destination: URL(string: "sms:988")!) { IconBubble(symbol: "message.fill", title: "Text 988", size: 52) }
                }
                .buttonStyle(.plain)
                Text("Thinking about hurting yourself, or it's all too much? 988 is free and open 24/7 in the US. Elsewhere, findahelpline.com, or your local emergency number.")
                    .detailsSmall()
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// "a heating pad" -> "Heating pad".
    private static func shortName(_ phrase: String) -> String {
        let bare = phrase.replacingOccurrences(of: #"^(a|an|some|the) "#, with: "", options: .regularExpression)
        return bare.prefix(1).uppercased() + bare.dropFirst()
    }

    private var reassurance: String {
        if case .knownStretch = engine.todayLine(for: today) {
            return InsightCopy.text(for: engine.todayLine(for: today)) + " It's passed every time."
        }
        if let position = engine.position(for: .now), engine.usualHardPositions.contains(position) {
            return "This part of your cycle is usually harder. That's hormones, not you."
        }
        if let day = engine.periodDay(for: .now) {
            return "Period day \(day). Hormones are at their lowest, so feeling low is really common."
        }
        if let offset = engine.backwardOffset(for: .now), offset <= 7 {
            return "Your period's about \(offset) day\(offset == 1 ? "" : "s") away. It usually lifts once it starts."
        }
        return "Hard days happen. It doesn't mean something's wrong with you."
    }
}
