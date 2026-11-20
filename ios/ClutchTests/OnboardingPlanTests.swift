import XCTest
@testable import Clutch

final class OnboardingPlanTests: XCTestCase {
    func testThreeQuestions() {
        XCTAssertEqual(OnboardingPlan().steps, [.age, .lastPeriod, .cycleLength])
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
