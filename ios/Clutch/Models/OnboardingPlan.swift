import Foundation

/// The onboarding questions after the name scribble: three, tap-only, each
/// one setting up her cycle. Each needs an answer, and "Not sure" counts
/// as one. (Importing from Clue and what she wants help with are asked
/// later, inside the app.)
struct OnboardingPlan: Equatable {
    enum Step: String, CaseIterable {
        case age, lastPeriod, cycleLength
    }

    var ageRange: AgeRange?
    var lastPeriodStart: Date?
    var lastPeriodNotSure = false
    var cycleLength: Int?
    var cycleLengthNotSure = false

    func isAnswered(_ step: Step) -> Bool {
        switch step {
        case .age: ageRange != nil
        case .lastPeriod: lastPeriodStart != nil || lastPeriodNotSure
        case .cycleLength: cycleLength != nil || cycleLengthNotSure
        }
    }

    var steps: [Step] { Step.allCases }

    func step(after step: Step) -> Step? {
        let all = Step.allCases
        guard let i = all.firstIndex(of: step), i + 1 < all.count else { return nil }
        return all[i + 1]
    }

    func step(before step: Step) -> Step? {
        let all = Step.allCases
        guard let i = all.firstIndex(of: step), i > 0 else { return nil }
        return all[i - 1]
    }

    func apply(to profile: inout CycleProfile) {
        profile.ageRange = ageRange
        profile.lastPeriodStart = lastPeriodStart
        profile.cycleLength = cycleLength
    }
}

/// A rough phase from her last start and usual length, for the end of
/// onboarding. Plain words, no medical claims.
struct EstimatedPhase: Equatable {
    let cycleDay: Int
    let name: String
    let note: String

    init?(profile: CycleProfile, on date: Date, calendar: Calendar = .current) {
        guard let start = profile.lastPeriodStart else { return nil }
        let length = profile.effectiveCycleLength
        let elapsed = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: date)).day ?? 0
        guard elapsed >= 0 else { return nil }
        let day = elapsed % length + 1
        let ovulation = length - 14
        cycleDay = day
        switch day {
        case ...profile.effectivePeriodLength:
            name = "your period"
            note = "Go easy on yourself these days."
        case ..<(ovulation - 1):
            name = "rising days"
            note = "Energy often builds after a period."
        case (ovulation - 1)...(ovulation + 1):
            name = "mid-cycle"
            note = "Many people feel their strongest around now."
        default:
            name = "pre-period days"
            note = "Some people feel lower or more tired in this stretch."
        }
    }
}
