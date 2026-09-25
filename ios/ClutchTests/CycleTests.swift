import XCTest
@testable import Clutch

final class CycleTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ offset: Int, from base: Date = Date(timeIntervalSince1970: 1_790_000_000)) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: base)!)
    }

    private func log(planted: Int, seed: Int) -> DayLog {
        var log = DayLog(date: day(0), seed: seed)
        log.planted = planted
        return log
    }

    func testSymptomSwipesAreTheEightNewOnes() {
        XCTAssertEqual(
            Symptom.catalog.map(\.id),
            ["anxious", "low", "irritable", "cramps", "bloating", "headache", "poor-sleep", "cravings"]
        )
    }

    func testFirstBleedingDayBecomesTheStartWhenSheWasntSure() {
        let today = day(0)
        let start = CycleProfile.newPeriodStart(
            loggedOn: today, yesterdayHadPeriod: false, currentStart: nil, periodLength: 5, calendar: calendar
        )
        XCTAssertEqual(start, today)
    }

    func testNewPeriodReplacesAnOldEstimate() {
        let today = day(0)
        let start = CycleProfile.newPeriodStart(
            loggedOn: today, yesterdayHadPeriod: false, currentStart: day(-27), periodLength: 5, calendar: calendar
        )
        XCTAssertEqual(start, today)
    }

    func testContinuingPeriodKeepsTheExistingStart() {
        XCTAssertNil(CycleProfile.newPeriodStart(
            loggedOn: day(0), yesterdayHadPeriod: true, currentStart: day(-2), periodLength: 5, calendar: calendar
        ))
        // No log yesterday, but still within the period she already reported.
        XCTAssertNil(CycleProfile.newPeriodStart(
            loggedOn: day(0), yesterdayHadPeriod: false, currentStart: day(-3), periodLength: 5, calendar: calendar
        ))
    }

    func testPreferNotToSayIsReadAsNoBirthControl() {
        XCTAssertEqual(BirthControl.preferNotToSay.effective, BirthControl.none)
        XCTAssertEqual(BirthControl.hormonalIUD.effective, .hormonalIUD)
    }

    // MARK: - Migration

    func testOldDayLogsWithoutFlowStillDecode() throws {
        let json = #"{"date": 0, "symptoms": ["cramps"], "skipped": [], "seed": 7}"#
        let log = try JSONDecoder().decode(DayLog.self, from: Data(json.utf8))
        XCTAssertNil(log.flow)
        XCTAssertEqual(log.symptoms, ["cramps"])
        XCTAssertEqual(log.legacySymptoms, ["cramps"])
    }

    /// A finished day from the five-card deck.
    private let versionOneLog = #"""
    {"date": 800000000, "seed": 42, "flow": "heavy",
     "symptoms": ["period", "low", "moody"], "skipped": ["anxious", "irritable"]}
    """#

    func testVersionOneLogMigratesToTheNewFields() throws {
        let log = try JSONDecoder().decode(DayLog.self, from: Data(versionOneLog.utf8))
        XCTAssertEqual(log.flow, .heavy)
        XCTAssertEqual(log.symptoms, ["low"], "feeling low → low")
        XCTAssertEqual(log.skipped, ["anxious", "irritable"], "anxiety → anxious")
        XCTAssertEqual(log.moodSwings, true, "mood swings kept as it was")
        XCTAssertNil(log.mood, "a yes/no can't become a 1–5 mood")
        XCTAssertEqual(log.legacySymptoms, ["period", "low", "moody"])
        XCTAssertEqual(log.legacySkipped, ["anxious", "irritable"])
        XCTAssertTrue(log.completed)
        XCTAssertEqual(log.planted, 5)
        XCTAssertEqual(log.version, DayLog.currentVersion)
    }

    func testMigratedLogKeepsItsBouquetAndSurvivesASave() throws {
        let migrated = try JSONDecoder().decode(DayLog.self, from: Data(versionOneLog.utf8))
        var original = DayLog(date: migrated.date, seed: 42)
        original.planted = 5
        XCTAssertEqual(BouquetGenerator.flowers(for: migrated).map(\.art), BouquetGenerator.flowers(for: original).map(\.art))

        let resaved = try JSONDecoder().decode(DayLog.self, from: JSONEncoder().encode(migrated))
        XCTAssertEqual(resaved, migrated)
    }

    func testVersionOneProfileKeepsItsAnswersAndSkipsOnboarding() throws {
        let json = #"{"age": 14, "cycleLength": 30, "birthControl": "hormonalIUD", "lastPeriodStart": 800000000}"#
        let profile = try JSONDecoder().decode(CycleProfile.self, from: Data(json.utf8))
        XCTAssertTrue(profile.onboardingComplete)
        XCTAssertEqual(profile.age, 14)
        XCTAssertEqual(profile.ageRange, .fifteenToSeventeen)
        XCTAssertEqual(profile.cycleLength, 30)
        XCTAssertEqual(profile.birthControl, .hormonalIUD)
        XCTAssertEqual(profile.oneTimeCards[OneTimeQuestion.birthControl.id]?.answered, true)
        XCTAssertEqual(profile.oneTimeCards[OneTimeQuestion.periodLength.id]?.answered, true)
        XCTAssertNil(profile.oneTimeCards[OneTimeQuestion.goals.id])
    }

    func testAgeRangesCoverFifteenToSeventy() {
        XCTAssertEqual(AgeRange(age: 15), .fifteenToSeventeen)
        XCTAssertEqual(AgeRange(age: 24), .eighteenToTwentyFour)
        XCTAssertEqual(AgeRange(age: 25), .twentyFiveToThirtyFive)
        XCTAssertEqual(AgeRange(age: 70), .thirtySixToSeventy)
    }

    // MARK: - Bouquet collection

    func testDifferentDaysArrangeTheFlowersDifferently() {
        let orders = (0..<8).map { seed in BouquetGenerator.flowers(for: log(planted: 5, seed: seed)).map(\.art) }
        XCTAssertGreaterThan(Set(orders).count, 1)
    }

    func testSoftPhotosOnlyEverSitInTheBackRow() {
        for seed in 0..<40 {
            let arts = BouquetGenerator.flowers(for: log(planted: 5, seed: seed)).map(\.art)
            for (position, art) in arts.enumerated() where BouquetGenerator.softArts.contains(art) {
                XCTAssertTrue(BouquetGenerator.backPositions.contains(position), "seed \(seed): soft art \(art) at \(position)")
            }
        }
    }

    func testStreakCountsConsecutiveDaysEndingToday() {
        let today = day(0)
        XCTAssertEqual(BouquetCollection.streak(collectedDays: [day(0), day(-1), day(-2), day(-4)], today: today, calendar: calendar), 3)
    }

    func testStreakStillHoldsBeforeTodaysCardsAreDone() {
        XCTAssertEqual(BouquetCollection.streak(collectedDays: [day(-1), day(-2)], today: day(0), calendar: calendar), 2)
    }

    func testStreakBreaksAfterAMissedDay() {
        XCTAssertEqual(BouquetCollection.streak(collectedDays: [day(-2), day(-3)], today: day(0), calendar: calendar), 0)
        XCTAssertEqual(BouquetCollection.streak(collectedDays: [], today: day(0), calendar: calendar), 0)
    }

    func testSameLogAlwaysRegrowsTheSameBouquet() {
        let log = log(planted: 5, seed: 42)
        let first = BouquetGenerator.flowers(for: log)
        let second = BouquetGenerator.flowers(for: log)
        XCTAssertEqual(first.count, 5)
        XCTAssertEqual(first.map(\.art), second.map(\.art))
        XCTAssertEqual(first.map(\.heightOffset), second.map(\.heightOffset))
        XCTAssertEqual(Set(first.map(\.art)).count, 5, "a bouquet shouldn't repeat a flower")
        XCTAssertTrue(first.allSatisfy { (1...BouquetGenerator.artCount).contains($0.art) })
    }

    func testNothingTodayPlantsASeedAndStillCounts() {
        var log = DayLog(date: day(0), seed: 3)
        log.nothingToday = true
        log.completed = true
        XCTAssertTrue(BouquetGenerator.flowers(for: log).isEmpty)
        XCTAssertTrue(BouquetStyle(log: log).hasSeed)
        XCTAssertTrue(log.isLogged)
    }

    func testAnswersShapeTheBouquet() {
        var log = DayLog(date: day(0), seed: 3)
        log.flow = .heavy
        log.energy = 5
        log.symptoms = ["cramps", "bloating"]
        let style = BouquetStyle(log: log)
        XCTAssertEqual(style.colorDepth, 1)
        XCTAssertGreaterThan(style.stemBoost, 0)
        XCTAssertEqual(style.leaves, 2)
    }
}
