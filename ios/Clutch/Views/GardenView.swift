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
    /// "Does this match you?" under today's line, once answered.
    @State private var lineMatchAnswer: Bool?

    private var streak: Int { BouquetCollection.streak(collectedDays: collection.map(\.day)) }

    init(signature: UIImage? = nil) {
        self.signature = signature ?? SignatureStore.load()
    }

    private static let ink = Color.ink
    private static let mutedInk = Color.mutedInk

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
                            if model.todayLine.asksForMatch {
                                lineMatchRow
                                    .transition(.opacity)
                            }
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
                        PolaroidCard(flowers: model.flowers, style: model.style, signature: signature, caption: shareCaption) {
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

            Text(model.engine.cycleDay(for: .now).map { "DAY \($0)" } ?? "DAY \u{2014}")
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
            Bouquet(flowers: bouquet.flowers, reduceMotion: true, animatesIn: false, signature: signature, style: bouquet.style)
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

    private func handleCommit(_ prompt: String) {
        promptText = prompt
    }

    /// Today in one line, tying the whole log together.
    private func handleFinished() {
        promptText = model.hasBloomed ? InsightCopy.text(for: model.todayLine) : "A quiet day. Nothing planted."
        withAnimation(.easeInOut(duration: 0.3)) {
            collection = BouquetCollection.load()
        }
        guard model.hasBloomed else { return }
        withAnimation(.easeInOut(duration: 1.4)) { bouquetCentered = true }
    }

    private func shareToday() {
        guard model.hasBloomed else { return }
        let count = model.totalLoggedCount
        shareCaption = model.flowers.isEmpty
            ? "a seed planted today"
            : (count == 1 ? "1 thing bloomed today" : "\(count) things bloomed today")
        withAnimation(.easeInOut(duration: 0.3)) { showShare = true }
    }

    private var flowerBed: some View {
        let scale: CGFloat = bouquetCentered ? 0.74 : 0.55
        return Bouquet(flowers: model.flowers, reduceMotion: reduceMotion, signature: signature, style: model.style)
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

    @ViewBuilder
    private var lineMatchRow: some View {
        if let lineMatchAnswer {
            Text(lineMatchAnswer ? "Glad it fits." : "Thanks, Clutch will keep learning.")
                .font(.system(size: 13, design: .serif).italic())
                .foregroundStyle(Self.mutedInk)
        } else {
            HStack(spacing: 10) {
                Text("Does this match you?")
                    .font(.system(size: 13, design: .serif).italic())
                    .foregroundStyle(Self.ink.opacity(0.8))
                ForEach([true, false], id: \.self) { matches in
                    Button(matches ? "Yes" : "No") { answerLineMatch(matches) }
                        .font(.custom("HelveticaNeue", size: 12))
                        .foregroundStyle(Self.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.35), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.8), lineWidth: 0.8))
                }
            }
        }
    }

    private func answerLineMatch(_ matches: Bool) {
        let line = model.todayLine
        let kind: String
        switch line {
        case .knownStretch: kind = "knownStretch"
        case .goodWindow: kind = "goodWindow"
        default: kind = "other"
        }
        InsightStore.record(.init(date: .now, insight: "today.\(kind)", text: InsightCopy.text(for: line), matches: matches))
        withAnimation(.easeInOut(duration: 0.2)) { lineMatchAnswer = matches }
    }

    private var gardenSummaryLabel: String {
        let count = model.totalLoggedCount
        return count == 0 ? "Your garden: empty" : "Your garden: \(count) flower\(count == 1 ? "" : "s")"
    }
}

// MARK: - Swipe deck

