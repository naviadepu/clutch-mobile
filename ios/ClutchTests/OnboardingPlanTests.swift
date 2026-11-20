import XCTest
@testable import Clutch

final class OnboardingPlanTests: XCTestCase {
    func testNewToTrackingGetsFourQuestions() {
        var plan = OnboardingPlan()
        plan.tracker = OnboardingPlan.Tracker.none
        XCTAssertEqual(plan.steps, [.age, .tracker, .lastPeriod, .cycleLength])
    }

    func testTrackerGetsImportThenSkipsCycleQuestionsOnceImported() {
        var plan = OnboardingPlan()
        plan.tracker = .clue
        XCTAssertEqual(plan.steps, [.age, .tracker, .importHistory, .lastPeriod, .cycleLength])
        XCTAssertTrue(plan.isAnswered(.importHistory), "the import can be skipped")
        plan.imported = true
        XCTAssertEqual(plan.steps, [.age, .tracker, .importHistory])
        XCTAssertNil(plan.step(after: .importHistory))
    }

    func testImportedAnswersDontOverwriteHistory() {
        var plan = OnboardingPlan()
        plan.imported = true
        plan.lastPeriodStart = nil
        var profile = CycleProfile()
        profile.cycleLength = 31
        plan.apply(to: &profile)
        XCTAssertEqual(profile.cycleLength, 31)
    }

    func testEveryQuestionNeedsAnAnswer() {
        var plan = OnboardingPlan()
        XCTAssertFalse(plan.isAnswered(.age))
        XCTAssertFalse(plan.isAnswered(.lastPeriod))
        XCTAssertFalse(plan.isAnswered(.cycleLength))
        plan.lastPeriodNotSure = true
        plan.cycleLengthNotSure = true
        XCTAssertTrue(plan.isAnswered(.lastPeriod), "Not sure is an answer")
        XCTAssertTrue(plan.isAnswered(.cycleLength))
    }

    func testAnswersLandInProfile() {
        var plan = OnboardingPlan()
        plan.ageRange = .eighteenToTwentyFour
        plan.cycleLength = 29
        var profile = CycleProfile()
        plan.apply(to: &profile)
        XCTAssertEqual(profile.ageRange, .eighteenToTwentyFour)
        XCTAssertEqual(profile.cycleLength, 29)
        XCTAssertNil(profile.lastPeriodStart)
    }

    func testPainGoalLeadsTheDeckWithSymptoms() {
        var profile = CycleProfile()
        profile.goals = [.pain]
        let planner = DeckPlanner(engine: CycleEngine(logs: [], profile: profile))
        XCTAssertEqual(planner.deck(on: .now).first, .chips)
        XCTAssertEqual(planner.symptomOrder(on: .now).first?.id, "cramps")
    }
}
