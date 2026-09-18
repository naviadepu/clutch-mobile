import SwiftUI

/// Fine static film grain. Seeded so it doesn't shimmer between renders.
struct GrainOverlay: View {
    var body: some View {
        Canvas { context, size in
            var rng = SeededRandom(seed: 42)
            let count = Int(size.width * size.height / 60)
            for _ in 0..<count {
                let x = CGFloat(rng.next()) * size.width
                let y = CGFloat(rng.next()) * size.height
                let white = rng.next() > 0.5
                context.fill(
                    Path(CGRect(x: x, y: y, width: 1, height: 1)),
                    with: .color(white ? .white : .black)
                )
            }
        }
        .allowsHitTesting(false)
    }
}

private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}
