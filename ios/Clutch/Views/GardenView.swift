import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// `UIImage` has no built-in `Transferable` conformance — `ShareLink` needs
/// this thin wrapper to export the snapshot as JPEG data.
private struct ShareableGardenImage: Transferable {
    let image: UIImage

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { shareable in
            shareable.image.jpegData(compressionQuality: 0.92) ?? Data()
        }
    }
}

/// The Garden screen: one symptom at a time as a swipeable card — right to
/// log, left to skip. Either direction plants a flower along the bottom of
/// the screen (showing up counts, even when the answer is "skip"); finishing
/// the deck with at least one flower brings in a butterfly that opens a
/// share sheet when tapped. An empty garden — the deck finishing with
/// nothing planted — still gets a quiet, non-judgmental message rather than
/// a faked reward, though in practice that's now unreachable while the
/// catalog is non-empty, since every card plants something.
///
/// Blooms and the butterfly are real photo cutouts (feathered PNGs derived
/// from the user's own reference photos), not the reference prototype's
/// original bitmaps — those arrived as inline base64 too long to
/// transcribe by hand without risking silent corruption.
struct GardenView: View {
    let signature: UIImage?

    @StateObject private var model = GardenModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var promptText = "Log how you feel — your garden fills as you go."
    @State private var showButterfly = false
    @State private var showShare = false
    @State private var didStart = false
    @State private var gardenSnapshot: UIImage?

    init(signature: UIImage? = nil) {
        self.signature = signature
    }

    /// The two-tone text palette used throughout: a near-black warm brown
    /// for anything primary/active, a muted taupe for secondary labels.
    private static let ink = Color(red: 0.29, green: 0.23, blue: 0.20)
    private static let mutedInk = Color(red: 0.61, green: 0.54, blue: 0.50)

    @State private var selectedDockItem: DockItem = .garden

