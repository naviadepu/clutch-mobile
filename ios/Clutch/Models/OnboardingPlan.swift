import Foundation

/// The onboarding questions after the name scribble: three to five, all
/// tap-only. Age and last period need an answer ("Not sure" counts); the
/// import can be skipped. Someone who already tracks gets the import step,
/// and once her history is in, the cycle questions are skipped because it
/// already answers them.
struct OnboardingPlan: Equatable {
    enum Step: String, CaseIterable {
        case age, tracker, importHistory, lastPeriod, cycleLength
    }

    enum Tracker: String, CaseIterable {
        case clue, other, none

        var title: String {
            switch self {
            case .clue: "Yes, Clue"
            case .other: "Yes, Apple Health or another app"
            case .none: "No, I'm new to this"
            }
        }
    }

    var ageRange: AgeRange?
    var tracker: Tracker?
    var imported = false
    var lastPeriodStart: Date?
    var lastPeriodNotSure = false
    var cycleLength: Int?
    var cycleLengthNotSure = false

    func applies(_ step: Step) -> Bool {
        switch step {
        case .age, .tracker: true
        case .importHistory: tracker != nil && tracker != Tracker.none
        case .lastPeriod, .cycleLength: !imported
        }
    }

    func isAnswered(_ step: Step) -> Bool {
        switch step {
        case .age: ageRange != nil
        case .tracker: tracker != nil
        case .importHistory: true
        case .lastPeriod: lastPeriodStart != nil || lastPeriodNotSure
        case .cycleLength: cycleLength != nil || cycleLengthNotSure
        }
    }

    var steps: [Step] { Step.allCases.filter(applies) }

    func step(after step: Step) -> Step? {
        let all = Step.allCases
        guard let i = all.firstIndex(of: step) else { return nil }
        return all[(i + 1)...].first(where: applies)
    }

    func step(before step: Step) -> Step? {
        let all = Step.allCases
        guard let i = all.firstIndex(of: step) else { return nil }
        return all[..<i].last(where: applies)
    }

    /// Imported history already set her last period and cycle length.
    func apply(to profile: inout CycleProfile) {
        profile.ageRange = ageRange
        guard !imported else { return }
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
