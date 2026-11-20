import SwiftUI
import UIKit

/// The Garden screen: today's log as a deck of at most four cards —
/// swiping moves between them, inputs inside are taps. Every card adds a
/// flower to the day's bouquet (showing up counts). When the log is done
/// the new flower blooms, flies into the bouquet and the streak ticks up;
/// then "See full details" opens what her logs add up to.
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
    @State private var showProfile = false
    @State private var collection: [CollectedBouquet] = []
    /// Once the deck is done the bouquet grows to full size in the middle
    /// of the screen; while logging it sits smaller, low, under the cards.
    @State private var bouquetCentered = false
    /// The bloom → fly in → streak tick sequence after the last card.
    @State private var celebration: Celebration?
    /// Today's newest flower stays out of the bouquet until it lands.
    @State private var holdsNewestFlower = false
    /// A little sway when the flower lands.
    @State private var landingSway = false
    /// Done for the day and back on the clean home screen: name, wordmark,
    /// today's bouquet, the period chip.
    @State private var atHome = false
    /// The cloud's first-visit tour of the home screen.
    @State private var walkthroughStep: WalkthroughStep?

    private var streak: Int { BouquetCollection.streak(collectedDays: collection.map(\.day)) }

    init(signature: UIImage? = nil) {
        self.signature = signature ?? SignatureStore.load()
    }

    private static let ink = Color.ink
    private static let mutedInk = Color.mutedInk

    @State private var selectedDockItem: DockItem = .garden
    /// A feature screen opened from the cloud, the dock or a widget tap.
    @State private var feature: AppRouter.Route?
    @ObservedObject private var router = AppRouter.shared

    var body: some View {
        ZStack {
            AuraBackground()

            flowerBed
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: bouquetCentered ? .center : .bottom)
                .padding(.bottom, atHome ? 210 : (bouquetCentered ? 150 : 80))
                .padding(.top, atHome ? 120 : 0)

            if bouquetCentered && celebration == nil && !atHome {
                afterBloom
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 118)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Group {
                if atHome {
                    homeState
                        .transition(.opacity)
                } else if didStart {
                    VStack(spacing: 22) {
                        Text(promptText)
                            .font(.system(size: 17, design: .serif).italic())
                            .foregroundStyle(Self.ink)
                            .multilineTextAlignment(.center)
                            .animation(.easeInOut(duration: 0.3), value: promptText)
                            // Room on the right for the cloud.
                            .padding(.leading, 28)
                            .padding(.trailing, 96)
                            .opacity(celebration == nil ? 1 : 0)

                        if !model.isFinished {
                            SwipeDeck(model: model, onCommit: handleCommit, onFinished: { handleFinished(animated: true) })
                                .padding(.horizontal, 28)
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
            if !didStart || atHome {
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
                            withAnimation(.easeInOut(duration: 0.35)) {
                                showShare = false
                                atHome = true
                            }
                        }
                    }
                    .transition(.opacity)
            }

            if let celebration {
                BloomCelebration(
                    celebration: celebration,
                    style: model.style,
                    onLanded: flowerLanded,
                    onDetails: {
                        endCelebration(offerShare: false)
                        showDetails = true
                    },
                    onDone: { endCelebration() }
                )
                .transition(.opacity)
                .zIndex(5)
            }

            dock
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .opacity(celebration == nil && !showShare ? 1 : 0)

            if celebration == nil && !showShare {
                gardenCloud
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, didStart && !atHome ? 0 : 150)
                    .padding(.trailing, 14)
            }
        }
        .overlayPreferenceValue(WalkthroughAnchorKey.self) { anchors in
            if walkthroughStep != nil {
                WalkthroughOverlay(anchors: anchors, step: $walkthroughStep)
            }
        }
        .sheet(item: $feature) { route in
            FeatureScreen(route: route)
        }
        .onReceive(router.$pending) { route in
            guard let route else { return }
            router.pending = nil
            switch route {
            case .today: break
            case .request: showRequest = true
            default: feature = route
            }
        }
        .sheet(isPresented: $showCollection) {
            BouquetCollectionView(bouquets: collection, streak: streak)
        }
        .sheet(isPresented: $showRequest) {
            RequestView()
        }
        .sheet(isPresented: $showProfile) {
            ProfileView(signature: signature)
        }
        .navigationDestination(isPresented: $showDetails) {
            DetailsView()
                .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            collection = BouquetCollection.load()
            startWalkthroughIfNeeded()
            // Resuming after today's deck was already finished (app relaunched,
            // came back from another tab) — the commit flow that normally
            // drives this UI never runs, so re-derive it from the model.
            // Also skip straight past the "Start today" gate in that case;
            // there's nothing left to start.
            guard model.isFinished else { return }
            didStart = true
            handleFinished(animated: false)
            // Coming back to a finished day: straight to the clean home.
            atHome = true
            #if DEBUG
            if DebugLaunch.showShare { shareToday() }
            #endif
        }
    }

    /// The cloud, always nearby: it reacts to today and opens its home.
    private var gardenCloud: some View {
        let moment = MascotMoment.make(at: .now, snapshot: CycleSnapshot.load())
        let face: FuzzyCloud.Face = moment.scene == .sleep ? .sleepy : (moment.scene == .drizzle || moment.line.hasPrefix("Rough")) ? .soft : .happy
        return Button { feature = .cloud } label: {
            FuzzyCloud(face: face, gloomy: moment.scene == .drizzle)
                .frame(width: 74)
                .overlay(alignment: .topTrailing) {
                    if moment.sparkle {
                        Image(systemName: "sparkle").font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(red: 1, green: 0.84, blue: 0.45))
                    }
                }
                // A self-contained bob: a repeating withAnimation here used to
                // sweep up the screen's first layout and set the dock labels
                // and the cloud itself drifting.
                .phaseAnimator(reduceMotion ? [false] : [false, true]) { content, up in
                    content.offset(y: up ? -3 : 3)
                } animation: { _ in .easeInOut(duration: 2.4) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Your cloud: \(moment.line)")
        .walkthroughTarget(.cloud)
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

    /// Her name opens her profile.
    private var signatureBox: some View {
        Button { showProfile = true } label: { signatureCard }
            .buttonStyle(.plain)
            .accessibilityLabel("Your profile")
    }

    private var signatureCard: some View {
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
                .padding(.bottom, 16)

            dockButton(.share)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 7)
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
            } else if item == .cycle {
                feature = .tracker
            } else {
                selectedDockItem = item
            }
        } label: {
            VStack(spacing: 4) {
                AuraTile(palette: item.palette, symbol: item.symbol)
                    .frame(width: 48, height: 48)
                    .modifier(DockWalkthroughTarget(item: item))

                Text(item.title)
                    .font(.custom(isSelected ? "HelveticaNeue-Medium" : "HelveticaNeue", size: 9.5))
                    .foregroundStyle(.black.opacity(isSelected ? 0.75 : 0.5))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .buttonStyle(DockButtonStyle())
        .accessibilityLabel(item.title)
    }

    /// Under the finished bouquet, only two things: her streak (opens her
    /// past bouquets) and sharing today's. A quiet link leads on to her
    /// cycle so far.
    private var afterBloom: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                GardenChip(title: streak == 1 ? "1-day streak" : "\(streak)-day streak", symbol: "flame") {
                    showCollection = true
                }
                if model.hasBloomed {
                    GardenChip(title: "Share bouquet", symbol: "square.and.arrow.up") {
                        shareToday()
                    }
                }
            }

            HStack {
                Button { showDetails = true } label: {
                    HStack(spacing: 4) {
                        Text("your cycle so far")
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .medium))
                    }
                    .font(.system(size: 14, design: .serif).italic())
                    .foregroundStyle(Self.ink.opacity(0.75))
                }
                .buttonStyle(.plain)

                Spacer()

                // Done: on to the clean home screen.
                Button { goHome() } label: {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(Self.ink)
                        .frame(width: 46, height: 46)
                        .background(.ultraThinMaterial, in: Circle())
                        .background(.white.opacity(0.35), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 0.8))
                        .shadow(color: Color(hex: 0xB0587F).opacity(0.18), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Home")
            }
        }
        .padding(.horizontal, 28)
    }

    /// Once, on the first visit after onboarding, before the day's started.
    private func startWalkthroughIfNeeded() {
        var force = false
        #if DEBUG
        force = DebugLaunch.walkthrough
        #endif
        guard force || (!Walkthrough.isDone && !model.isFinished && (CycleProfile.load()?.onboardingComplete ?? false)) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            guard force || !didStart else { return }
            var first = WalkthroughStep.checkIn
            #if DEBUG
            first = WalkthroughStep(rawValue: DebugLaunch.walkthroughStep) ?? .checkIn
            #endif
            withAnimation(.easeInOut(duration: 0.35)) { walkthroughStep = first }
        }
    }

    private func goHome() {
        withAnimation(.easeInOut(duration: 0.45)) { atHome = true }
    }

    /// Home once today's check-in is done: the bouquet sits under her name
    /// and the wordmark, with the period chip below. Tap the bouquet to
    /// share it again.
    private var homeState: some View {
        VStack(spacing: 12) {
            Spacer()
            periodChip
            Button { showDetails = true } label: {
                HStack(spacing: 4) {
                    Text("your cycle so far")
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .medium))
                }
                .font(.system(size: 14, design: .serif).italic())
                .foregroundStyle(Self.ink.opacity(0.75))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 128)
    }

    /// The idle screen shown before today's deck begins: the glass orb that
    /// starts the day, with the prompt written around it.
    private var startState: some View {
        StartOrb(text: "log how you feel  \u{2726}  your garden fills  \u{2726}  tap to begin  \u{2726}  ") {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) { didStart = true }
        }
        .walkthroughTarget(.checkIn)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: 20)
        .overlay(alignment: .bottom) {
            periodChip
                .padding(.bottom, 140)
        }
    }

    /// Always here on the Today screen: "My period started", or which
    /// period day it is once one's running.
    @ViewBuilder
    private var periodChip: some View {
        if let day = model.engine.periodDay(for: .now) {
            GardenChip(title: "Period, day \(day)", symbol: "drop.fill") {}
                .allowsHitTesting(false)
        } else {
            GardenChip(title: "My period started", symbol: "drop") {
                withAnimation(.easeInOut(duration: 0.25)) { model.startPeriod() }
            }
        }
    }

    private func handleCommit(_ prompt: String) {
        promptText = prompt
    }

    /// The log is done. Straight after the last card the new flower
    /// blooms, flies into the bouquet and the streak ticks up; coming back
    /// to a finished day just shows the settled bouquet.
    private func handleFinished(animated: Bool) {
        let line = InsightCopy.text(for: model.todayLine)
        promptText = model.hasBloomed ? line : "A quiet day. Nothing planted."
        let before = BouquetCollection.load()
        withAnimation(.easeInOut(duration: 0.3)) { collection = before }
        guard model.hasBloomed else { return }
        guard animated else {
            withAnimation(.easeInOut(duration: 1.4)) { bouquetCentered = true }
            return
        }

        let today = Calendar.current.startOfDay(for: .now)
        let days = collection.map(\.day)
        let after = BouquetCollection.streak(collectedDays: days)
        let streakBefore = BouquetCollection.streak(collectedDays: days.filter { Calendar.current.startOfDay(for: $0) != today })
        let milestone = Celebration.milestone(streak: after, engine: model.engine, today: model.log)
        if let milestone { model.recordMilestone(milestone.id) }

        // The bouquet stays low while the flower blooms above it, and moves
        // up once the flower has landed.
        holdsNewestFlower = !model.log.nothingToday
        withAnimation(.easeInOut(duration: 0.3)) {
            celebration = Celebration(
                flower: model.log.nothingToday ? nil : model.flowers.last,
                streakBefore: min(streakBefore, after),
                streakAfter: after,
                milestone: milestone?.line,
                line: line
            )
        }
    }

    private func flowerLanded() {
        holdsNewestFlower = false
        withAnimation(.easeInOut(duration: reduceMotion ? 0.3 : 0.8)) { bouquetCentered = true }
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.35)) { landingSway = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) { landingSway = false }
        }
    }

    /// The bouquet's done: offer to share it straight away. Closing the
    /// share card lands on the clean home.
    private func endCelebration(offerShare: Bool = true) {
        holdsNewestFlower = false
        bouquetCentered = true
        withAnimation(.easeInOut(duration: 0.3)) { celebration = nil }
        guard offerShare, model.hasBloomed else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { shareToday() }
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
        let scale: CGFloat = atHome ? 0.56 : (bouquetCentered ? 0.74 : 0.55)
        let flowers = holdsNewestFlower ? Array(model.flowers.dropLast()) : model.flowers
        return Bouquet(flowers: flowers, reduceMotion: reduceMotion, signature: signature, style: model.style)
            .rotationEffect(.degrees(landingSway ? 2.5 : 0), anchor: .bottom)
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

/// The stacked deck: one live card up front, the next ones peeking behind
/// it. Inputs inside a card are taps; a swipe either way moves on without
/// answering. "Nothing today" sits under every card, and "My period
/// started" on the first one when her period is due.
private struct SwipeDeck: View {
    @ObservedObject var model: GardenModel
    let onCommit: (_ prompt: String) -> Void
    let onFinished: () -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var cardOpacity: Double = 1

    var body: some View {
        VStack(spacing: 18) {
            if model.currentIndex == 0 && model.offersPeriodStart && !model.log.periodStarted {
                GardenChip(title: "My period started", symbol: "drop") {
                    withAnimation(.easeInOut(duration: 0.25)) { model.startPeriod() }
                    onCommit("Period logged. Flow comes last today.")
                }
                .transition(.opacity)
            }

            ZStack {
                ForEach(Array(model.upcoming(3).enumerated()).reversed(), id: \.element.id) { pair in
                    card(pair.element, depth: pair.offset)
                }
            }
            .frame(height: 316)

            if !model.isFinished {
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

        return content(for: deckCard)
            .allowsHitTesting(isTop)
            .frame(height: 300)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(isTop ? 1 : 1 - CGFloat(depth) * 0.04)
            .offset(y: isTop ? 0 : CGFloat(depth) * 10)
            .offset(isTop ? dragOffset : .zero)
            .rotationEffect(.degrees(isTop ? dragOffset.width / 18 : 0))
            .opacity(isTop ? cardOpacity : 1)
            .zIndex(isTop ? 10 : Double(9 - depth))
            .gesture(isTop ? swipeGesture : nil)
            .accessibilityHidden(!isTop)
            .accessibilityAction(named: "Next card") { swipeOn(toRight: true) }
    }

    @ViewBuilder
    private func content(for deckCard: DeckCard) -> some View {
        switch deckCard {
        case .mood:
            LevelCard(word: "mood", aura: 0, question: "How's your mood today?", titles: LevelScale.moodTitles, icon: { AnyView(MoodFace(level: $0)) }) { level in
                answer("Mood: \(LevelScale.moodTitles[level - 1].lowercased()).") { model.answerMood(level) }
            }

        case .energy:
            LevelCard(word: "energy", aura: 1, question: "How's your energy today?", titles: LevelScale.energyTitles, icon: { LogIcon.image(LogIcon.energy($0), size: 15) }) { level in
                answer("Energy: \(LevelScale.energyTitles[level - 1].lowercased()).") { model.answerEnergy(level) }
            }

        case .chips:
            ChipsCard(symptoms: model.chipOrder) { ids in
                answer(ids.isEmpty ? "Nothing else today." : "Noted.") { model.answerChips(ids) }
            }

        case .flow:
            FlowCard(
                onPick: { flow in answer("\(flow.title) flow.") { model.answerFlow(flow) } },
                onEnded: { answer("Period ended. Noted.") { model.answerPeriodEnded() } }
            )

        case let .followUp(day):
            HelpedCard(question: "Yesterday was rough. What helped?", options: Helper.options + [.nothingReally]) { helpers in
                answer("Thanks. Clutch is learning what helps you.") { model.answerFollowUp(helpers, about: day) }
            }
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = CGSize(width: value.translation.width, height: value.translation.height * 0.35)
            }
            .onEnded { value in
                if abs(value.translation.width) > 88 {
                    swipeOn(toRight: value.translation.width > 0)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { dragOffset = .zero }
                }
            }
    }

    // MARK: Answering

    /// A swipe moves on to the next card without answering this one.
    private func swipeOn(toRight: Bool) {
        withAnimation(.easeIn(duration: 0.35)) {
            dragOffset = CGSize(width: toRight ? 520 : -520, height: 40)
            cardOpacity = 0
        }
        onCommit("Skipped.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            model.skipCurrent()
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

    private func nothingToday() {
        answer("Seed planted.") { model.nothingToday() }
    }
}

// MARK: - Share

/// Sharing a bouquet: a 4:5 keepsake card (works as a post, a story and in
/// a message), then the places it can go, as dock-style tiles: Instagram
/// Story, Post and Message, then iMessage and Save.
struct PolaroidCard: View {
    let flowers: [PlantedFlower]
    var style: BouquetStyle = .plain
    /// When there is one, the card offers to put her name on the bouquet.
    let signature: UIImage?
    let caption: String
    let onClose: () -> Void

    @State private var includeName = true
    @State private var image: UIImage?
    @State private var note: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Share your bouquet")
                .font(.custom("PinyonScript-Regular", size: 36))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    BlushGradient()
                }
            }
            .frame(width: 236, height: 295)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.9), lineWidth: 1))
            .shadow(color: Color(hex: 0xB0587F).opacity(0.35), radius: 24, y: 14)

            VStack(spacing: 16) {
                if signature != nil {
                    Toggle("Include my name", isOn: $includeName)
                        .font(.custom("DMSans-Regular", size: 14))
                        .foregroundStyle(Color.ink)
                        .tint(Color(hex: 0xD68EA5))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("INSTAGRAM").detailsLabel()
                    HStack(spacing: 0) {
                        target("Story", "circle.dashed", palette: 1) { BouquetSharing.shareStory($0, text: shareText, saved: savedNote) }
                        target("Post", "square.grid.2x2", palette: 3) { BouquetSharing.shareToInstagramPost($0, text: shareText, saved: savedNote) }
                        target("Message", "paperplane", palette: 2) { BouquetSharing.shareToInstagramMessage($0) }
                    }
                }

                Rectangle().fill(Color.ink.opacity(0.1)).frame(height: 0.6)

                HStack(spacing: 0) {
                    target("iMessage", "message", palette: 0) { image in
                        if !BouquetSharing.shareToMessages(image, body: shareText) { BouquetSharing.presentShareSheet(image, text: shareText) }
                    }
                    target("Save", "arrow.down.to.line", palette: 4) { image in
                        BouquetSharing.saveToPhotos(image) { ok in
                            withAnimation { note = ok ? "Saved to Photos" : "Allow Photos access in Settings to save" }
                        }
                    }
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                }

                if let note {
                    Text(note)
                        .font(.custom("DMSans-Regular", size: 13))
                        .foregroundStyle(Color.ink.opacity(0.7))
                        .transition(.opacity)
                }
            }
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .background(.white.opacity(0.4), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.35)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
            )
            .shadow(color: Color(hex: 0xB0587F).opacity(0.18), radius: 18, y: 8)
        }
        .padding(.horizontal, 24)
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 0.6))
            }
            .padding(.trailing, 44)
            .padding(.top, -8)
            .accessibilityLabel("Close")
        }
        .onAppear(perform: render)
        .onChange(of: includeName) { render() }
    }

    private var shareText: String { "\(caption) \u{2014} my Clutch bouquet" }

    private func savedNote(_ ok: Bool) {
        withAnimation { note = ok ? "Saved to Photos, opening Instagram" : "Allow Photos access in Settings to share" }
    }

    private func target(_ title: String, _ symbol: String, palette: Int, action: @escaping (UIImage) -> Void) -> some View {
        Button {
            if let image { action(image) }
        } label: {
            VStack(spacing: 6) {
                AuraTile(palette: AuraTile.hints[palette], symbol: symbol)
                    .frame(width: 52, height: 52)
                Text(title)
                    .font(.custom("DMSans-Regular", size: 12))
                    .foregroundStyle(Color.ink)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title == "Message" ? "Send in an Instagram message" : title == "Story" ? "Share to Instagram story" : title == "Post" ? "Post on Instagram" : title)
    }

    private func render() {
        note = nil
        image = BouquetSnapshot.card(of: flowers, signature: includeName ? signature : nil, style: style, caption: caption)
    }
}

