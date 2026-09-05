import SwiftUI

/// First screen shown on launch: just the looping background video.
struct LandingView: View {
    var body: some View {
        LoopingVideoPlayer(resourceName: "background-1", resourceExtension: "mp4")
            .ignoresSafeArea()
            .overlay {
                // Soft edge vignette for depth — keeps the footage feeling rich
                // rather than flat.
                RadialGradient(
                    colors: [.clear, .black.opacity(0.28)],
                    center: .center,
                    startRadius: 120,
                    endRadius: 520
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                VStack(spacing: 18) {
                    Image("girl")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 260)
                        .shadow(color: .white.opacity(0.55), radius: 34)

                    Text("Clutch")
                        .font(.custom("PinyonScript-Regular", size: 62))
                        .foregroundStyle(.white)
                }
                .padding(.top, 90)
            }
            .background(Color.black)
    }
}

#Preview {
    LandingView()
}