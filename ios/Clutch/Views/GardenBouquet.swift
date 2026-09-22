import SwiftUI

/// The day's flowers gathered into a bouquet: photographed stems cut out
/// with clean, opaque edges, fanned out like a real bunch — the tallest
/// raised at the back and centre, shorter ones angling out at the sides —
/// each washed in a soft blush-to-lavender tint, with a few sprigs of
/// greenery, all held in a photographed newspaper wrap. When she's signed
/// her name, it's on a paper tag tucked into the front. Each card answered
/// adds a flower.
struct Bouquet: View {
    let flowers: [PlantedFlower]
    let reduceMotion: Bool
    /// Off for snapshots and thumbnails, which show the bouquet settled.
    var animatesIn = true
    /// Her onboarding scribble, for the tag. No tag without one.
    var signature: UIImage? = nil

    static let size = CGSize(width: 380, height: 600)
    /// Where every stem meets, hidden inside the wrap.
    fileprivate static let knot = CGPoint(x: 194, y: 352)

    /// Where each flower goes, in the order they're added. Depth 0 is the
    /// back row: raised on longer stems at the centre. Depth 2 is the
    /// front: full size, angling well out at the sides.
    private static let slots: [Slot] = [
        Slot(angle: -3, scale: 0.66, lift: 112, depth: 0),
        Slot(angle: 33, scale: 0.9, lift: 0, depth: 2),
        Slot(angle: -19, scale: 0.62, lift: 84, depth: 0),
        Slot(angle: -35, scale: 0.88, lift: 4, depth: 2),
        Slot(angle: 15, scale: 0.63, lift: 92, depth: 0),
        Slot(angle: 5, scale: 0.74, lift: 40, depth: 1),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !flowers.isEmpty {
                // A faint blush bloom behind the bunch, and a soft shadow on
                // the ground beneath it.
                RadialGradient(
                    colors: [Color(hex: 0xF6D6DE).opacity(0.7), Color(hex: 0xF6D6DE).opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 200
                )
                .frame(width: 400, height: 400)
                .position(x: Self.knot.x, y: 190)

                Ellipse()
                    .fill(.black.opacity(0.16))
                    .frame(width: 96, height: 16)
                    .blur(radius: 9)
                    .position(x: Wrap.frame.minX + 290 * Wrap.scale, y: Wrap.frame.maxY - 2)

                Greenery(reduceMotion: reduceMotion, animatesIn: animatesIn)
                    .zIndex(-1)
            }

            ForEach(Array(flowers.enumerated()), id: \.element.id) { index, flower in
                let slot = Self.slots[index % Self.slots.count]
                PhotoFlower(
                    flower: flower,
                    slot: slot,
                    reduceMotion: reduceMotion,
                    animatesIn: animatesIn
                )
                .zIndex(Double(slot.depth))
            }

            if !flowers.isEmpty {
                Group {
                    RimShadow()
                    if let signature {
                        NameTag(signature: signature)
                    }
                    Wrap()
                }
                .zIndex(10)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityHidden(true)
    }
}

fileprivate struct Slot {
    let angle: Double
    let scale: CGFloat
    /// How far up its own axis the flower sits, on a longer stem.
    let lift: CGFloat
    let depth: Int
}

/// Per-photo layout: where the stem leaves the bottom edge (as a fraction
/// of width) and the image's aspect ratio.
private enum FlowerArt {
    static let stemBaseX: [Int: CGFloat] = [1: 0.462, 2: 0.995, 3: 0.351, 4: 0.441, 5: 0.72, 6: 0.328]
    static let aspect: [Int: CGFloat] = [1: 441.0 / 760, 2: 385.0 / 578, 3: 427.0 / 640, 4: 604.0 / 760, 5: 506.0 / 760, 6: 439.0 / 670]
    static let fullHeight: CGFloat = 322
    static let stemColor = Color(hex: 0x8A9A7E)
}

/// One photographed stem in its slot. A raised flower gets a plain stem
/// running down from the photo's stem to the knot. It fades in as it's
/// added, then sways very slowly.
private struct PhotoFlower: View {
    let flower: PlantedFlower
    let slot: Slot
    let reduceMotion: Bool

    @State private var settled: Bool
    @State private var swayed = false

    init(flower: PlantedFlower, slot: Slot, reduceMotion: Bool, animatesIn: Bool) {
        self.flower = flower
        self.slot = slot
        self.reduceMotion = reduceMotion
        _settled = State(initialValue: !animatesIn)
    }

    var body: some View {
        let knot = Bouquet.knot
        let height = FlowerArt.fullHeight * slot.scale + flower.heightOffset
        let width = height * (FlowerArt.aspect[flower.art] ?? 0.66)
        let rawBase = FlowerArt.stemBaseX[flower.art] ?? 0.5
        let baseX = flower.flipped ? 1 - rawBase : rawBase
        let lift = slot.lift
        let degrees = slot.angle + flower.tilt + (swayed ? 0.7 : -0.7)

        // Everything is laid out upright on the knot, then turned about it,
        // so the extra stem and the photo lean together.
        ZStack(alignment: .topLeading) {
            if lift > 0 {
                Capsule()
                    .fill(FlowerArt.stemColor)
                    .frame(width: 2.6 * max(slot.scale, 0.7), height: lift + 6)
                    .position(x: knot.x, y: knot.y - lift / 2)
            }

            DreamyWash(flower: flower, photo: photo)
                .shadow(color: Color(hex: 0xA85A74).opacity(0.18), radius: 8, y: 4)
                .frame(width: width, height: height)
                .position(x: knot.x - (baseX - 0.5) * width, y: knot.y - lift - height / 2)
        }
        .frame(width: Bouquet.size.width, height: Bouquet.size.height)
        .rotationEffect(.degrees(degrees), anchor: UnitPoint(x: knot.x / Bouquet.size.width, y: knot.y / Bouquet.size.height))
        .opacity(settled ? 1 : 0)
        .onAppear {
            if !settled {
                withAnimation(.easeOut(duration: 1.0)) { settled = true }
            }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: flower.swayPeriod).repeatForever(autoreverses: true)) {
                swayed = true
            }
        }
    }

