import SwiftUI
import UIKit

/// The Garden screen: one card at a time as a swipeable deck — right to
/// log, left to skip. Either direction adds a gradient tulip to the day's
/// bouquet (showing up counts, even when the answer is "skip"). A finished
/// bouquet can be shared, and joins the collection that tracks her streak.
struct GardenView: View {
    let signature: UIImage?

    @StateObject private var model = GardenModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var promptText = "Log how you feel, your garden fills as you go."
    @State private var showShare = false
    @State private var didStart = false
    @State private var shareCaption = ""
    @State private var showCollection = false
    @State private var showRequest = false
    @State private var showDetails = false
    @State private var collection: [CollectedBouquet] = []
    /// Once the deck is done the bouquet grows to full size in the middle
    /// of the screen; while logging it sits smaller, low, under the cards.
    @State private var bouquetCentered = false

    private var streak: Int { BouquetCollection.streak(collectedDays: collection.map(\.day)) }

    init(signature: UIImage? = nil) {
        self.signature = signature ?? SignatureStore.load()
    }

    /// The two-tone text palette used throughout: a near-black warm brown
    /// for anything primary/active, a muted taupe for secondary labels.
    private static let ink = Color(red: 0.29, green: 0.23, blue: 0.20)
    private static let mutedInk = Color(red: 0.61, green: 0.54, blue: 0.50)

    @State private var selectedDockItem: DockItem = .garden