    var body: some View {
        ZStack {
            AuraBackground()

            // ~1 inch of clearance below the stems, off the true screen edge,
            // plus room for the tab bar sitting on top of it.
            flowerBed
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 168)

            Group {
                if didStart {
                    VStack(spacing: 22) {
                        Text(promptText)
                            .font(.system(size: 17, design: .serif).italic())
                            .foregroundStyle(Self.ink)
                            .multilineTextAlignment(.center)
                            .animation(.easeInOut(duration: 0.3), value: promptText)
                            .padding(.horizontal, 40)

                        if !model.isFinished {
                            SwipeDeck(model: model, onCommit: handleCommit, onFinished: handleFinished)
                                .padding(.horizontal, 28)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 190)
                    .transition(.opacity)
                } else {
                    startState
                        .transition(.opacity)
                }
            }

            topBar
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if showShare {
                // A Polaroid card over the same screen rather than a system
                // sheet — sharing never leaves the garden.
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.25)) { showShare = false } }
                    .overlay {
                        PolaroidCard(image: gardenSnapshot, flowerCount: model.totalLoggedCount) {
                            withAnimation(.easeInOut(duration: 0.25)) { showShare = false }
                        }
                    }
                    .transition(.opacity)
            }

            dock
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .onAppear {
            // Resuming after today's deck was already finished (app relaunched,
            // came back from another tab) — the commit flow that normally
            // drives this UI never runs, so re-derive it from the model.
            // Also skip straight past the "Start today" gate in that case;
            // there's nothing left to start.
            guard model.isFinished else { return }
            didStart = true
            handleFinished()
        }
    }

    /// The onboarding scribble framed in a dashed glass box on the left,
    /// like the reference's side-strip frame; the wordmark on the right.
    private var topBar: some View {
        HStack(alignment: .center) {
            signatureBox
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("Clutch")
                    .font(.custom("PinyonScript-Regular", size: 44))
                    .foregroundStyle(Self.ink)
                Text("your cycle, in bloom")
                    .font(.system(size: 14, design: .serif).italic())
                    .foregroundStyle(Self.ink.opacity(0.7))
            }
            .padding(.trailing, 6)
        }
        .padding(.horizontal, 20)
        .padding(.top, 48)
    }

    private var signatureBox: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        return VStack(alignment: .leading, spacing: 6) {
            Group {
                if let signature {
                    Image(uiImage: signature)
                        .resizable()
                        .scaledToFit()
                } else {
                    Text("your name")
                        .font(.custom("PinyonScript-Regular", size: 34))
                        .foregroundStyle(Self.mutedInk)
                        .minimumScaleFactor(0.5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            // No real cycle-start date is captured yet (see
            // `GardenModel.phase`), so the day is a placeholder.
            Text("DAY 1")
                .font(.custom("HelveticaNeue", size: 9))
                .tracking(1.4)
                .foregroundStyle(.black.opacity(0.5))
        }
        .padding(12)
        .frame(width: 168, height: 104)
        .background(.ultraThinMaterial, in: shape)
        .background(.white.opacity(0.25), in: shape)
        .overlay(
            shape.strokeBorder(
                .black.opacity(0.35),
                style: StrokeStyle(lineWidth: 0.6, dash: [2, 2])
            )
        )
    }

    // MARK: - Dock

    /// A macOS-style dock: a frosted glass shelf of aura tiles (the
    /// reference's side-strip swatches), a hairline separator before
    /// "share", a dot under the active item, and a magnify-and-lift on tap.
    private var dock: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        return HStack(alignment: .bottom, spacing: 12) {
            ForEach(DockItem.primary) { item in
                dockButton(item)
            }

            Rectangle()
                .fill(.black.opacity(0.18))
                .frame(width: 0.6, height: 44)
                .padding(.bottom, 12)

            dockButton(.share)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.ultraThinMaterial, in: shape)
        .background(.white.opacity(0.3), in: shape)
        .overlay(
            shape.strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.95), .white.opacity(0.35)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.8
            )
        )
        .shadow(color: Color(hex: 0xB0587F).opacity(0.18), radius: 18, y: 8)
        .padding(.bottom, 26)
    }

    private func dockButton(_ item: DockItem) -> some View {
        let isSelected = selectedDockItem == item

        return Button {
            if item == .share {
                if model.hasBloomed { shareGarden() }
            } else {
                selectedDockItem = item
            }
        } label: {
            VStack(spacing: 5) {
                AuraTile(palette: item.palette, symbol: item.symbol)
                    .frame(width: 48, height: 48)

                Circle()
                    .fill(.black.opacity(isSelected ? 0.55 : 0))
                    .frame(width: 4, height: 4)
            }
        }
        .buttonStyle(DockButtonStyle())
        .accessibilityLabel(item.title)
    }

    /// The idle screen shown before today's deck begins: a quiet prompt
    /// over the glass orb that starts the day, sitting at the aura's core.
    private var startState: some View {
        StartOrb(text: "log how you feel  \u{2726}  your garden fills  \u{2726}  tap to begin  \u{2726}  ") {
            withAnimation(.easeInOut(duration: 0.4)) { didStart = true }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: 20)
    }

    private func handleCommit(keep: Bool, symptom: Symptom) {
        promptText = keep ? "\u{201C}\(symptom.label)\u{201D} bloomed." : "skipped."
    }

    private func handleFinished() {
        promptText = model.hasBloomed ? "Your garden today." : "A quiet day. Nothing planted."
        guard model.hasBloomed else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            showButterfly = true
        }
    }

    /// Renders the bouquet (no butterfly) to a fixed-size image for the
    /// Polaroid card, then opens it.
    private func shareGarden() {
        let content = ZStack {
            LinearGradient(
                colors: [Color(red: 0.98, green: 0.85, blue: 0.88), Color(red: 0.96, green: 0.90, blue: 0.87)],
                startPoint: .top,
                endPoint: .bottom
            )
            bouquetCluster
                .scaleEffect(0.82)
                .offset(y: 16)
        }
        .frame(width: 300, height: 300)

        let renderer = ImageRenderer(content: content)
        renderer.scale = UIScreen.main.scale
        gardenSnapshot = renderer.uiImage

        withAnimation(.easeInOut(duration: 0.3)) { showShare = true }
    }

    /// Tall enough for the tallest possible stem (160) + bloom head (~95,
    /// roughly as tall as it is wide) + the butterfly's own clearance above
    /// it. Flowers sit flush at the bottom of this frame — the "inch or so"
    /// of clearance above the true screen edge is applied once, outside,
    /// where `flowerBed` is used.
    private static let bedHeight: CGFloat = 320

    /// The bloom head crops are roughly as tall as they are wide, so this
    /// approximates a flower's full visual height (stem + head) without
    /// needing to measure the actual image.
    private func visualHeight(_ flower: PlantedFlower) -> CGFloat {
        flower.stemHeight + flower.bloomWidth
    }

    /// The flowers only — fanned out like a bouquet around a shared centre,
    /// closer together as more get planted so the cluster stays compact
    /// instead of spreading edge to edge. Reused as-is for the share
    /// snapshot, so what you share matches what's on screen.
    private var bouquetCluster: some View {
        ZStack(alignment: .bottom) {
            ForEach(Array(model.flowers.enumerated()), id: \.element.id) { index, flower in
                let n = model.flowers.count
                let mid = Double(n - 1) / 2
                let fan = fanStep(for: n)
                let step = bouquetSpacing(for: n)

                FlowerView(flower: flower, reduceMotion: reduceMotion)
                    .rotationEffect(.degrees((Double(index) - mid) * fan), anchor: .bottom)
                    .offset(x: (Double(index) - mid) * step + flower.jitter)
                    .zIndex(Double(index))
            }
        }
    }

    private func fanStep(for count: Int) -> Double {
        count > 1 ? 7 : 0
    }

    /// Fixed rather than shrinking with count — a capped, sparse bouquet
    /// (max 6) stays legible at a constant spacing instead of packing
    /// tighter as it fills, so the background always shows through.
    private func bouquetSpacing(for count: Int) -> Double {
        count > 1 ? 70 : 0
    }

    /// Landing spots for the butterfly's roam, in the same centre-relative
    /// coordinate space the bouquet places flowers in — a handful of
    /// flowers spread across the bouquet, not all of them.
    private var butterflyLandingSpots: [CGPoint] {
        let flowers = model.flowers
        guard !flowers.isEmpty else { return [] }
        let n = flowers.count
        let mid = Double(n - 1) / 2
        let step = bouquetSpacing(for: n)
        let visitCount = min(4, n)
        let indices: [Int] = visitCount == 1
            ? [n - 1]
            : (0..<visitCount).map { i in Int((Double(i) * Double(n - 1) / Double(visitCount - 1)).rounded()) }

        return indices.map { i in
            CGPoint(x: (Double(i) - mid) * step + flowers[i].jitter, y: -(visualHeight(flowers[i]) * 0.82))
        }
    }

    private var flowerBed: some View {
        bouquetCluster
            .frame(maxWidth: .infinity)
            .frame(height: Self.bedHeight, alignment: .bottom)
            .overlay(alignment: .bottom) {
                if showButterfly {
                    ButterflyView(landingSpots: butterflyLandingSpots, reduceMotion: reduceMotion) {
                        shareGarden()
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(gardenSummaryLabel)
    }

    private var gardenSummaryLabel: String {
        let count = model.totalLoggedCount
        return count == 0 ? "Your garden: empty" : "Your garden: \(count) flower\(count == 1 ? "" : "s")"
    }
}

// MARK: - Swipe deck

/// The stacked card deck: one live card up front, two more peeking behind
/// it for depth, plus the ✕ / ♥ tap targets that mirror the swipe gesture.
private struct SwipeDeck: View {
    @ObservedObject var model: GardenModel
    let onCommit: (_ keep: Bool, _ symptom: Symptom) -> Void
    let onFinished: () -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var cardOpacity: Double = 1

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                ForEach(Array(model.upcoming(3).enumerated()).reversed(), id: \.element.id) { pair in
                    card(symptom: pair.element, depth: pair.offset)
                }
            }
            .frame(height: 190)

            if let symptom = model.currentSymptom {
                HStack(spacing: 36) {
                    tapButton(systemName: "xmark", tint: Color(red: 0.61, green: 0.54, blue: 0.50)) {
                        commit(false, symptom: symptom)
                    }
                    .accessibilityLabel("Skip \(symptom.label)")

                    tapButton(systemName: "heart.fill", tint: .white, background: Color.matcha) {
                        commit(true, symptom: symptom)
                    }
                    .accessibilityLabel("Log \(symptom.label)")
                }
            }
        }
    }

    private func card(symptom: Symptom, depth: Int) -> some View {
        let isTop = depth == 0

        return ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.white)
                .shadow(color: .black.opacity(0.14), radius: 20, y: 12)

            VStack(spacing: 10) {
                Text(symptom.label.capitalized)
                    .font(.custom("PlayfairDisplay-SemiBold", size: 28))
                    .foregroundStyle(Color(red: 0.29, green: 0.23, blue: 0.20))
                Text("swipe right to log, left to skip")
                    .font(.system(size: 14, design: .serif).italic())
                    .foregroundStyle(Color(red: 0.61, green: 0.54, blue: 0.50))
            }

            if isTop {
                stamp("LOG", tint: Color.matcha, alignment: .topTrailing, opacity: logStampOpacity)
                stamp("SKIP", tint: Color(red: 0.61, green: 0.54, blue: 0.50), alignment: .topLeading, opacity: skipStampOpacity)
            }
        }
        .frame(height: 176)
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .scaleEffect(isTop ? 1 : 1 - CGFloat(depth) * 0.04)
        .offset(y: isTop ? 0 : CGFloat(depth) * 10)
        .offset(isTop ? dragOffset : .zero)
        .rotationEffect(.degrees(isTop ? dragOffset.width / 18 : 0))
        .opacity(isTop ? cardOpacity : 1)
        .zIndex(isTop ? 10 : Double(9 - depth))
        .gesture(isTop ? dragGesture(for: symptom) : nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isTop ? symptom.label : "")
        .accessibilityAddTraits(isTop ? .isButton : [])
        .accessibilityActions {
            if isTop {
                Button("Log \(symptom.label)") { commit(true, symptom: symptom) }
                Button("Skip \(symptom.label)") { commit(false, symptom: symptom) }
            }
        }
    }

    private func stamp(_ text: String, tint: Color, alignment: Alignment, opacity: Double) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .bold))
            .tracking(2.5)
            .foregroundStyle(tint)
            .padding(.horizontal, 13)
            .padding(.vertical, 6)
            .overlay(Capsule().strokeBorder(tint, lineWidth: 1.5))
            .opacity(opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .padding(16)
            .allowsHitTesting(false)
    }

    private var logStampOpacity: Double { min(1, max(0, dragOffset.width - 20) / 70) }
    private var skipStampOpacity: Double { min(1, max(0, -dragOffset.width - 20) / 70) }

    private func dragGesture(for symptom: Symptom) -> some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = CGSize(width: value.translation.width, height: value.translation.height * 0.35)
            }
            .onEnded { value in
                if value.translation.width > 88 {
                    commit(true, symptom: symptom)
                } else if value.translation.width < -88 {
                    commit(false, symptom: symptom)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { dragOffset = .zero }
                }
            }
    }

    private func tapButton(
        systemName: String,
        tint: Color,
        background: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 54, height: 54)
                .background(background, in: Circle())
                .overlay(Circle().strokeBorder(.black.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func commit(_ keep: Bool, symptom: Symptom) {
        let flyDistance: CGFloat = keep ? 520 : -520
        withAnimation(.easeIn(duration: 0.4)) {
            dragOffset = CGSize(width: flyDistance, height: 40)
            cardOpacity = 0
        }
        onCommit(keep, symptom)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if keep { model.logCurrent() } else { model.skipCurrent() }
            dragOffset = .zero
            cardOpacity = 1
            if model.isFinished { onFinished() }
        }
    }
}

