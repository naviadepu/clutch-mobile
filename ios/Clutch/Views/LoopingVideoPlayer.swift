import SwiftUI
import AVFoundation

/// A muted, looping, aspect-fill video used as a full-bleed background.
struct LoopingVideoPlayer: UIViewRepresentable {
    let resourceName: String
    let resourceExtension: String

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: resourceExtension) else {
            assertionFailure("Missing bundled video \(resourceName).\(resourceExtension)")
            return view
        }

        let item = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer(playerItem: item)
        queuePlayer.isMuted = true
        queuePlayer.actionAtItemEnd = .none

        context.coordinator.looper = AVPlayerLooper(player: queuePlayer, templateItem: item)

        view.playerLayer.player = queuePlayer
        view.playerLayer.videoGravity = .resizeAspectFill
        queuePlayer.play()

        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var looper: AVPlayerLooper?
    }

    /// UIView backed by an AVPlayerLayer so the video resizes with the view.
    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
