import SwiftUI

/// The opening screen's moving pink footage with the "Creativity Aura"
/// glow laid over it: a cream core and blush ring (sampled from the aura
/// reference) that shade into the video's own rose and lilac and then fade
/// out, so the footage keeps moving around the edges.
struct AuraBackground: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(hex: 0xE6A3C0)

                LoopingVideoPlayer(resourceName: "background-1", resourceExtension: "mp4")

                EllipticalGradient(
                    stops: [
                        .init(color: Color(hex: 0xFFFDEE), location: 0.00),
                        .init(color: Color(hex: 0xFFF6F0), location: 0.14),
                        .init(color: Color(hex: 0xFEE4F6).opacity(0.95), location: 0.34),
                        .init(color: Color(hex: 0xF7CDE8).opacity(0.75), location: 0.52),
                        .init(color: Color(hex: 0xEFB8D8).opacity(0.35), location: 0.72),
                        .init(color: Color(hex: 0xEFB8D8).opacity(0), location: 1.00),
                    ],
                    center: .center
                )
                .frame(width: geo.size.width * 1.1, height: geo.size.height * 0.9)
                .offset(y: geo.size.height * 0.04)
                .blur(radius: 24)

                GrainOverlay()
                    .blendMode(.overlay)
                    .opacity(0.3)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
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
