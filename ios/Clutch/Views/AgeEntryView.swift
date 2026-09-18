import SwiftUI
import UIKit

/// Third screen: asks for age with a draggable dot-scale, styled after the
/// glowing wellness-tracker card look — a dark blurred glow rides behind the
/// scale to mark the current position, and the active dot lifts with a
/// shadow while it's being dragged.
struct AgeEntryView: View {
    let signature: UIImage?

    @State private var age: Double = 22
    @State private var isDragging = false
    @State private var goToGarden = false

    init(signature: UIImage? = nil) {
        self.signature = signature
    }

    private let ageRange: ClosedRange<Double> = 13...70
    private let dotCount = 11

    var body: some View {
        ZStack {
            backgroundGlow

            VStack(spacing: 32) {
                Text("How old are you?")
                    .font(.custom("PlayfairDisplay-SemiBold", size: 26))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 2)

                card
                    .frame(height: 250)
            }
            .padding(.horizontal, 28)
        }
        .overlay(alignment: .bottomTrailing) {
            // TODO: the cycle-date and signature onboarding steps belong between
            // this screen and the Garden — out of scope for the Garden brief, so
            // this jumps straight there for now.
            Button {
                goToGarden = true
            } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(red: 0.10, green: 0.10, blue: 0.12))
                    .frame(width: 52, height: 52)
                    .background(.white, in: Circle())
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            }
            .padding(24)
        }
        .navigationDestination(isPresented: $goToGarden) {
            GardenView(signature: signature)
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var backgroundGlow: some View {
        RadialGradient(
            colors: [
                Color(red: 0.62, green: 0.22, blue: 0.34),
                Color.strawberry.opacity(0.85),
                Color(red: 0.86, green: 0.70, blue: 0.78),
            ],
            center: .center,
            startRadius: 20,
            endRadius: 460
        )
        .ignoresSafeArea()
    }

    private var card: some View {
        ZStack {
            // Magenta bleed that escapes the card's own rounded rect, echoing
            // the reference's glow-through-glass look.
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.62, green: 0.16, blue: 0.36).opacity(0.95),
                            Color.strawberry.opacity(0.55),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 6,
                        endRadius: 200
                    )
                )
                .padding(-34)
                .blur(radius: 44)

            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.82, green: 0.47, blue: 0.63).opacity(0.55),
                            Color(red: 0.55, green: 0.20, blue: 0.40).opacity(0.55),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 22) {
                Text("Your age")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))

                GeometryReader { geo in
                    dotTrack(width: geo.size.width)
                }
                .frame(height: 60)

                HStack(alignment: .lastTextBaseline, spacing: 5) {
                    Text("\(Int(age))")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                    Text("yrs")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .foregroundStyle(.white)
            }
            .padding(26)
        }
    }

    private func dotTrack(width: CGFloat) -> some View {
        let fraction = (age - ageRange.lowerBound) / (ageRange.upperBound - ageRange.lowerBound)
        let dotSpacing = width / CGFloat(dotCount - 1)
        let selectedIndex = Int((fraction * Double(dotCount - 1)).rounded())
        let selectedX = CGFloat(selectedIndex) * dotSpacing

        let glowSize: CGFloat = isDragging ? 100 : 76

        return ZStack(alignment: .leading) {
            // The glow that trails the active dot, echoing the reference card's
            // dark-to-magenta blob sitting behind the scale.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .black.opacity(isDragging ? 0.75 : 0.6),
                            Color(red: 0.35, green: 0.05, blue: 0.2).opacity(0.5),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: glowSize / 2
                    )
                )
                .frame(width: glowSize, height: glowSize)
                .blur(radius: isDragging ? 10 : 8)
                .offset(x: selectedX - glowSize / 2)

            ForEach(0..<dotCount, id: \.self) { index in
                let distance = abs(index - selectedIndex)
                let isSelected = distance == 0
                let lifted = isSelected && isDragging
                // Sizes taper away from the selected dot, matching the
                // reference scale's bell-curve silhouette.
                let size: CGFloat = {
                    if isSelected { return isDragging ? 26 : 14 }
                    switch distance {
                    case 1: return 10
                    case 2: return 8
                    default: return 6
                    }
                }()

                ZStack {
                    if lifted {
                        SparkleBurst()
                    }

                    Circle()
                        .fill(.white)
                        .frame(width: size, height: size)
                        // Dark drop shadow underneath — reads as the dot lifting off the track.
                        .shadow(color: .black.opacity(lifted ? 0.55 : 0), radius: lifted ? 14 : 0, y: lifted ? 9 : 0)
                        // A tinted glimmer plus a white halo — together they read as a glittery shadow.
                        .shadow(color: Color.strawberry.opacity(lifted ? 0.9 : 0), radius: lifted ? 9 : 0)
                        .shadow(color: .white.opacity(lifted ? 0.85 : 0), radius: lifted ? 16 : 0)
                }
                .offset(
                    x: CGFloat(index) * dotSpacing - size / 2,
                    y: lifted ? -7 : 0
                )
            }
        }
        .frame(width: width, height: 60, alignment: .leading)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    isDragging = true
                    let clampedX = min(max(value.location.x, 0), width)
                    let dragFraction = clampedX / width
                    let newAge = ageRange.lowerBound + dragFraction * (ageRange.upperBound - ageRange.lowerBound)
                    age = newAge.rounded()
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: selectedIndex)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isDragging)
    }
}

/// A handful of twinkling sparkles scattered around the dragger while it's
/// lifted, each on its own staggered timer so the glitter reads as random
/// rather than a single pulsing glow.
private struct SparkleBurst: View {
    @State private var twinkle = false

    private struct Spark {
        let dx: CGFloat
        let dy: CGFloat
        let size: CGFloat
        let delay: Double
    }

    private let sparks: [Spark] = [
        .init(dx: -22, dy: -14, size: 7, delay: 0.00),
        .init(dx: 18, dy: -20, size: 5, delay: 0.12),
        .init(dx: 26, dy: 6, size: 6, delay: 0.24),
        .init(dx: -18, dy: 16, size: 5, delay: 0.08),
        .init(dx: 5, dy: -27, size: 4, delay: 0.30),
        .init(dx: -6, dy: 24, size: 6, delay: 0.18),
    ]

    var body: some View {
        ZStack {
            ForEach(sparks.indices, id: \.self) { i in
                let s = sparks[i]
                Image(systemName: "sparkle")
                    .font(.system(size: s.size, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .white.opacity(0.9), radius: 3)
                    .offset(x: s.dx, y: s.dy)
                    .opacity(twinkle ? 1 : 0.15)
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

#Preview {
    AgeEntryView()
}