// MARK: - Dock items

/// Today's log, the cycle tracker, the free-products map, past bouquets,
/// and sharing today's bouquet.
private enum DockItem: String, CaseIterable, Identifiable {
    case garden, cycle, request, bouquets, share

    static let primary: [DockItem] = [.garden, .cycle, .request, .bouquets]

    var id: String { rawValue }

    /// Each tile names and pictures exactly where it goes.
    var title: String {
        switch self {
        case .garden: "Today"
        case .cycle: "Cycle"
        case .request: "Free pads"
        case .bouquets: "Bouquets"
        case .share: "Share"
        }
    }

    var symbol: String {
        switch self {
        case .garden: "sun.max"
        case .cycle: "drop"
        case .request: "map"
        case .bouquets: "leaf"
        case .share: "square.and.arrow.up"
        }
    }

    /// Core → rim colors, sampled from the reference strip's swatches.
    var palette: [Color] {
        switch self {
        case .garden: [Color(hex: 0xFFFBE8), Color(hex: 0xD4FDE0), Color(hex: 0xF5DFF9)]
        case .cycle: [Color(hex: 0xFFFFFF), Color(hex: 0xFFD0DD), Color(hex: 0xF3DDF6)]
        case .request: [Color(hex: 0xFFFFFF), Color(hex: 0xD3E5FF), Color(hex: 0xEADCF7)]
        case .bouquets: [Color(hex: 0xFFFBEA), Color(hex: 0xFFEAB0), Color(hex: 0xF5DDEB)]
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
struct GardenChip: View {
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

/// The dock tiles the walkthrough points at.
private struct DockWalkthroughTarget: ViewModifier {
    let item: DockItem

    func body(content: Content) -> some View {
        switch item {
        case .cycle: content.walkthroughTarget(.cycle)
        case .request: content.walkthroughTarget(.freePads)
        case .bouquets: content.walkthroughTarget(.bouquets)
        default: content
        }
    }
}