// MARK: - Flowers

/// One planted flower: a photographed bloom head on top of a separately
/// drawn stem and leaf, growing in once and swaying forever after on its
/// own randomised timer. The stem is deliberately understated — soft,
/// translucent, faintly curved — so it recedes behind the bloom rather
/// than competing with it.
private struct FlowerView: View {
    let flower: PlantedFlower
    let reduceMotion: Bool

    @State private var grown = false
    @State private var swayHigh = false

    private static let bloomNames = ["bloom-1", "bloom-2", "bloom-3", "bloom-4", "bloom-5"]
    private var bloomName: String { Self.bloomNames[flower.paletteIndex % Self.bloomNames.count] }

    /// Muted, desaturated olive — a clean saturated green would fight the
    /// bloom for attention instead of receding behind it.
    private static let stemColor = Color(red: 0.43, green: 0.46, blue: 0.33)

    private var leafOnRight: Bool { flower.stemCurveOffset < 0 }

    var body: some View {
        VStack(spacing: -6) {
            Image(bloomName)
                .resizable()
                .scaledToFit()
                .frame(width: flower.bloomWidth)
                .shadow(color: .black.opacity(0.14), radius: 5, y: 3)

            StemShape(curveOffset: flower.stemCurveOffset)
                .stroke(Self.stemColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 24, height: flower.stemHeight)
                .opacity(0.55)
                .blur(radius: 1.5)
                .overlay {
                    LeafShape()
                        .fill(Self.stemColor)
                        .frame(width: flower.stemHeight * 0.3, height: flower.stemHeight * 0.14)
                        .rotationEffect(.degrees(leafOnRight ? 35 : -35))
                        .offset(
                            x: leafOnRight ? flower.stemHeight * 0.14 : -flower.stemHeight * 0.14,
                            y: flower.stemHeight * 0.12
                        )
                        .opacity(0.6)
                        .blur(radius: 2.5)
                }
        }
        .rotationEffect(.degrees(flower.rotation), anchor: .bottom)
        .rotationEffect(.degrees(swayHigh ? 1.8 : -1.6), anchor: .bottom)
        .scaleEffect(grown ? 1 : 0.6, anchor: .bottom)
        .opacity(grown ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { grown = true }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: flower.swayPeriod).repeatForever(autoreverses: true)) {
                swayHigh = true
            }
        }
        .accessibilityHidden(true)
    }
}

