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

    /// `-question3` opens that onboarding question on its own.
    static let question: Int? = ProcessInfo.processInfo.arguments
        .first { $0.hasPrefix("-question") }
        .flatMap { Int($0.dropFirst("-question".count)) }

    static let finishedGarden: Bool = {
        guard ProcessInfo.processInfo.arguments.contains("-finishedGarden") else { return false }
        var log = DayLogStore.loadOrCreate(for: Date())
        let answered = Set(log.symptoms + log.skipped)
        log.symptoms += Symptom.catalog.map(\.id).filter { !answered.contains($0) }
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
        case 2: LastPeriodView(signature: nil, profile: $profile)
        case 3: CycleLengthView(signature: nil, profile: $profile)
        case 4: PeriodLengthView(signature: nil, profile: $profile)
        case 5: BirthControlView(signature: nil, profile: $profile)
        default: AgeEntryView()
        }
    }
}
#endif
