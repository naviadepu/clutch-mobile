import SwiftUI

/// Third screen: asks for age with a draggable dot-scale, styled after the
/// glowing wellness-tracker card look — a dark blurred glow rides behind the
/// scale to mark the current position, and the active dot lifts with a
/// shadow while it's being dragged.
struct AgeEntryView: View {
    @State private var age: Double = 22
    @State private var isDragging = false

    private let ageRange: ClosedRange<Double> = 13...70
    private let dotCount = 11

    var body: some View {
        ZStack {
            backgroundGlow

            VStack(spacing: 32) {
                Text("How old are you?")
                    .font(.custom("PlayfairDisplay-SemiBold", size: 26))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 2)

                card
                    .frame(height: 250)
            }
            .padding(.horizontal, 28)
        }
    }

    private var backgroundGlow: some View {
        RadialGradient(
            colors: [
                Color(red: 0.62, green: 0.22, blue: 0.34),
                Color.strawberry.opacity(0.85),
                Color(red: 0.86, green: 0.70, blue: 0.78),
            ],
            center: .center,
            startRadius: 20,
            endRadius: 460
        )
        .ignoresSafeArea()
    }

    private var card: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(.white.opacity(0.14))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 22) {
                Text("Your age")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))

                GeometryReader { geo in
                    dotTrack(width: geo.size.width)
                }
                .frame(height: 60)

                HStack(alignment: .lastTextBaseline, spacing: 5) {
                    Text("\(Int(age))")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                    Text("yrs")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .foregroundStyle(.white)
            }
            .padding(26)
        }
    }

    private func dotTrack(width: CGFloat) -> some View {
        let fraction = (age - ageRange.lowerBound) / (ageRange.upperBound - ageRange.lowerBound)
        let dotSpacing = width / CGFloat(dotCount - 1)
        let selectedIndex = Int((fraction * Double(dotCount - 1)).rounded())
        let selectedX = CGFloat(selectedIndex) * dotSpacing

        let glowSize: CGFloat = isDragging ? 100 : 76

        return ZStack(alignment: .leading) {
            // The glow that trails the active dot, echoing the reference card's blob.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.black.opacity(isDragging ? 0.7 : 0.55), .black.opacity(0.15), .clear],
                        center: .center,
                        startRadius: 2,
                        endRadius: glowSize / 2
                    )
                )
                .frame(width: glowSize, height: glowSize)
                .blur(radius: isDragging ? 10 : 8)
                .offset(x: selectedX - glowSize / 2)

            ForEach(0..<dotCount, id: \.self) { index in
                let isSelected = index == selectedIndex
                let lifted = isSelected && isDragging
                let size: CGFloat = isSelected ? (isDragging ? 26 : 13) : 6

                Circle()
                    .fill(.white)
                    .frame(width: size, height: size)
                    // Dark drop shadow underneath — reads as the dot lifting off the track.
                    .shadow(color: .black.opacity(lifted ? 0.55 : 0), radius: lifted ? 14 : 0, y: lifted ? 9 : 0)
                    // Soft white halo around it — the "glow" that sells the lift.
                    .shadow(color: .white.opacity(lifted ? 0.85 : 0), radius: lifted ? 12 : 0)
                    .offset(
                        x: CGFloat(index) * dotSpacing - size / 2,
                        y: lifted ? -7 : 0
                    )
            }
        }
        .frame(width: width, height: 60, alignment: .leading)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    isDragging = true
                    let clampedX = min(max(value.location.x, 0), width)
                    let dragFraction = clampedX / width
                    let newAge = ageRange.lowerBound + dragFraction * (ageRange.upperBound - ageRange.lowerBound)
                    age = newAge.rounded()
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: selectedIndex)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isDragging)
    }
}

#Preview {
    AgeEntryView()
}
