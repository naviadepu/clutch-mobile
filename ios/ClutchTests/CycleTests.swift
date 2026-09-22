import XCTest
@testable import Clutch

final class CycleTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ offset: Int, from base: Date = Date(timeIntervalSince1970: 1_790_000_000)) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: base)!)
    }

    func testDeckIsThePeriodCardThenTheFourMoodCheckIns() {
        XCTAssertEqual(
            Symptom.catalog.map(\.id),
            [Symptom.periodID, "low", "anxious", "moody", "irritable"]
        )
    }

    func testFirstBleedingDayBecomesTheStartWhenSheDidntRemember() {
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

    func testOldDayLogsWithoutFlowStillDecode() throws {
        let json = #"{"date": 0, "symptoms": ["cramps"], "skipped": [], "seed": 7}"#
        let log = try JSONDecoder().decode(DayLog.self, from: Data(json.utf8))
        XCTAssertNil(log.flow)
        XCTAssertEqual(log.symptoms, ["cramps"])
    }

    // MARK: - Bouquet collection

    func testDifferentDaysArrangeTheFlowersDifferently() {
        let orders = (0..<8).map { seed in
            BouquetGenerator.flowers(for: DayLog(date: day(0), symptoms: ["a", "b", "c", "d", "e"], seed: seed)).map(\.art)
        }
        XCTAssertGreaterThan(Set(orders).count, 1)
    }

    func testSoftPhotosOnlyEverSitInTheBackRow() {
        for seed in 0..<40 {
            let arts = BouquetGenerator.flowers(for: DayLog(date: day(0), symptoms: ["a", "b", "c", "d", "e"], seed: seed)).map(\.art)
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
        let log = DayLog(date: day(0), symptoms: ["period", "low", "anxious"], skipped: ["moody", "irritable"], seed: 42)
        let first = BouquetGenerator.flowers(for: log)
        let second = BouquetGenerator.flowers(for: log)
        XCTAssertEqual(first.count, 5)
        XCTAssertEqual(first.map(\.art), second.map(\.art))
        XCTAssertEqual(first.map(\.heightOffset), second.map(\.heightOffset))
        XCTAssertEqual(Set(first.map(\.art)).count, 5, "a bouquet shouldn't repeat a flower")
        XCTAssertTrue(first.allSatisfy { (1...BouquetGenerator.artCount).contains($0.art) })
        XCTAssertTrue(log.isComplete)
    }
}