    private var photo: some View {
        Image("flower-\(flower.art)")
            .resizable()
            .scaleEffect(x: flower.flipped ? -1 : 1)
    }
}

/// A soft colour wash over a flower's petals — blush drifting into lavender
/// or pale sky — laid in soft light so the photo's veins and texture show
/// through, with a little light glowing through the petal tips. It fades
/// out down the stem, which stays green. Colour only: no blur, no fade.
private struct DreamyWash<Photo: View>: View {
    let flower: PlantedFlower
    let photo: Photo

    private static var blush: Color { Color(hex: 0xF7B3C6) }
    private static var lavender: Color { Color(hex: 0xC4B3EE) }
    private static var sky: Color { Color(hex: 0xAFCFF2) }

    var body: some View {
        // Each photo gets its own slant, mirrored with the photo, so no two
        // washes run the same way.
        let angle = (Double(flower.art) * 47 + (flower.flipped ? 180 : 0)).truncatingRemainder(dividingBy: 360) * .pi / 180
        let dx = cos(angle) * 0.5, dy = sin(angle) * 0.5 * 0.6
        let start = UnitPoint(x: 0.5 - dx, y: 0.3 - dy)
        let end = UnitPoint(x: 0.5 + dx, y: 0.3 + dy)
        let cool = flower.art.isMultiple(of: 2) ? Self.lavender : Self.sky
        let wash = LinearGradient(colors: [Self.blush, Self.blush, cool], startPoint: start, endPoint: end)

        // Each layer blends straight onto the photo (a mask or group on the
        // layer itself would cut it off from the petals beneath); the final
        // mask trims everything to the photo's own outline.
        photo
            .overlay { wash.mask(Self.petals).blendMode(.softLight) }
            // Soft light barely moves near-white petals; a whisper of
            // multiply lets pale blooms pick up the tint too.
            .overlay { wash.mask(Self.petals).opacity(0.22).blendMode(.multiply) }
            .overlay { Self.tipGlow.blendMode(.screen) }
            .mask(photo)
            .compositingGroup()
    }