    var body: some View {
        ZStack {
            AuraBackground()

            flowerBed
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: bouquetCentered ? .center : .bottom)
                .padding(.bottom, bouquetCentered ? 150 : 80)

            if bouquetCentered {
                afterBloom
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 118)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

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
                        } else if model.hasBloomed {
                            HStack(spacing: 12) {
                                GardenChip(title: "Share bouquet", symbol: "square.and.arrow.up") {
                                    shareToday()
                                }
                                GardenChip(
                                    title: streak == 1 ? "1-day streak" : "\(streak)-day streak",
                                    symbol: "rectangle.stack"
                                ) {
                                    showCollection = true
                                }
                            }
                            .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8)
                    // Rises out of the orb up into the space the header leaves.
                    .transition(.asymmetric(
                        insertion: .offset(y: 380).combined(with: .opacity),
                        removal: .opacity
                    ))
                } else {
                    startState
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }

            // The name and wordmark step aside once the day starts, so the
            // deck and the flowers have the screen.
            if !didStart {
                topBar
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if showShare {
                // A Polaroid card over the same screen rather than a system
                // sheet — sharing never leaves the garden.
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.25)) { showShare = false } }
                    .overlay {
                        PolaroidCard(flowers: model.flowers, signature: signature, caption: shareCaption) {
                            withAnimation(.easeInOut(duration: 0.25)) { showShare = false }
                        }
                    }
                    .transition(.opacity)
            }

            dock
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .sheet(isPresented: $showCollection) {
            BouquetCollectionView(bouquets: collection, streak: streak)
        }
        .sheet(isPresented: $showRequest) {
            RequestView()
        }
        .navigationDestination(isPresented: $showDetails) {
            YouView()
                .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            collection = BouquetCollection.load()
            // Resuming after today's deck was already finished (app relaunched,
            // came back from another tab) — the commit flow that normally
            // drives this UI never runs, so re-derive it from the model.
            // Also skip straight past the "Start today" gate in that case;
            // there's nothing left to start.
            guard model.isFinished else { return }
            didStart = true
            handleFinished()
            #if DEBUG
            if DebugLaunch.showShare { shareToday() }
            #endif
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
        .padding(.top, 68)
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

            // Not derived from the saved cycle start yet, so the day is a
            // placeholder.
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
    /// "share", and a dot under the active item.
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
                shareToday()
            } else if item == .bouquets {
                showCollection = true
            } else if item == .request {
                showRequest = true
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

    /// Earlier bouquets, newest first — today's is the big one above.
    private var recentBouquets: [CollectedBouquet] {
        let today = Calendar.current.startOfDay(for: .now)
        return Array(collection.filter { Calendar.current.startOfDay(for: $0.day) != today }.prefix(4))
    }

    /// Under the finished bouquet: the ones before it, then the way on to
    /// everything the app knows about her.
    private var afterBloom: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Recent bouquets")
                        .font(.system(size: 13, design: .serif).italic())
                        .foregroundStyle(Self.ink.opacity(0.8))
                    Spacer()
                    if !recentBouquets.isEmpty {
                        Button("See all") { showCollection = true }
                            .font(.custom("HelveticaNeue", size: 12))
                            .foregroundStyle(Self.mutedInk)
                    }
                }

                if recentBouquets.isEmpty {
                    Text("Your past bouquets will gather here, one for each day you check in.")
                        .font(.system(size: 12, design: .serif).italic())
                        .foregroundStyle(Self.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: 10) {
                        ForEach(recentBouquets) { bouquet in
                            Button { showCollection = true } label: {
                                miniBouquet(bouquet)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Bouquet from \(bouquet.day.formatted(date: .long, time: .omitted))")
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            Button { showDetails = true } label: {
                HStack(spacing: 8) {
                    Text("See your details")
                        .font(.custom("HelveticaNeue-Medium", size: 15))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Color(hex: 0xFDF6F2))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Self.ink, in: Capsule())
                .shadow(color: Self.ink.opacity(0.25), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
    }

    private func miniBouquet(_ bouquet: CollectedBouquet) -> some View {
        VStack(spacing: 4) {
            Bouquet(flowers: bouquet.flowers, reduceMotion: true, animatesIn: false, signature: signature)
                .scaleEffect(0.11, anchor: .bottom)
                .frame(width: 56, height: 62, alignment: .bottom)
                .clipped()
            Text(bouquet.day.formatted(.dateTime.month(.abbreviated).day()))
                .font(.custom("HelveticaNeue", size: 9))
                .foregroundStyle(Self.ink.opacity(0.7))
        }
        .padding(6)
        .background(.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.8), lineWidth: 0.6))
    }

    /// The idle screen shown before today's deck begins: the glass orb that
    /// starts the day, with the prompt written around it.
    private var startState: some View {
        StartOrb(text: "log how you feel  \u{2726}  your garden fills  \u{2726}  tap to begin  \u{2726}  ") {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) { didStart = true }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: 20)
    }

    private func handleCommit(keep: Bool, symptom: Symptom, flow: Flow?) {
        if keep, let flow {
            promptText = "Period logged, \(flow.rawValue) flow."
        } else {
            promptText = keep ? "\u{201C}\(symptom.label)\u{201D} bloomed." : "skipped."
        }
    }

    private func handleFinished() {
        promptText = model.hasBloomed ? "Your bouquet today." : "A quiet day. Nothing planted."
        withAnimation(.easeInOut(duration: 0.3)) {
            collection = BouquetCollection.load()
        }
        guard model.hasBloomed else { return }
        withAnimation(.easeInOut(duration: 1.4)) { bouquetCentered = true }
    }

    private func shareToday() {
        guard model.hasBloomed else { return }
        let count = model.totalLoggedCount
        shareCaption = count == 1 ? "1 thing bloomed today" : "\(count) things bloomed today"
        withAnimation(.easeInOut(duration: 0.3)) { showShare = true }
    }

    private var flowerBed: some View {
        let scale: CGFloat = bouquetCentered ? 0.74 : 0.55
        return Bouquet(flowers: model.flowers, reduceMotion: reduceMotion, signature: signature)
            .scaleEffect(scale, anchor: .bottom)
            .frame(width: Bouquet.size.width, height: Bouquet.size.height * scale, alignment: .bottom)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                if model.isFinished && model.hasBloomed { shareToday() }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(gardenSummaryLabel)
            .accessibilityAddTraits(model.isFinished && model.hasBloomed ? .isButton : [])
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
    let onCommit: (_ keep: Bool, _ symptom: Symptom, _ flow: Flow?) -> Void
    let onFinished: () -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var cardOpacity: Double = 1
    /// Set after a right swipe on the period card, while flow is picked.
    @State private var askingFlow = false

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                ForEach(Array(model.upcoming(3).enumerated()).reversed(), id: \.element.id) { pair in
                    card(symptom: pair.element, depth: pair.offset)
                }
            }
            .frame(height: 316)

            if let symptom = model.currentSymptom, !askingFlow {
                HStack(spacing: 36) {
                    tapButton(systemName: "xmark", tint: Color(red: 0.61, green: 0.54, blue: 0.50)) {
                        commit(false, symptom: symptom)
                    }
                    .accessibilityLabel("Skip \(symptom.label)")

                    tapButton(systemName: "heart.fill", tint: .white, background: Color.matcha) {
                        log(symptom)
                    }
                    .accessibilityLabel("Log \(symptom.label)")
                }
            }
        }
    }

    private func card(symptom: Symptom, depth: Int) -> some View {
        let isTop = depth == 0

        return ZStack {
            CrosswordCard(symptom: symptom)

            if isTop {
                stamp("LOG", tint: Color.matcha, alignment: .topTrailing, opacity: logStampOpacity)
                stamp("SKIP", tint: Color(red: 0.61, green: 0.54, blue: 0.50), alignment: .topLeading, opacity: skipStampOpacity)
            }

            if isTop && askingFlow {
                FlowPicker(
                    onPick: { flow in
                        commit(true, symptom: symptom, flow: flow)
                    },
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.25)) { askingFlow = false }
                    }
                )
                .transition(.opacity)
            }
        }
        .frame(height: 300)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .scaleEffect(isTop ? 1 : 1 - CGFloat(depth) * 0.04)
        .offset(y: isTop ? 0 : CGFloat(depth) * 10)
        .offset(isTop ? dragOffset : .zero)
        .rotationEffect(.degrees(isTop ? dragOffset.width / 18 : 0))
        .opacity(isTop ? cardOpacity : 1)
        .zIndex(isTop ? 10 : Double(9 - depth))
        .gesture(isTop && !askingFlow ? dragGesture(for: symptom) : nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isTop ? symptom.label : "")
        .accessibilityAddTraits(isTop ? .isButton : [])
        .accessibilityActions {
            if isTop {
                Button("Log \(symptom.label)") { log(symptom) }
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
                    log(symptom)
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

    /// A right swipe / heart. The period card first asks for flow; every
    /// other card logs straight away.
    private func log(_ symptom: Symptom) {
        guard symptom.asksForFlow else {
            commit(true, symptom: symptom)
            return
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            dragOffset = .zero
            askingFlow = true
        }
    }

    private func commit(_ keep: Bool, symptom: Symptom, flow: Flow? = nil) {
        let flyDistance: CGFloat = keep ? 520 : -520
        withAnimation(.easeIn(duration: 0.4)) {
            dragOffset = CGSize(width: flyDistance, height: 40)
            cardOpacity = 0
        }
        onCommit(keep, symptom, flow)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if keep { model.logCurrent(flow: flow) } else { model.skipCurrent() }
            dragOffset = .zero
            cardOpacity = 1
            askingFlow = false
            if model.isFinished { onFinished() }
        }
    }
}

