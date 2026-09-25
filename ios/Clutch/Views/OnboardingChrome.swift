import SwiftUI

/// Shared look for the onboarding questions: the speed-streaked aura page,
/// a Helvetica heading, frosted glass that refracts the page artwork, a glass
/// "next" arrow, and the dot-scale number picker.
enum OnboardingStyle {
    static let plum = Color(red: 0.42, green: 0.16, blue: 0.29)
    static let lavender = Color(red: 0.78, green: 0.70, blue: 0.95)
}

private struct AuraPageSizeKey: EnvironmentKey {
    static let defaultValue: CGSize = .zero
}

extension EnvironmentValues {
    /// Full-screen size of the aura artwork, so glass can line its blurred
    /// copy up with the page behind it.
    var auraPageSize: CGSize {
        get { self[AuraPageSizeKey.self] }
        set { self[AuraPageSizeKey.self] = newValue }
    }
}

struct AuraArtwork: View {
    let size: CGSize

    var body: some View {
        Image("aura-bg")
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
    }
}

/// How far through the questions each screen is. Name is question 1 but
/// its screen is the scribble canvas, with no bar; the welcome, payoff and
/// Garden screens aren't questions.
enum OnboardingProgress {
    static let total = 4
}

/// One onboarding question on the aura page, with a glass arrow to move on
/// and, when it's one of the numbered questions, a progress bar on top.
struct OnboardingPage<Content: View>: View {
    let title: String
    var subtitle: String?
    var canContinue = true
    /// Which question this is, 1-based. `nil` hides the progress bar.
    var step: Int?
    let onNext: () -> Void
    @ViewBuilder let content: Content

    @State private var pageSize: CGSize = .zero

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.custom("HelveticaNeue-Medium", size: 30))
                .tracking(-1)
                .multilineTextAlignment(.center)
                .foregroundStyle(OnboardingStyle.plum)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle {
                Text(subtitle)
                    .font(.custom("Quicksand-Regular", size: 15))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(OnboardingStyle.plum.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }

            content
                .padding(.top, 22)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            GeometryReader { geo in
                ZStack {
                    AuraArtwork(size: geo.size)
                    GrainOverlay()
                        .blendMode(.overlay)
                        .opacity(0.22)
                }
                .onAppear { pageSize = geo.size }
                .onChange(of: geo.size) { _, newSize in pageSize = newSize }
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .bottomTrailing) {
            Button(action: onNext) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .auraGlass(Circle(), blur: 14)
            }
            .disabled(!canContinue)
            .opacity(canContinue ? 1 : 0.45)
            .padding(24)
            .accessibilityLabel("Next")
        }
        .overlay(alignment: .top) {
            if let step {
                OnboardingProgressBar(step: step, total: OnboardingProgress.total)
                    .padding(.horizontal, 28)
                    .padding(.top, 8)
            }
        }
        .environment(\.auraPageSize, pageSize)
    }
}

/// A hairline bar under the status bar: a barely-there blush track with a
/// blush-to-lavender fill that eases along as each question is answered.
struct OnboardingProgressBar: View {
    let step: Int
    let total: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fraction: CGFloat

    init(step: Int, total: Int) {
        self.step = step
        self.total = total
        // Starts where the question before it left off — a little along
        // already on the first one — then eases to this step's place.
        _fraction = State(initialValue: step <= 1 ? 0.08 : CGFloat(step - 1) / CGFloat(total))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.strawberry.opacity(0.3))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xF7B3C6), OnboardingStyle.lavender],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(geo.size.width * fraction, 4))
            }
        }
        .frame(height: 4)
        .onAppear {
            let target = CGFloat(step) / CGFloat(total)
            if reduceMotion {
                fraction = target
            } else {
                withAnimation(.easeOut(duration: 0.4)) { fraction = target }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Onboarding progress, step \(step) of \(total)")
    }
}

// MARK: - Glass

/// Frosted glass: a blurred, slightly deepened copy of the page artwork
/// aligned under the shape, a bright inner rim, and an iridescent edge.
private struct AuraGlass<S: InsettableShape>: View {
    let shape: S
    let blur: CGFloat

    @Environment(\.auraPageSize) private var pageSize

    var body: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .global)
            ZStack {
                AuraArtwork(size: pageSize)
                    .offset(x: -frame.minX, y: -frame.minY)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    .blur(radius: blur, opaque: true)
                    .saturation(1.15)

                // Rose tint so white type reads on the pale aura.
                shape.fill(OnboardingStyle.plum.opacity(0.22))

                // Light falling on the top of the pane.
                shape.fill(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .white.opacity(0.04), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )

                // Thick glass glows at its edges.
                shape
                    .strokeBorder(.white.opacity(0.55), lineWidth: 10)
                    .blur(radius: 9)

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
        }
        .shadow(color: OnboardingStyle.plum.opacity(0.10), radius: 22, y: 10)
    }
}

extension View {
    /// The glass is decoration only. Its blurred artwork is a full-page
    /// image offset under the shape, and `clipShape` hides the overflow but
    /// doesn't stop it catching touches — left hit-testable, the "next"
    /// arrow's glass swallowed taps and drags meant for the calendar and
    /// sliders. So the glass takes no touches, and the view is hit only
    /// within its own shape.
    func auraGlass<S: InsettableShape>(_ shape: S, blur: CGFloat = 22) -> some View {
        background { AuraGlass(shape: shape, blur: blur).allowsHitTesting(false) }
            .contentShape(shape)
    }
}