    /// Full strength over the blooms, gone by the lower stem.
    private static var petals: LinearGradient {
        LinearGradient(
            stops: [.init(color: .white, location: 0), .init(color: .white, location: 0.5), .init(color: .clear, location: 0.8)],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// Light shining through the tips.
    private static var tipGlow: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(hex: 0xFFF4F7).opacity(0.5), location: 0),
                .init(color: Color(hex: 0xFFF4F7).opacity(0.15), location: 0.2),
                .init(color: .clear, location: 0.4),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }
}

// MARK: - Wrap

/// The photographed newspaper wrap, used as is: cut out of its photo, with
/// the flowers it held removed and turned a few degrees so the opening sits
/// nearly level. Only its front shows in the photo, so the stems go in
/// behind its top edge.
private struct Wrap: View {
    /// The photo is 435×825 px; its opening runs along the top edge.
    static let scale: CGFloat = 0.44
    static let frame = CGRect(x: 97, y: 232, width: 435 * scale, height: 825 * scale)
    /// The top edge of the paper, in the bouquet's space.
    static let rimY = frame.minY + 8 * scale

    var body: some View {
        Image("wrap-newspaper")
            .resizable()
            .frame(width: Self.frame.width, height: Self.frame.height)
            .position(x: Self.frame.midX, y: Self.frame.midY)
    }
}

/// The paper's top edge shading the stems and lower petals just as they go
/// in, so flowers and wrap read as one photo.
private struct RimShadow: View {
    var body: some View {
        Ellipse()
            .fill(Color(hex: 0x5C3A44).opacity(0.3))
            .frame(width: Wrap.frame.width * 0.86, height: 30)
            .blur(radius: 10)
            .position(x: Wrap.frame.midX + 4, y: Wrap.rimY + 4)
    }
}

/// A small cream tag tucked into the front of the wrap, its lower half out
/// of sight behind the paper, with her name in dark ink.
private struct NameTag: View {
    let signature: UIImage