// MARK: - Share

/// The share card: a snapshot of the bouquet in a white Polaroid frame,
/// tilted like it was just tossed down, with one-tap share targets
/// underneath.
struct PolaroidCard: View {
    let flowers: [PlantedFlower]
    /// When there is one, the card offers to put her name on the bouquet.
    let signature: UIImage?
    let caption: String
    let onClose: () -> Void

    @State private var includeName = true
    @State private var image: UIImage?
    @State private var saved = false

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
                Text("Share your bouquet")
                    .font(.custom("PinyonScript-Regular", size: 32))
                    .foregroundStyle(Color(red: 0.29, green: 0.23, blue: 0.20))
                Text(caption)
                    .font(.system(size: 13, design: .serif).italic())
                    .foregroundStyle(Color(red: 0.61, green: 0.54, blue: 0.50))
            }

            if signature != nil {
                Toggle("Include my name", isOn: $includeName)
                    .font(.system(size: 14, design: .serif).italic())
                    .foregroundStyle(Color(red: 0.29, green: 0.23, blue: 0.20))
                    .tint(Color(hex: 0xD68EA5))
                    .frame(width: 220)
            }

            if let image {
                shareTargets(for: image)
                    .padding(.top, 4)
            }
        }
        .padding(16)
        .padding(.bottom, 12)
        .background(.white)
        // Inside the frame, over the photo's corner, so it turns with the card.
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Self.ink)
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.85), in: Circle())
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            }
            .padding(24)
            .accessibilityLabel("Close")
        }
        .onAppear(perform: render)
        .onChange(of: includeName) { render() }
        .rotationEffect(.degrees(-2.5))
        .shadow(color: .black.opacity(0.3), radius: 26, y: 16)
    }

    private static let ink = Color(red: 0.29, green: 0.23, blue: 0.20)

    /// One tap to each place she's likely to post it. Story and Messages
    /// fall back to the share sheet when they can't open directly; TikTok
    /// always goes through it, since that's how TikTok takes images.
    private func shareTargets(for image: UIImage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            shareButton("Story", symbol: "camera") {
                if !BouquetSharing.shareToInstagramStory(image) { BouquetSharing.presentShareSheet(image, text: shareText) }
            }
            shareButton("TikTok", symbol: "music.note") {
                BouquetSharing.presentShareSheet(image, text: shareText)
            }
            shareButton("iMessage", symbol: "message") {
                if !BouquetSharing.shareToMessages(image, body: shareText) { BouquetSharing.presentShareSheet(image, text: shareText) }
            }
            shareButton(saved ? "Saved" : "Save", symbol: saved ? "checkmark" : "arrow.down.to.line") {
                BouquetSharing.saveToPhotos(image) { ok in
                    withAnimation(.easeInOut(duration: 0.2)) { saved = ok }
                }
            }
            shareButton("More", symbol: "ellipsis") {
                BouquetSharing.presentShareSheet(image, text: shareText)
            }
        }
    }

    private var shareText: String { "\(caption) \u{2014} my Clutch bouquet" }

    private func shareButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Self.ink)
                    .frame(width: 44, height: 44)
                    .background(Color.strawberry, in: Circle())
                Text(title)
                    .font(.system(size: 10, design: .serif).italic())
                    .foregroundStyle(Self.ink.opacity(0.8))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title == "Story" ? "Share to Instagram story" : title)
    }

    private func render() {
        saved = false
        image = BouquetSnapshot.image(of: flowers, signature: includeName ? signature : nil)
    }
}

