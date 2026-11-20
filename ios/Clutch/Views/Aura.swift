import SwiftUI

/// The Garden's page: a soft pink gradient behind the bouquet.
struct AuraBackground: View {
    var body: some View {
        BlushGradient()
            .ignoresSafeArea()
    }
}

/// A very pale blush glow in the middle, where the bouquet stands, deepening
/// to warmer rose toward the edges and the bottom, with a whisper of grain
/// that also keeps the gradient from banding. Shared by the Garden and the
/// bouquet snapshots, so shares match the screen.
struct BlushGradient: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(hex: 0xE8A9BA)

                EllipticalGradient(
                    stops: [
                        .init(color: Color(hex: 0xFDF1F3), location: 0.0),
                        .init(color: Color(hex: 0xFAE3E9), location: 0.22),
                        .init(color: Color(hex: 0xF5D0DA), location: 0.45),
                        .init(color: Color(hex: 0xEFBDCA), location: 0.7),
                        .init(color: Color(hex: 0xE8A9BA), location: 1.0),
                    ],
                    center: UnitPoint(x: 0.5, y: 0.46),
                    startRadiusFraction: 0,
                    endRadiusFraction: 0.78
                )
                .frame(width: geo.size.width * 1.35, height: geo.size.height * 1.1)
                .position(x: geo.size.width / 2, y: geo.size.height * 0.46)

                LinearGradient(
                    stops: [
                        .init(color: Color(hex: 0xD68EA5).opacity(0), location: 0.55),
                        .init(color: Color(hex: 0xD68EA5).opacity(0.28), location: 0.82),
                        .init(color: Color(hex: 0xD08199).opacity(0.5), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                GrainOverlay()
                    .blendMode(.softLight)
                    .opacity(0.22)
            }
        }
    }
}

/// One swatch from the reference's side strip: a tiny blurred aura in a
/// soft rounded square, with a thin glyph on top.
struct AuraTile: View {
    let palette: [Color]
    let symbol: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        ZStack {
            shape.fill(palette.last ?? .white)

            RadialGradient(
                colors: palette,
                center: .center,
                startRadius: 1,
                endRadius: 26
            )
            .blur(radius: 5)

            Image(systemName: symbol)
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(.black.opacity(0.7))
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.8), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension AuraTile {
    /// The dock's color hints, core to rim: mint, rose, sky, butter, peach.
    static let hints: [[Color]] = [
        [Color(hex: 0xFFFBE8), Color(hex: 0xD4FDE0), Color(hex: 0xF5DFF9)],
        [Color(hex: 0xFFFFFF), Color(hex: 0xFFD0DD), Color(hex: 0xF3DDF6)],
        [Color(hex: 0xFFFFFF), Color(hex: 0xD3E5FF), Color(hex: 0xEADCF7)],
        [Color(hex: 0xFFFBEA), Color(hex: 0xFFEAB0), Color(hex: 0xF5DDEB)],
        [Color(hex: 0xFFFDEE), Color(hex: 0xFDE6D0), Color(hex: 0xF6D5E6)],
    ]
}
