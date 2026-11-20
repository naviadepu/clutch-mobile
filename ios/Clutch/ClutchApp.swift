import SwiftUI
import UIKit

@main
struct ClutchApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var router = AppRouter.shared

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                #if DEBUG
                if let route = DebugLaunch.openRoute {
                    FeatureScreen(route: route)
                } else if DebugLaunch.mascotGallery {
                    DebugMascotGallery()
                } else if DebugLaunch.requestScreen {
                    RequestView(locations: DebugLaunch.sampleSpots ? ProductLocation.samples : ProductLocationStore.all)
                } else if DebugLaunch.cardGallery {
                    DebugCardGallery()
                } else if DebugLaunch.details {
                    DetailsView()
                } else if let step = DebugLaunch.question {
                    DebugQuestionScreen(step: step)
                } else if DebugLaunch.finishedGarden {
                    GardenView()
                } else {
                    LandingView()
                }
                #else
                LandingView()
                #endif
            }
            // A new session (after deleting her data) starts from the top.
            .id(router.session)
            .onOpenURL { AppRouter.shared.handle($0) }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                HealthSync.shared.syncIfConnected()
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseBootstrap.configure()
        #if DEBUG
        _ = DebugLaunch.demoHistory
        #endif
        WidgetBridge.refresh()
        return true
    }
}

#if DEBUG
/// Launch with `-finishedGarden` to open straight onto the Garden with
/// today's deck already answered — for checking the bouquet screen without
/// going through onboarding. Add `-showShare` to open the share card too.
enum DebugLaunch {
    static let showShare = ProcessInfo.processInfo.arguments.contains("-showShare")
    /// `-walkthrough` shows the cloud's home-screen tour again.
    static let walkthrough = ProcessInfo.processInfo.arguments.contains("-walkthrough")
    /// `-walkthrough -walkthroughStep 3` opens that tip first.
    static let walkthroughStep: Int = ProcessInfo.processInfo.arguments
        .firstIndex(of: "-walkthroughStep")
        .flatMap { i in ProcessInfo.processInfo.arguments.dropFirst(i + 1).first.flatMap { Int($0) } } ?? 0

    /// `-requestScreen` opens the Request screen on its own; add
    /// `-sampleSpots` to fill it with stand-in locations.
    static let requestScreen = ProcessInfo.processInfo.arguments.contains("-requestScreen")
    static let sampleSpots = ProcessInfo.processInfo.arguments.contains("-sampleSpots")

    /// `-cardGallery` shows every kind of deck card, for checking layout.
    static let cardGallery = ProcessInfo.processInfo.arguments.contains("-cardGallery")

    /// `-mascotGallery` shows the widget cloud's scenes at widget sizes;
    /// `-galleryPage N` picks which four.
    static let mascotGallery = ProcessInfo.processInfo.arguments.contains("-mascotGallery")

    /// `-open tracker` (or cloud, hard-time, cravings, wind-down) opens
    /// that screen on its own.
    static let openRoute: AppRouter.Route? = ProcessInfo.processInfo.arguments
        .firstIndex(of: "-open")
        .flatMap { AppRouter.Route(rawValue: ProcessInfo.processInfo.arguments[$0 + 1]) }

    /// `-details` opens "See full details" on its own. Add `-sampleHistory`
    /// to first replace every saved log with four logged cycles of sample
    /// data (pre-period lows), for checking the full version of the page.
    static let details: Bool = {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-sampleHistory") { DebugSampleHistory.install() }
        return arguments.contains("-details")
    }()

    /// `-question3` opens that onboarding question on its own.
    static let question: Int? = ProcessInfo.processInfo.arguments
        .first { $0.hasPrefix("-question") }
        .flatMap { Int($0.dropFirst("-question".count)) }

    /// `-demoHistory` (for recording the demo video) fills in four past
    /// cycles of logs ending yesterday but leaves onboarding and today's
    /// cards to do, so the walkthrough starts fresh and ends on a full
    /// details page.
    static let demoHistory: Bool = {
        guard ProcessInfo.processInfo.arguments.contains("-demoHistory") else { return false }
        DebugSampleHistory.install(includingToday: false)
        return true
    }()

    static let finishedGarden: Bool = {
        guard ProcessInfo.processInfo.arguments.contains("-finishedGarden") else { return false }
        var log = DayLogStore.loadOrCreate(for: Date())
        guard !log.completed else { return true }
        log.flow = .medium
        log.mood = 2
        log.energy = 3
        log.symptoms = ["low", "cramps", "bloating"]
        log.skipped = Symptom.catalog.map(\.id).filter { !log.symptoms.contains($0) }
        log.planted = 6
        log.completed = true
        DayLogStore.save(log)
        return true
    }()
}
#endif

