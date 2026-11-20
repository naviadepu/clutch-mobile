import HealthKit
import XCTest
@testable import Clutch

final class ClueImportTests: XCTestCase {
    func testDayListFormat() throws {
        let json = """
        {"data": [
          {"day": "2023-01-02T00:00:00Z", "period": "heavy", "pain": ["cramps", "headache"]},
          {"day": "2023-01-03T00:00:00Z", "period": "medium", "energy": ["low"], "craving": ["sweet"]},
          {"day": "2023-01-20T00:00:00Z", "emotion": ["sad"], "digestion": ["bloated"]}
        ]}
        """
        let days = try ClueImport.parse(Data(json.utf8))
        XCTAssertEqual(days.count, 3)
        XCTAssertEqual(days[0].flow, .heavy)
        XCTAssertEqual(days[0].symptoms, ["cramps", "headache"])
        XCTAssertEqual(days[1].flow, .medium)
        XCTAssertEqual(days[1].symptoms, ["cravings"], "low energy isn't feeling low")
        XCTAssertNil(days[2].flow)
        XCTAssertEqual(days[2].symptoms, ["low", "bloating"])
    }

    func testMeasurementListFormat() throws {
        let json = """
        [
          {"date": "2024-03-01", "type": "period", "value": {"option": "light"}},
          {"date": "2024-03-01", "type": "pain", "value": [{"option": "period_cramps"}]},
          {"date": "2024-03-02", "type": "period", "value": {"option": "very_heavy"}},
          {"date": "2024-03-05", "type": "spotting", "value": {"option": "spotting"}}
        ]
        """
        let days = try ClueImport.parse(Data(json.utf8))
        XCTAssertEqual(days.map(\.flow), [.light, .heavy, nil])
        XCTAssertTrue(days[0].symptoms.contains("cramps"))
    }

    func testCSV() throws {
        let csv = "Date,Period,Notes\n2022-05-01,Medium,\n2022-05-02,Light,headache\n2022-05-10,,\n"
        let days = try ClueImport.parse(Data(csv.utf8))
        XCTAssertEqual(days.count, 3)
        XCTAssertEqual(days[0].flow, .medium)
        XCTAssertEqual(days[1].symptoms, ["headache"])
    }

    func testFileWithoutPeriodsIsRejected() {
        let json = #"[{"day": "2023-01-02", "pain": ["headache"]}]"#
        XCTAssertThrowsError(try ClueImport.parse(Data(json.utf8))) { error in
            XCTAssertEqual(error as? ClueImport.Failure, .noPeriodData)
        }
    }

    func testHealthFlowValues() {
        XCTAssertEqual(HealthSync.flow(fromHealthValue: HKCategoryValueMenstrualFlow.light.rawValue), .light)
        XCTAssertEqual(HealthSync.flow(fromHealthValue: HKCategoryValueMenstrualFlow.unspecified.rawValue), .medium)
        XCTAssertEqual(HealthSync.flow(fromHealthValue: HKCategoryValueMenstrualFlow.heavy.rawValue), .heavy)
        XCTAssertEqual(HealthSync.flow(fromHealthValue: HKCategoryValueMenstrualFlow.none.rawValue), .noFlow)
    }
}

/// Uses days in 2001 so it can't touch anything real, and cleans up.
final class PeriodImportTests: XCTestCase {
    private let calendar = Calendar.current
    private func day(_ d: Int) -> Date { calendar.date(from: DateComponents(year: 2001, month: 1, day: d))! }

    override func tearDown() {
        for d in 1...31 { DayLogStore.remove(for: day(d)) }
        super.tearDown()
    }

    func testMergeFillsGapsButKeepsHerAnswers() {
        var hers = DayLog(date: day(2), seed: 1)
        hers.flow = .light
        hers.answeredCards = ["flow"]
        hers.completed = true
        DayLogStore.save(hers)

        PeriodImport.merge([
            ImportedDay(date: day(1), flow: .heavy, symptoms: ["cramps"]),
            ImportedDay(date: day(2), flow: .heavy, symptoms: ["bloating"]),
        ], source: .clue)

        XCTAssertEqual(DayLogStore.load(for: day(1))?.flow, .heavy)
        XCTAssertEqual(DayLogStore.load(for: day(1))?.importedFrom, "clue")
        XCTAssertFalse(DayLogStore.load(for: day(1))!.completed, "imported days don't grow bouquets")
        XCTAssertEqual(DayLogStore.load(for: day(2))?.flow, .light, "her own flow wins")
        XCTAssertEqual(DayLogStore.load(for: day(2))?.symptoms, ["bloating"])
    }

    func testUndoRemovesOnlyImportedDays() {
        var hers = DayLog(date: day(3), seed: 1)
        hers.completed = true
        DayLogStore.save(hers)
        PeriodImport.merge([ImportedDay(date: day(4), flow: .medium)], source: .clue)
        XCTAssertNotNil(DayLogStore.load(for: day(4)))

        PeriodImport.undo(.clue)
        XCTAssertNil(DayLogStore.load(for: day(4)))
        XCTAssertNotNil(DayLogStore.load(for: day(3)))
    }

    func testImportedHistoryDrivesCycleLengths() {
        let days = [1, 2, 3, 29, 30, 31].map { ImportedDay(date: day($0), flow: .medium) }
        PeriodImport.merge(days, source: .clue)
        let logs = DayLogStore.allLogs().filter { $0.date < day(31).addingTimeInterval(86_400) && $0.date >= day(1) }
        let engine = CycleEngine(logs: logs, profile: CycleProfile())
        XCTAssertEqual(engine.completedCycles.map(\.length), [28])
    }
}