/// The stacked card deck: one live card up front, two more peeking behind
/// it for depth. Symptom cards swipe (right yes, left no, with ✕ / ♥ tap
/// targets that mirror the gesture); the rest are tapped. A yes can flip
/// the card over to an insight. "Nothing today" sits under every card.
private struct SwipeDeck: View {
    @ObservedObject var model: GardenModel
    let onCommit: (_ prompt: String) -> Void
    let onFinished: () -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var cardOpacity: Double = 1
    /// The card turned over after a yes swipe, until she moves on.
    @State private var flip: FlipInsight?

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                if let flip {
                    InsightFlipCard(flip: flip, flowers: model.flowers, style: model.style, onContinue: endFlip)
                        .frame(height: 300)
                        .offset(dragOffset)
                        .opacity(cardOpacity)
                        .id(flip.id)
                } else {
                    ForEach(Array(model.upcoming(3).enumerated()).reversed(), id: \.element.id) { pair in
                        card(pair.element, depth: pair.offset)
                    }
                }
            }
            .frame(height: 316)

            if flip == nil, case let .symptom(symptom) = model.currentCard {
                HStack(spacing: 36) {
                    tapButton(systemName: "xmark", tint: .mutedInk) {
                        swipe(symptom, yes: false)
                    }
                    .accessibilityLabel("No \(symptom.label)")

                    tapButton(systemName: "heart.fill", tint: .white, background: Color.matcha) {
                        swipe(symptom, yes: true)
                    }
                    .accessibilityLabel("Yes, \(symptom.label)")
                }
            }

            if flip == nil && !model.isFinished {
                Button(action: nothingToday) {
                    Text("Nothing today")
                        .font(.custom("HelveticaNeue", size: 12))
                        .foregroundStyle(Color.mutedInk)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .overlay(Capsule().strokeBorder(Color.mutedInk.opacity(0.6), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Cards

    private func card(_ deckCard: DeckCard, depth: Int) -> some View {
        let isTop = depth == 0

        return ZStack {
            content(for: deckCard)
                .allowsHitTesting(isTop)

            if isTop && deckCard.isSwipe {
                stamp("YES", tint: Color.matcha, alignment: .topTrailing, opacity: yesStampOpacity)
                stamp("NO", tint: .mutedInk, alignment: .topLeading, opacity: noStampOpacity)
            }
        }
        .frame(height: 300)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .scaleEffect(isTop ? 1 : 1 - CGFloat(depth) * 0.04)
        .offset(y: isTop ? 0 : CGFloat(depth) * 10)
        .offset(isTop ? dragOffset : .zero)
        .rotationEffect(.degrees(isTop && deckCard.isSwipe ? dragOffset.width / 18 : 0))
        .opacity(isTop ? cardOpacity : 1)
        .zIndex(isTop ? 10 : Double(9 - depth))
        .gesture(isTop ? swipeGesture(for: deckCard) : nil)
        .accessibilityHidden(!isTop)
    }

    @ViewBuilder
    private func content(for deckCard: DeckCard) -> some View {
        switch deckCard {
        case let .symptom(symptom):
            CrosswordCard(symptom: symptom)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(symptom.question)
                .accessibilityAction(named: "Yes") { swipe(symptom, yes: true) }
                .accessibilityAction(named: "No") { swipe(symptom, yes: false) }

        case .flow:
            FlowCard { flow in
                answer(flow == .noFlow ? "No period today." : "Period logged, \(flow.rawValue) flow.") {
                    model.answerFlow(flow)
                }
            }

        case .mood:
            LevelCard(word: "mood", aura: 0, question: "How's your mood today?", titles: LevelScale.moodTitles) { level in
                answer("Mood: \(LevelScale.moodTitles[level - 1].lowercased()).") { model.answerMood(level) }
            }

        case .energy:
            LevelCard(word: "energy", aura: 1, question: "How's your energy today?", titles: LevelScale.energyTitles) { level in
                answer("Energy: \(LevelScale.energyTitles[level - 1].lowercased()).") { model.answerEnergy(level) }
            }

        case .helped:
            HelpedCard(question: "Today was a lot. What helped?", options: Helper.options) { helpers in
                answer("Noted what helped.") { model.answerHelped(helpers) }
            }

        case let .followUp(day, symptomIDs, daysAgo):
            HelpedCard(
                question: InsightCopy.followUpQuestion(symptomIDs: symptomIDs, daysAgo: daysAgo, day: day),
                options: Helper.options + [.nothingReally]
            ) { helpers in
                answer("Thanks. Clutch is learning what helps you.") { model.answerFollowUp(helpers, about: day) }
            }

        case let .oneTime(question):
            OneTimeCard(
                question: question,
                onAnswer: { update in answer("Saved.") { model.answerOneTime(question, update: update) } },
                onSkip: { answer("Skipped for now.") { model.skipOneTime(question) } }
            )
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

    private var yesStampOpacity: Double { min(1, max(0, dragOffset.width - 20) / 70) }
    private var noStampOpacity: Double { min(1, max(0, -dragOffset.width - 20) / 70) }

    /// Only symptom cards swipe; mood and energy use their own drag.
    private func swipeGesture(for deckCard: DeckCard) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard deckCard.isSwipe else { return }
                dragOffset = CGSize(width: value.translation.width, height: value.translation.height * 0.35)
            }
            .onEnded { value in
                guard case let .symptom(symptom) = deckCard else { return }
                if value.translation.width > 88 {
                    swipe(symptom, yes: true)
                } else if value.translation.width < -88 {
                    swipe(symptom, yes: false)
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

    // MARK: Answering

    /// A yes that has something to say turns the card over; otherwise the
    /// card flies off the way it was swiped.
    private func swipe(_ symptom: Symptom, yes: Bool) {
        guard yes else {
            flyAway(toRight: false, prompt: "No \(symptom.label) today.") { model.answerSymptom(symptom, yes: false) }
            return
        }
        let prompt = "\u{201C}\(symptom.label)\u{201D} bloomed."
        guard let insight = model.insightIfYes(symptom) else {
            flyAway(toRight: true, prompt: prompt) { model.answerSymptom(symptom, yes: true) }
            return
        }
        onCommit(prompt)
        model.answerSymptom(symptom, yes: true)
        model.markShown(insight)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { dragOffset = .zero }
        flip = insight
    }

    private func endFlip() {
        withAnimation(.easeIn(duration: 0.35)) {
            dragOffset = CGSize(width: 520, height: 40)
            cardOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            flip = nil
            dragOffset = .zero
            cardOpacity = 1
            if model.isFinished { onFinished() }
        }
    }

    /// Tap cards lift up and away.
    private func answer(_ prompt: String, apply: @escaping () -> Void) {
        withAnimation(.easeIn(duration: 0.3)) {
            dragOffset = CGSize(width: 0, height: -60)
            cardOpacity = 0
        }
        onCommit(prompt)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            apply()
            dragOffset = .zero
            cardOpacity = 1
            if model.isFinished { onFinished() }
        }
    }

    private func flyAway(toRight: Bool, prompt: String?, apply: @escaping () -> Void) {
        withAnimation(.easeIn(duration: 0.4)) {
            dragOffset = CGSize(width: toRight ? 520 : -520, height: 40)
            cardOpacity = 0
        }
        if let prompt { onCommit(prompt) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            apply()
            dragOffset = .zero
            cardOpacity = 1
            if model.isFinished { onFinished() }
        }
    }

    private func nothingToday() {
        answer("Seed planted.") { model.nothingToday() }
    }
}

// MARK: - Share

/// The share card: a snapshot of the bouquet in a white Polaroid frame,
/// tilted like it was just tossed down, with one-tap share targets
/// underneath.
struct PolaroidCard: View {
    let flowers: [PlantedFlower]
    var style: BouquetStyle = .plain
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
                    .foregroundStyle(Color.ink)
                Text(caption)
                    .font(.system(size: 13, design: .serif).italic())
                    .foregroundStyle(Color.mutedInk)
            }

            if signature != nil {
                Toggle("Include my name", isOn: $includeName)
                    .font(.system(size: 14, design: .serif).italic())
                    .foregroundStyle(Color.ink)
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

    private static let ink = Color.ink

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
        image = BouquetSnapshot.image(of: flowers, signature: includeName ? signature : nil, style: style)
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
                .foregroundStyle(Color.ink)
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