#if DEBUG
/// One onboarding question, opened directly by `-questionN`.
struct DebugQuestionScreen: View {
    let step: Int

    var body: some View {
        if step == 1 {
            NameEntryView()
        } else {
            let steps = OnboardingPlan.Step.allCases
            OnboardingFlow(signature: nil, startAt: steps[min(max(step - 2, 0), steps.count - 1)], ready: step - 2 >= steps.count)
        }
    }
}
#endif

#if DEBUG
/// Every kind of deck card at its real size, two to a screen;
/// `-galleryPage N` picks which two.
struct DebugCardGallery: View {
    private let page = ProcessInfo.processInfo.arguments
        .firstIndex(of: "-galleryPage")
        .flatMap { Int(ProcessInfo.processInfo.arguments[$0 + 1]) } ?? 0

    private var cards: [AnyView] {
        [
            AnyView(LevelCard(word: "mood", aura: 0, question: "How's your mood today?", titles: LevelScale.moodTitles, icon: { AnyView(MoodFace(level: $0)) }) { _ in }),
            AnyView(LevelCard(word: "energy", aura: 1, question: "How's your energy today?", titles: LevelScale.energyTitles, icon: { LogIcon.image(LogIcon.energy($0), size: 15) }) { _ in }),
            AnyView(ChipsCard(symptoms: Symptom.catalog) { _ in }),
            AnyView(FlowCard(onPick: { _ in }, onEnded: {})),
            AnyView(HelpedCard(question: "Yesterday was rough. What helped?", options: Helper.options + [.nothingReally]) { _ in }),
        ]
    }

    var body: some View {
        let all = cards
        VStack(spacing: 24) {
            ForEach(Array(all.indices.dropFirst(page * 2).prefix(2)), id: \.self) { i in
                all[i].frame(height: 300)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AuraBackground())
    }
}

/// Four logged 28-day cycles ending today: low and anxious the four days
/// before each period, cramps on the first two days, a heating pad after.
enum DebugSampleHistory {
    static func install(includingToday: Bool = true) {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("garden.log.") {
            defaults.removeObject(forKey: key)
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let first = calendar.date(byAdding: .day, value: -(28 * 4 + 25), to: today)!
        // Without today, also leave a missed day ten days back, so the
        // streak reads like a real person's rather than every day since.
        let skipped: Set<Int> = includingToday ? [] : [28 * 4 + 15]
        for i in 0...(28 * 4 + 25) where (includingToday || i < 28 * 4 + 25) && !skipped.contains(i) {
            let date = calendar.date(byAdding: .day, value: i, to: first)!
            let cycleDay = i % 28 + 1
            var log = DayLog(date: date, seed: i * 7919)
            log.flow = cycleDay <= 5 ? .medium : .noFlow
            log.mood = 4
            log.energy = (8...14).contains(cycleDay) ? 5 : 3
            if cycleDay >= 25 || cycleDay == 1 {
                log.symptoms = ["anxious", "low"]
                log.mood = 2
            }
            if cycleDay <= 2 { log.symptoms.append("cramps") }
            if cycleDay == 3 || cycleDay == 26 { log.helpedNextDay = [Helper.heatingPad.rawValue, Helper.rest.rawValue] }
            log.answeredCards = ["mood", "energy", "chips"]
            log.planted = 3
            log.completed = true
            DayLogStore.save(log)
        }
        var profile = CycleProfile.load() ?? CycleProfile()
        profile.lastPeriodStart = calendar.date(byAdding: .day, value: 28 * 4, to: first)
        profile.onboardingComplete = includingToday
        profile.save()
    }
}
#endif

#if DEBUG
/// The cloud's scenes as small and medium widgets, four to a screen.
struct DebugMascotGallery: View {
    private let page = ProcessInfo.processInfo.arguments
        .firstIndex(of: "-galleryPage")
        .flatMap { Int(ProcessInfo.processInfo.arguments[$0 + 1]) } ?? 0

    var body: some View {
        let scenes = Array(MascotScene.allCases.dropFirst(page * 4).prefix(4))
        VStack(spacing: 14) {
            ForEach(scenes) { scene in
                HStack(spacing: 14) {
                    MascotSceneView(scene: scene, hasFlower: scene == .walk)
                        .frame(width: 158, height: 158)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scene.rawValue).font(.caption.bold())
                        Text(scene.line).font(.caption)
                    }
                    Spacer()
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cream)
    }
}
#endif
