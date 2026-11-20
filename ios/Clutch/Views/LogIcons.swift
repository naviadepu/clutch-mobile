import SwiftUI

// Small icons for the daily log's tiles, so an answer reads at a glance
// instead of as a number or a word.

/// A hand-drawn-looking face for mood levels 1 (awful) to 5 (great).
struct MoodFace: View {
    let level: Int
    var size: CGFloat = 22

    var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width
            let line = max(1.2, s * 0.07)
            let style = StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
            let ink = GraphicsContext.Shading.color(CrosswordStyle.ink)

            context.stroke(Path(ellipseIn: CGRect(x: line / 2, y: line / 2, width: s - line, height: s - line)), with: ink, style: style)

            // Eyes: closed happy arcs at 5, dots otherwise.
            let eyeY = s * 0.4
            for eyeX in [s * 0.35, s * 0.65] {
                if level == 5 {
                    var arc = Path()
                    arc.move(to: CGPoint(x: eyeX - s * 0.07, y: eyeY + s * 0.03))
                    arc.addQuadCurve(to: CGPoint(x: eyeX + s * 0.07, y: eyeY + s * 0.03), control: CGPoint(x: eyeX, y: eyeY - s * 0.07))
                    context.stroke(arc, with: ink, style: style)
                } else {
                    let r = line * 0.75
                    context.fill(Path(ellipseIn: CGRect(x: eyeX - r, y: eyeY - r, width: r * 2, height: r * 2)), with: ink)
                }
            }

            // Mouth: frown at 1, smile at 5. Bend is how far the middle drops.
            let bend: CGFloat = [-0.14, -0.07, 0, 0.08, 0.15][min(max(level, 1), 5) - 1] * s
            let mouthY = s * 0.66 - bend / 2
            var mouth = Path()
            mouth.move(to: CGPoint(x: s * 0.32, y: mouthY))
            mouth.addQuadCurve(to: CGPoint(x: s * 0.68, y: mouthY), control: CGPoint(x: s * 0.5, y: mouthY + bend * 2))
            context.stroke(mouth, with: ink, style: style)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

enum LogIcon {
    /// Energy 1 (drained) to 5 (buzzing) as a filling battery.
    static func energy(_ level: Int) -> String {
        ["battery.0percent", "battery.25percent", "battery.50percent", "battery.75percent", "battery.100percent.bolt"][min(max(level, 1), 5) - 1]
    }

    static func symptom(_ id: String) -> String {
        switch id {
        case "anxious": "waveform.path"
        case "low": "cloud.drizzle"
        case "irritable": "flame"
        case "cramps": "bolt.heart"
        case "bloating": "balloon"
        case "headache": "brain.head.profile"
        case "poor-sleep": "moon.zzz"
        case "cravings": "birthday.cake"
        case "stressed": "tornado"
        case "none": "checkmark"
        default: "circle"
        }
    }

    static func helper(_ helper: Helper) -> String {
        switch helper {
        case .nap: "bed.double"
        case .walk: "figure.walk"
        case .heatingPad: "heater.vertical"
        case .painRelief: "pills"
        case .rest: "sofa"
        case .talkedToSomeone: "bubble.left.and.bubble.right"
        case .nothingReally: "minus"
        }
    }

    /// A symbol sized to sit above a tile's label.
    static func image(_ name: String, size: CGFloat = 15) -> AnyView {
        AnyView(Image(systemName: name).font(.system(size: size, weight: .regular)).accessibilityHidden(true))
    }
}
