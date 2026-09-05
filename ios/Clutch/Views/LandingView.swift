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
            .background(Color.black)
    }
}

#Preview {
    LandingView()
}
