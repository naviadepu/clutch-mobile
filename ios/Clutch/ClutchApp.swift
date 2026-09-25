import SwiftUI
import UIKit

@main
struct ClutchApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                #if DEBUG
                if DebugLaunch.requestScreen {
                    RequestView(locations: DebugLaunch.sampleSpots ? ProductLocation.samples : ProductLocationStore.all)
                } else if DebugLaunch.cardGallery {
                    DebugCardGallery()
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
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseBootstrap.configure()
        return true
    }
}

#if DEBUG
/// Launch with `-finishedGarden` to open straight onto the Garden with
/// today's deck already answered — for checking the bouquet screen without
/// going through onboarding. Add `-showShare` to open the share card too.
enum DebugLaunch {
    static let showShare = ProcessInfo.processInfo.arguments.contains("-showShare")

    /// `-requestScreen` opens the Request screen on its own; add
    /// `-sampleSpots` to fill it with stand-in locations.
    static let requestScreen = ProcessInfo.processInfo.arguments.contains("-requestScreen")
    static let sampleSpots = ProcessInfo.processInfo.arguments.contains("-sampleSpots")

    /// `-cardGallery` shows every kind of deck card, for checking layout.
    static let cardGallery = ProcessInfo.processInfo.arguments.contains("-cardGallery")

    /// `-question3` opens that onboarding question on its own.
    static let question: Int? = ProcessInfo.processInfo.arguments
        .first { $0.hasPrefix("-question") }
        .flatMap { Int($0.dropFirst("-question".count)) }

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

    @State private var profile = CycleProfile()

    var body: some View {
        switch step {
        case 1: NameEntryView()
        case 3: LastPeriodView(signature: nil, profile: $profile)
        case 4: CycleLengthView(signature: nil, profile: $profile)
        case 5: OnboardingPayoffView(signature: nil, profile: $profile)
        default: AgeEntryView()
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
            AnyView(FlowCard { _ in }),
            AnyView(LevelCard(word: "mood", aura: 0, question: "How's your mood today?", titles: LevelScale.moodTitles) { _ in }),
            AnyView(CrosswordCard(symptom: Symptom.catalog[3])),
            AnyView(HelpedCard(question: "Today was a lot. What helped?", options: Helper.options) { _ in }),
            AnyView(HelpedCard(
                question: InsightCopy.followUpQuestion(symptomIDs: ["cramps"], daysAgo: 1, day: .now),
                options: Helper.options + [.nothingReally]
            ) { _ in }),
        ] + OneTimeQuestion.allCases.map { question in
            AnyView(OneTimeCard(question: question, onAnswer: { _ in }, onSkip: {}))
        }
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
#endif