// MARK: - Dock items

/// `garden`, `request`, `bouquets` and `share` are wired up; `cycle` is a
/// visual placeholder not wired to any destination yet.
private enum DockItem: String, CaseIterable, Identifiable {
    case garden, cycle, request, bouquets, share

    static let primary: [DockItem] = [.garden, .cycle, .request, .bouquets]

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .garden: "leaf"
        case .cycle: "moon"
        case .request: "hand.raised"
        case .bouquets: "rectangle.stack"
        case .share: "square.and.arrow.up"
        }
    }

    /// Core → rim colors, sampled from the reference strip's swatches.
    var palette: [Color] {
        switch self {
        case .garden: [Color(hex: 0xFFFBE8), Color(hex: 0xD4FDE0), Color(hex: 0xF5DFF9)]
        case .cycle: [Color(hex: 0xFFFFFF), Color(hex: 0xF5DFF9), Color(hex: 0xE9D5F7)]
        case .request: [Color(hex: 0xFFFBF0), Color(hex: 0xFDDCE6), Color(hex: 0xE7DCF6)]
        case .bouquets: [Color(hex: 0xFFF6D8), Color(hex: 0xFDDEDF), Color(hex: 0xE9E7F3)]
        case .share: [Color(hex: 0xFFFDEE), Color(hex: 0xFDE6D0), Color(hex: 0xF6D5E6)]
        }
    }
}

/// The macOS Dock's press feel: the tile magnifies and lifts.
private struct DockButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Stays in place — just dims a touch while pressed.
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    GardenView()
}

/// A small frosted pill for actions under the finished bouquet.
private struct GardenChip: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.custom("HelveticaNeue-Medium", size: 14))
                .foregroundStyle(Color(red: 0.29, green: 0.23, blue: 0.20))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .background(.white.opacity(0.35), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.8), lineWidth: 0.8))
                .shadow(color: Color(hex: 0xB0587F).opacity(0.15), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }
}
