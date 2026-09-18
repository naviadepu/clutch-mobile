import SwiftUI
import UIKit

/// Third screen: asks for age with a draggable dot-scale on a glass card.
/// The aura artwork fills the page (speed-streaked and grained); the card
/// refracts a blurred copy of that same artwork so it reads as real glass
/// rather than a milky material. Numerals use a dot-matrix face, labels a
/// light rounded sans.
struct AgeEntryView: View {
    let signature: UIImage?

    @State private var age: Double = 22
    @State private var isDragging = false
    @State private var goToGarden = false
    @State private var pageSize: CGSize = .zero

    init(signature: UIImage? = nil) {
        self.signature = signature
    }

    private let ageRange: ClosedRange<Double> = 13...70
    private let dotCount = 11
    private let cornerRadius: CGFloat = 36

    private let plum = Color(red: 0.42, green: 0.16, blue: 0.29)
    private let lavender = Color(red: 0.78, green: 0.70, blue: 0.95)

    var body: some View {
        ZStack {
            VStack(spacing: 36) {
                Text("How old are you?")
                    .font(.custom("HelveticaNeue-Medium", size: 30))
                    .tracking(-1)
                    .foregroundStyle(plum)

                card
                    .frame(height: 260)
            }
            .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            GeometryReader { geo in
                ZStack {
                    aura(size: geo.size)
                    GrainOverlay()
                        .blendMode(.overlay)
                        .opacity(0.22)
                }
                .onAppear { pageSize = geo.size }
                .onChange(of: geo.size) { _, newSize in pageSize = newSize }
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .bottomTrailing) {
            // TODO: the cycle-date and signature onboarding steps belong between
            // this screen and the Garden — out of scope for the Garden brief, so
            // this jumps straight there for now.
            Button {
                goToGarden = true
            } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background { glass(in: Circle(), blur: 14) }
            }
            .padding(24)
        }
        .navigationDestination(isPresented: $goToGarden) {
            GardenView(signature: signature)
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func aura(size: CGSize) -> some View {
        Image("aura-bg")
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
    }

    // MARK: - Glass

    /// Frosted glass: a blurred, slightly deepened copy of the page artwork
    /// aligned under the shape, a bright inner rim, and an iridescent edge.
    private func glass<S: InsettableShape>(in shape: S, blur: CGFloat) -> some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .global)
            ZStack {
                aura(size: pageSize)
                    .offset(x: -frame.minX, y: -frame.minY)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    .blur(radius: blur, opaque: true)
                    .saturation(1.15)

                // Rose tint so white type reads on the pale aura.
                shape.fill(plum.opacity(0.22))

                // Light falling on the top of the pane.
                shape.fill(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .white.opacity(0.04), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )

                // Thick glass glows at its edges.
                shape
                    .strokeBorder(.white.opacity(0.55), lineWidth: 10)
                    .blur(radius: 9)

                shape.strokeBorder(
                    AngularGradient(
                        colors: [
                            .white.opacity(0.9),
                            lavender.opacity(0.7),
                            Color(red: 0.72, green: 0.93, blue: 0.88).opacity(0.6),
                            Color(red: 1.0, green: 0.90, blue: 0.68).opacity(0.6),
                            .white.opacity(0.3),
                            .white.opacity(0.9),
                        ],
                        center: .center
                    ),
                    lineWidth: 1
                )
            }
            .clipShape(shape)
        }
        .shadow(color: plum.opacity(0.10), radius: 22, y: 10)
    }

    // MARK: - Card

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your age")
                    .font(.custom("Quicksand-Regular", size: 16))
                Spacer()
                Text("\(Int(ageRange.lowerBound)) – \(Int(ageRange.upperBound))")
                    .font(.custom("Quicksand-Light", size: 14))
                    .opacity(0.9)
            }

            Spacer(minLength: 0)

            GeometryReader { geo in
                dotTrack(width: geo.size.width)
            }
            .frame(height: 56)

            Spacer(minLength: 0)

            HStack(alignment: .lastTextBaseline) {
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text("\(Int(age))")
                        .font(.custom("DotoRounded-Medium", size: 68))
                        .contentTransition(.numericText(value: age))
                    Text("yrs")
                        .font(.custom("Quicksand-Light", size: 16))
                        .opacity(0.9)
                }
                Spacer()
                Text("born \(String(birthYear))")
                    .font(.custom("Quicksand-Light", size: 14))
                    .opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: plum.opacity(0.25), radius: 6, y: 1)
        .padding(.horizontal, 26)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .background { glass(in: shape, blur: 22) }
    }

    private var birthYear: Int {
        Calendar.current.component(.year, from: .now) - Int(age)
    }

    // MARK: - Dot track

    private func dotTrack(width: CGFloat) -> some View {
        let fraction = (age - ageRange.lowerBound) / (ageRange.upperBound - ageRange.lowerBound)
        let dotSpacing = width / CGFloat(dotCount - 1)
        let selectedIndex = Int((fraction * Double(dotCount - 1)).rounded())
        let selectedX = CGFloat(selectedIndex) * dotSpacing
        let markerSize: CGFloat = isDragging ? 38 : 32

        return ZStack(alignment: .leading) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0), .white.opacity(0.55), .white.opacity(0.55), .white.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: width, height: 0.75)

            ForEach(0..<dotCount, id: \.self) { index in
                let distance = abs(index - selectedIndex)
                let size: CGFloat = distance == 1 ? 6 : (distance == 2 ? 5 : 4)

                if distance != 0 {
                    Circle()
                        .fill(.white.opacity(distance <= 2 ? 1 : 0.8))
                        .frame(width: size, height: size)
                        .offset(x: CGFloat(index) * dotSpacing - size / 2)
                }
            }

            // Glass ring marker for the selected value.
            ZStack {
                if isDragging {
                    SparkleBurst()
                }
                Circle()
                    .fill(.white.opacity(0.18))
                Circle()
                    .strokeBorder(.white.opacity(0.9), lineWidth: 0.75)
                Circle()
                    .strokeBorder(.white.opacity(0.4), lineWidth: 0.5)
                    .padding(5)
                Circle()
                    .fill(.white)
                    .frame(width: 8, height: 8)
                    .shadow(color: .white.opacity(0.9), radius: 4)
            }
            .frame(width: markerSize, height: markerSize)
            .offset(x: selectedX - markerSize / 2)
        }
        .frame(width: width, height: 56, alignment: .leading)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    isDragging = true
                    let clampedX = min(max(value.location.x, 0), width)
                    let dragFraction = clampedX / width
                    let newAge = ageRange.lowerBound + dragFraction * (ageRange.upperBound - ageRange.lowerBound)
                    withAnimation(.snappy(duration: 0.2)) {
                        age = newAge.rounded()
                    }
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedIndex)
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isDragging)
    }
}

/// A handful of twinkling sparkles around the marker while it's being
/// dragged, each on its own staggered timer so the glitter reads as random.
private struct SparkleBurst: View {
    @State private var twinkle = false

    private struct Spark {
        let dx: CGFloat
        let dy: CGFloat
        let size: CGFloat
        let delay: Double
    }

    private let sparks: [Spark] = [
        .init(dx: -26, dy: -14, size: 6, delay: 0.00),
        .init(dx: 22, dy: -20, size: 4, delay: 0.12),
        .init(dx: 28, dy: 8, size: 5, delay: 0.24),
        .init(dx: -22, dy: 16, size: 4, delay: 0.08),
    ]

    var body: some View {
        ZStack {
            ForEach(sparks.indices, id: \.self) { i in
                let s = sparks[i]
                Image(systemName: "sparkle")
                    .font(.system(size: s.size, weight: .light))
                    .foregroundStyle(.white)
                    .offset(x: s.dx, y: s.dy)
                    .opacity(twinkle ? 0.9 : 0.1)
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