/// A softly curved stem: a single quadratic path from base to tip, its
/// control point pulled off-centre so it bows rather than running dead
/// straight.
private struct StemShape: Shape {
    let curveOffset: CGFloat

    func path(in rect: CGRect) -> Path {
        let base = CGPoint(x: rect.midX, y: rect.maxY)
        let tip = CGPoint(x: rect.midX, y: rect.minY)
        let control = CGPoint(x: rect.midX + curveOffset, y: rect.midY)

        var path = Path()
        path.move(to: base)
        path.addQuadCurve(to: tip, control: control)
        return path
    }
}

/// A simple tapered leaf — two quadratic curves meeting at each end —
/// filled rather than stroked, then blurred and dimmed more than the stem.
private struct LeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY), control: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.midY), control: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

// MARK: - Butterfly

/// Flies in from off-screen to the first flower, then roams from bloom to
/// bloom forever, pausing to flutter at each one — skipped entirely under
/// Reduce Motion, where it just appears at the last stop. Tapping it (at
/// any point in the roam) opens the share Polaroid.
private struct ButterflyView: View {
    let landingSpots: [CGPoint]
    let reduceMotion: Bool
    let onTap: () -> Void

    @State private var position: CGPoint = .zero
    @State private var rotation: Double = 0
    @State private var flutter = false
    @State private var appeared = false
    @State private var stopIndex = 0

