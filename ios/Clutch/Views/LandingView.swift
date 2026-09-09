import SwiftUI

/// First screen shown on launch: the looping background video with the girl
/// image and an animated "Clutch" wordmark, centered.
struct LandingView: View {
    @State private var girlShown = false
    @State private var floating = false
    @State private var readyToContinue = false
    @State private var goToNameEntry = false

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
            .overlay {
                VStack(spacing: 18) {
                    Image("girl")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 260)
                        .shadow(color: .white.opacity(0.55), radius: 34)
                        .opacity(girlShown ? 1 : 0)
                        .scaleEffect(girlShown ? 1 : 0.94)
                        .offset(y: floating ? -4 : 4)
                        .onAppear {
                            withAnimation(.easeOut(duration: 1.2)) {
                                girlShown = true
                            }
                            withAnimation(
                                .easeInOut(duration: 4).repeatForever(autoreverses: true)
                            ) {
                                floating = true
                            }
                        }

                    AnimatedWordmark(text: "Clutch") {
                        withAnimation(.easeIn(duration: 0.6)) { readyToContinue = true }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                Text("tap to continue")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.bottom, 40)
                    .opacity(readyToContinue ? 1 : 0)
            }
            .background(Color("LaunchBackground"))
            .contentShape(Rectangle())
            .onTapGesture {
                if readyToContinue { goToNameEntry = true }
            }
            .navigationDestination(isPresented: $goToNameEntry) {
                NameEntryView()
                    .toolbar(.hidden, for: .navigationBar)
            }
    }
}

/// Renders the wordmark once (so the script font's connecting strokes stay
/// intact) and reveals it left-to-right, one letter at a time, via a mask.
private struct AnimatedWordmark: View {
    let text: String
    var onComplete: () -> Void = {}

    @State private var revealed = 0

    var body: some View {
        Text(text)
            .font(.custom("PinyonScript-Regular", size: 64))
            .foregroundStyle(.white)
            .mask(alignment: .leading) {
                GeometryReader { geo in
                    Rectangle()
                        .frame(width: geo.size.width * CGFloat(revealed) / CGFloat(max(text.count, 1)))
                }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(800))
                for letter in 1...text.count {
                    withAnimation(.easeOut(duration: 0.5)) {
                        revealed = letter
                    }
                    try? await Task.sleep(for: .milliseconds(340))
                }
                onComplete()
            }
    }
}

#Preview {
    LandingView()
}
