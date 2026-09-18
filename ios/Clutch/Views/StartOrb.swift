import SwiftUI
import UIKit

/// The "start today" control: the iridescent glass bubble from the
/// reference (cut out as-is) with a line of text written around it that
/// turns slowly. No label on the bubble itself.
struct StartOrb: View {
    var text = "tap to begin today  \u{2726}  "
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false
    @State private var float = false

    /// The bubble's ring spans 396 of the halo image's 496 px.
    private let haloSize: CGFloat = 186 * 496 / 396
    private let textRadius: CGFloat = 122

    var body: some View {
        ZStack {
            CircularText(
                text: text,
                radius: textRadius,
                font: UIFont(name: "HelveticaNeue", size: 12) ?? .systemFont(ofSize: 12)
            )
            .foregroundStyle(Color(red: 0.29, green: 0.23, blue: 0.20).opacity(0.7))
            .rotationEffect(.degrees(spin ? 360 : 0))
            .accessibilityHidden(true)

            Button(action: action) {
                Image("orb-halo")
                    .resizable()
                    .frame(width: haloSize, height: haloSize)
                    .contentShape(Circle().inset(by: haloSize * 0.1))
            }
            .buttonStyle(OrbPressStyle())
            .accessibilityLabel("Start today")
        }
        .offset(y: float ? -4 : 4)
        .frame(width: textRadius * 2 + 30, height: textRadius * 2 + 30)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 60).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) { float = true }
        }
    }
}

private struct OrbPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

/// Text laid around a circle, clockwise from the top. The phrase repeats
/// as many times as fits at natural spacing, and any leftover is spread
/// evenly so the ring closes seamlessly.
struct CircularText: View {
    let text: String
    let radius: CGFloat
    let font: UIFont

    var body: some View {
        let unitWidth = text.size(withAttributes: [.font: font]).width
        let repeats = max(1, Int(2 * .pi * radius / (unitWidth * 1.1)))
        let characters = Array(String(repeating: text, count: repeats))
        let widths = characters.map { String($0).size(withAttributes: [.font: font]).width }
        let total = widths.reduce(0, +)
        let gap = max(0, (2 * .pi * radius - total) / CGFloat(max(characters.count, 1)))

        ZStack {
            ForEach(characters.indices, id: \.self) { i in
                let before = widths[..<i].reduce(0, +) + gap * CGFloat(i)
                let angle = (before + widths[i] / 2) / radius

                Text(String(characters[i]))
                    .font(Font(font))
                    .offset(y: -radius)
                    .rotationEffect(.radians(angle))
            }
        }
        .frame(width: radius * 2, height: radius * 2)
    }
}