    var body: some View {
        Image("butterfly")
            .resizable()
            .scaledToFit()
            .frame(width: 62, height: 45)
            .contentShape(Rectangle())
            .rotationEffect(.degrees(rotation))
            .offset(x: position.x, y: position.y + (flutter && !reduceMotion ? -6 : 0))
            .opacity(appeared ? 1 : 0)
            .onTapGesture(perform: onTap)
            .onAppear { start() }
            .accessibilityLabel("Share your garden")
            .accessibilityAddTraits(.isButton)
    }

    private func start() {
        guard let first = landingSpots.first else { return }
        if reduceMotion {
            position = first
            appeared = true
            return
        }
        position = CGPoint(x: first.x + 170, y: first.y - 190)
        rotation = 24
        withAnimation(.easeOut(duration: 0.4)) { appeared = true }
        withAnimation(.easeInOut(duration: 0.9)) {
            position = first
            rotation = 0
        }
        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
            flutter = true
        }
        guard landingSpots.count > 1 else { return }
        roam(after: 1.8)
    }

    private func roam(after delay: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            stopIndex = (stopIndex + 1) % landingSpots.count
            let target = landingSpots[stopIndex]
            let headingRight = target.x > position.x
            withAnimation(.easeInOut(duration: 1.0)) {
                position = target
                rotation = headingRight ? 12 : -12
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeInOut(duration: 0.3)) { rotation = 0 }
            }
            roam(after: 2.6)
        }
    }
}