/// A glass pill for "Not sure" / "I don't remember" style answers; fills
/// with white when chosen.
struct GlassChoiceChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.custom("Quicksand-Regular", size: 15))
                .foregroundStyle(isSelected ? OnboardingStyle.plum : .white)
                .padding(.horizontal, 22)
                .padding(.vertical, 11)
                .background {
                    if isSelected {
                        Capsule().fill(.white.opacity(0.9))
                    }
                }
                .auraGlass(Capsule(), blur: 14)
                .shadow(color: OnboardingStyle.plum.opacity(0.25), radius: isSelected ? 0 : 4, y: 1)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

// MARK: - Dot-scale picker

/// A glass card with a draggable dot scale and the value in dot-matrix
/// numerals. Sizes taper around the selected dot; a glass ring marks it.
struct DotScaleCard: View {
    let label: String
    let range: ClosedRange<Int>
    @Binding var value: Int
    let unit: String
    var trailingNote: String?
    var dimmed = false

    @State private var isDragging = false

    private var dotCount: Int { min(11, range.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.custom("Quicksand-Regular", size: 16))
                Spacer()
                Text("\(range.lowerBound) – \(range.upperBound)")
                    .font(.custom("Quicksand-Light", size: 14))
                    .opacity(0.9)
            }

            Spacer(minLength: 0)

            GeometryReader { geo in
                dotTrack(width: geo.size.width)
            }
            .frame(height: 56)

            Spacer(minLength: 0)

            HStack(alignment: .lastTextBaseline) {
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text("\(value)")
                        .font(.custom("DotoRounded-Medium", size: 68))
                        .contentTransition(.numericText(value: Double(value)))
                    Text(unit)
                        .font(.custom("Quicksand-Light", size: 16))
                        .opacity(0.9)
                }
                Spacer()
                if let trailingNote {
                    Text(trailingNote)
                        .font(.custom("Quicksand-Light", size: 14))
                        .opacity(0.9)
                }
            }
        }
        .foregroundStyle(.white)
        .shadow(color: OnboardingStyle.plum.opacity(0.25), radius: 6, y: 1)
        .opacity(dimmed ? 0.45 : 1)
        .padding(.horizontal, 26)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .frame(height: 260)
        .auraGlass(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: dimmed)
    }

    private func dotTrack(width: CGFloat) -> some View {
        let span = Double(range.upperBound - range.lowerBound)
        let fraction = span > 0 ? Double(value - range.lowerBound) / span : 0
        let dotSpacing = width / CGFloat(dotCount - 1)
        let selectedIndex = Int((fraction * Double(dotCount - 1)).rounded())
        let selectedX = CGFloat(fraction) * width
        let markerSize: CGFloat = isDragging ? 38 : 32

        return ZStack(alignment: .leading) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0), .white.opacity(0.55), .white.opacity(0.55), .white.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: width, height: 0.75)

            ForEach(0..<dotCount, id: \.self) { index in
                let distance = abs(index - selectedIndex)
                let size: CGFloat = distance == 1 ? 6 : (distance == 2 ? 5 : 4)

                if distance != 0 {
                    Circle()
                        .fill(.white.opacity(distance <= 2 ? 1 : 0.8))
                        .frame(width: size, height: size)
                        .offset(x: CGFloat(index) * dotSpacing - size / 2)
                }
            }

            // Glass ring marker for the selected value.
            ZStack {
                if isDragging {
                    SparkleBurst()
                }
                Circle()
                    .fill(.white.opacity(0.18))
                Circle()
                    .strokeBorder(.white.opacity(0.9), lineWidth: 0.75)
                Circle()
                    .strokeBorder(.white.opacity(0.4), lineWidth: 0.5)
                    .padding(5)
                Circle()
                    .fill(.white)
                    .frame(width: 8, height: 8)
                    .shadow(color: .white.opacity(0.9), radius: 4)
            }
            .frame(width: markerSize, height: markerSize)
            .offset(x: selectedX - markerSize / 2)
        }
        .frame(width: width, height: 56, alignment: .leading)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    isDragging = true
                    let clamped = min(max(drag.location.x, 0), width) / width
                    let newValue = range.lowerBound + Int((clamped * span).rounded())
                    guard newValue != value else { return }
                    withAnimation(.snappy(duration: 0.2)) { value = newValue }
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: value)
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isDragging)
    }
}

/// A handful of twinkling sparkles around the marker while it's being
/// dragged, each on its own staggered timer so the glitter reads as random.
private struct SparkleBurst: View {
    @State private var twinkle = false

    private struct Spark {
        let dx: CGFloat
        let dy: CGFloat
        let size: CGFloat
        let delay: Double
    }

    private let sparks: [Spark] = [
        .init(dx: -26, dy: -14, size: 6, delay: 0.00),
        .init(dx: 22, dy: -20, size: 4, delay: 0.12),
        .init(dx: 28, dy: 8, size: 5, delay: 0.24),
        .init(dx: -22, dy: 16, size: 4, delay: 0.08),
    ]

    var body: some View {
        ZStack {
            ForEach(sparks.indices, id: \.self) { i in
                let s = sparks[i]
                Image(systemName: "sparkle")
                    .font(.system(size: s.size, weight: .light))
                    .foregroundStyle(.white)
                    .offset(x: s.dx, y: s.dy)
                    .opacity(twinkle ? 0.9 : 0.1)
                    .scaleEffect(twinkle ? 1 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.7).repeatForever(autoreverses: true).delay(s.delay),
                        value: twinkle
                    )
            }
        }
        .allowsHitTesting(false)
        .onAppear { twinkle = true }
    }
}
