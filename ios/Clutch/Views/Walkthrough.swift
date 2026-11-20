import SwiftUI

/// The first visit to the home screen: the cloud points out each part once
/// (check-in, cycle, free pads, bouquets, and itself). Tap to go on; Skip
/// ends it. Shown once.
enum WalkthroughStep: Int, CaseIterable {
    case checkIn, cycle, freePads, bouquets, cloud

    var line: String {
        switch self {
        case .checkIn: "Check in here every day. Each answer grows a flower!"
        case .cycle: "All things cycle: where you're at and when your period's coming."
        case .freePads: "Out of pads? Find free ones near you, and let everyone know what's stocked."
        case .bouquets: "Every bouquet you've grown, all in one place."
        case .cloud: "And this is me! Tap me whenever you need to wind down or journal."
        }
    }

    var next: WalkthroughStep? { WalkthroughStep(rawValue: rawValue + 1) }
}

enum Walkthrough {
    private static let key = "walkthrough.done"

    static var isDone: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

struct WalkthroughAnchorKey: PreferenceKey {
    static let defaultValue: [WalkthroughStep: Anchor<CGRect>] = [:]

    static func reduce(value: inout [WalkthroughStep: Anchor<CGRect>], nextValue: () -> [WalkthroughStep: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Marks the view the cloud points at for this step.
    func walkthroughTarget(_ step: WalkthroughStep) -> some View {
        anchorPreference(key: WalkthroughAnchorKey.self, value: .bounds) { [step: $0] }
    }
}

/// The dimmed screen with a soft spotlight on the current target, and the
/// cloud's speech bubble beside it.
struct WalkthroughOverlay: View {
    let anchors: [WalkthroughStep: Anchor<CGRect>]
    @Binding var step: WalkthroughStep?

    var body: some View {
        GeometryReader { geo in
            if let step, anchors[step] == nil {
                // That part isn't on screen right now (say the day's check-in
                // is already done): on to the next tip. Waits a beat first, so
                // a target that just hasn't been measured yet isn't skipped.
                Color.clear.task(id: step) {
                    try? await Task.sleep(for: .milliseconds(600))
                    if !Task.isCancelled { advance() }
                }
            } else if let step, let anchor = anchors[step] {
                let target = geo[anchor].insetBy(dx: -10, dy: -10)
                let below = target.midY < geo.size.height * 0.45
                ZStack {
                    Path { path in
                        path.addRect(CGRect(origin: .zero, size: geo.size).insetBy(dx: -100, dy: -100))
                        path.addRoundedRect(in: target, cornerSize: CGSize(width: 22, height: 22))
                    }
                    .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))

                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.white.opacity(0.9), lineWidth: 1.5)
                        .frame(width: target.width, height: target.height)
                        .position(x: target.midX, y: target.midY)

                    bubble(step)
                        .frame(width: min(geo.size.width - 40, 330))
                        .position(
                            x: geo.size.width / 2,
                            y: below ? min(target.maxY + 95, geo.size.height - 110) : max(target.minY - 95, 120)
                        )
                }
                .contentShape(Rectangle())
                .onTapGesture { advance() }
                .overlay(alignment: .topTrailing) {
                    Button("Skip") { finish() }
                        .font(.custom("DMSans-Regular", size: 15))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.trailing, 20)
                        .padding(.top, 60)
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.35), value: step)
            }
        }
        .ignoresSafeArea()
    }

    private func bubble(_ step: WalkthroughStep) -> some View {
        HStack(alignment: .center, spacing: 10) {
            FuzzyCloud(face: .happy).frame(width: 62)
            VStack(alignment: .leading, spacing: 10) {
                Text(step.line)
                    .font(.custom("DMSans-Regular", size: 15))
                    .foregroundStyle(Color.cardInk)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    HStack(spacing: 5) {
                        ForEach(WalkthroughStep.allCases, id: \.self) { dot in
                            Circle()
                                .fill(dot == step ? Color(hex: 0xE58DAA) : Color.cardRule)
                                .frame(width: 6, height: 6)
                        }
                    }
                    Spacer()
                    Text(step.next == nil ? "Got it" : "Next")
                        .font(.custom("DMSans-Regular", size: 14))
                        .foregroundStyle(Color.cardInk)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.strawberry, in: Capsule())
                }
            }
        }
        .padding(14)
        .background(Color.cream, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double-tap for the next tip")
    }

    private func advance() {
        withAnimation(.easeInOut(duration: 0.35)) {
            if let next = step?.next { step = next } else { finish() }
        }
    }

    private func finish() {
        Walkthrough.isDone = true
        withAnimation(.easeInOut(duration: 0.3)) { step = nil }
    }
}