    private static let ink = Color(hex: 0x2B2226)
    private static let size = CGSize(width: 78, height: 58)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        ZStack(alignment: .top) {
            shape.fill(
                LinearGradient(
                    colors: [Color(hex: 0xFCF7EC), Color(hex: 0xF3EBDB)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            GrainOverlay()
                .blendMode(.multiply)
                .opacity(0.08)
                .clipShape(shape)

            // Her own strokes, whatever colour she drew in, set in ink.
            Self.ink
                .mask(
                    Image(uiImage: signature)
                        .resizable()
                        .scaledToFit()
                )
                .frame(width: Self.size.width - 14, height: 26)
                .padding(.top, 8)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .shadow(color: Color(hex: 0x5C3A44).opacity(0.22), radius: 3, y: 2)
        .rotationEffect(.degrees(7))
        // Right of centre, so it doesn't hide the middle bloom; the bottom
        // ~15pt sits behind the paper.
        .position(x: Wrap.frame.midX + 36, y: Wrap.rimY - Self.size.height / 2 + 16)
    }
}

// MARK: - Greenery

/// A few thin sprigs of greenery reaching out at the edges and over the
/// top, behind the flowers, for a just-picked look.
private struct Greenery: View {
    let reduceMotion: Bool
    let animatesIn: Bool

    @State private var shown: Bool

    init(reduceMotion: Bool, animatesIn: Bool) {
        self.reduceMotion = reduceMotion
        self.animatesIn = animatesIn
        _shown = State(initialValue: !animatesIn)
    }

    /// Angle, length and leaf count for each sprig.
    private static let sprigs: [(angle: Double, length: CGFloat, leaves: Int)] = [
        (-54, 206, 9), (-44, 250, 11), (-8, 286, 12), (11, 272, 11), (47, 236, 10), (57, 198, 8),
    ]

    var body: some View {
        ZStack {
            ForEach(Array(Self.sprigs.enumerated()), id: \.offset) { index, sprig in
                Sprig(length: sprig.length, leaves: sprig.leaves, flip: index.isMultiple(of: 2))
                    .rotationEffect(
                        .degrees(sprig.angle),
                        anchor: UnitPoint(x: Bouquet.knot.x / Bouquet.size.width, y: Bouquet.knot.y / Bouquet.size.height)
                    )
            }
        }
        .frame(width: Bouquet.size.width, height: Bouquet.size.height)
        .opacity(shown ? 1 : 0)
        .onAppear {
            if !shown { withAnimation(.easeOut(duration: 1.0)) { shown = true } }
        }
    }
}

/// One sprig, laid out upright from the knot: a hairline stem with small
/// paired leaves that shrink toward the tip.
private struct Sprig: View {
    let length: CGFloat
    let leaves: Int
    let flip: Bool

    private static let stem = Color(hex: 0x7F8E6C)

    var body: some View {
        let knot = Bouquet.knot
        let bend: CGFloat = flip ? 10 : -10
        Canvas { context, _ in
            let top = CGPoint(x: knot.x + bend * 0.6, y: knot.y - length)
            let control = CGPoint(x: knot.x + bend, y: knot.y - length * 0.55)
            var stem = Path()
            stem.move(to: knot)
            stem.addQuadCurve(to: top, control: control)
            context.stroke(stem, with: .color(Self.stem), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))

            // Leaves only on the part above the wrap.
            for i in 0..<leaves {
                let t = 0.45 + 0.55 * CGFloat(i) / CGFloat(max(leaves - 1, 1))
                let u = 1 - t
                let point = CGPoint(
                    x: u * u * knot.x + 2 * u * t * control.x + t * t * top.x,
                    y: u * u * knot.y + 2 * u * t * control.y + t * t * top.y
                )
                let size = 11 - 5 * (t - 0.45) / 0.55
                for side in [-1.0, 1.0] {
                    let angle = side * (52 - 14 * Double(t)) + (i.isMultiple(of: 2) ? 4 : -4)
                    var leafContext = context
                    leafContext.translateBy(x: point.x, y: point.y)
                    leafContext.rotate(by: .degrees(angle))
                    let leaf = Path(ellipseIn: CGRect(x: -size * 0.2, y: -size, width: size * 0.4, height: size))
                    leafContext.fill(leaf, with: .linearGradient(
                        Gradient(colors: [Color(hex: 0xA9B894), Color(hex: 0x7C8D69)]),
                        startPoint: CGPoint(x: 0, y: -size), endPoint: .zero
                    ))
                }
            }
            // A single leaf at the tip.
            var tipContext = context
            tipContext.translateBy(x: top.x, y: top.y + 2)
            tipContext.fill(
                Path(ellipseIn: CGRect(x: -2, y: -9, width: 4, height: 9)),
                with: .color(Color(hex: 0x9CAC87))
            )
        }
        .frame(width: Bouquet.size.width, height: Bouquet.size.height)
    }
}

/// Renders a bouquet to a square image for sharing.
@MainActor
enum BouquetSnapshot {
    static func image(of flowers: [PlantedFlower], signature: UIImage? = nil) -> UIImage? {
        let content = ZStack {
            BlushGradient()
            Bouquet(flowers: flowers, reduceMotion: true, animatesIn: false, signature: signature)
                .scaleEffect(0.53)
                .offset(y: -2)
        }
        .frame(width: 300, height: 300)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        return renderer.uiImage
    }
}
