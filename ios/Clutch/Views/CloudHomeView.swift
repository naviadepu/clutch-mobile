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
                tile("Wind down", "moon.stars", .windDown)
                tile("Journal", "book", .journal)
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
        case .journal: JournalView()
        case .windDown: WindDownView()
        case .request: RequestView()
        case .importData: ImportView()
        case .profile: ProfileView(signature: SignatureStore.load())
        case .cloud, .today: CloudHomeView()
        }
    }
}