// MARK: - Share

/// The share card: a snapshot of the bouquet in a white Polaroid frame,
/// tilted like it was just tossed down, with a real `ShareLink` for the
/// image underneath.
private struct PolaroidCard: View {
    let image: UIImage?
    let flowerCount: Int
    let onClose: () -> Void

    private var summary: String {
        flowerCount == 1 ? "1 thing bloomed today" : "\(flowerCount) things bloomed today"
    }

    var body: some View {
        VStack(spacing: 14) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(red: 0.95, green: 0.87, blue: 0.85)
                }
            }
            .frame(width: 240, height: 240)
            .clipped()

            VStack(spacing: 4) {
                Text("Share your garden")
                    .font(.custom("PinyonScript-Regular", size: 32))
                    .foregroundStyle(Color(red: 0.29, green: 0.23, blue: 0.20))
                Text(summary)
                    .font(.system(size: 13, design: .serif).italic())
                    .foregroundStyle(Color(red: 0.61, green: 0.54, blue: 0.50))
            }

            if let image {
                ShareLink(
                    item: ShareableGardenImage(image: image),
                    preview: SharePreview("My Clutch garden", image: Image(uiImage: image))
                ) {
                    Text("Share")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 11)
                        .background(Color.strawberry, in: Capsule())
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .padding(.bottom, 12)
        .background(.white)
        .rotationEffect(.degrees(-2.5))
        .shadow(color: .black.opacity(0.3), radius: 26, y: 16)
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white, .black.opacity(0.45))
            }
            .padding(4)
            .rotationEffect(.degrees(2.5))
            .offset(x: 8, y: -8)
        }
    }
}

// MARK: - Dock items

/// Only `garden` and `share` do anything real yet; the rest are visual
/// placeholders not wired to any destination.
private enum DockItem: String, CaseIterable, Identifiable {
    case garden, cycle, journal, discover, share

    static let primary: [DockItem] = [.garden, .cycle, .journal, .discover]

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .garden: "leaf"
        case .cycle: "moon"
        case .journal: "book.closed"
        case .discover: "sparkles"
        case .share: "square.and.arrow.up"
        }
    }

    /// Core → rim colors, sampled from the reference strip's swatches.
    var palette: [Color] {
        switch self {
        case .garden: [Color(hex: 0xFFFBE8), Color(hex: 0xD4FDE0), Color(hex: 0xF5DFF9)]
        case .cycle: [Color(hex: 0xFFFFFF), Color(hex: 0xF5DFF9), Color(hex: 0xE9D5F7)]
        case .journal: [Color(hex: 0xFFF6D8), Color(hex: 0xFDDEDF), Color(hex: 0xE9E7F3)]
        case .discover: [Color(hex: 0xFFFFFF), Color(hex: 0xE9D5F7), Color(hex: 0xFEE4FE)]
        case .share: [Color(hex: 0xFFFDEE), Color(hex: 0xFDE6D0), Color(hex: 0xF6D5E6)]
        }
    }
}

/// The macOS Dock's press feel: the tile magnifies and lifts.
private struct DockButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.18 : 1, anchor: .bottom)
            .offset(y: configuration.isPressed ? -6 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#Preview {
    GardenView()
}
