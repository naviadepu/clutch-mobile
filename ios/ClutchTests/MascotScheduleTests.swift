import XCTest
@testable import Clutch

final class MascotScheduleTests: XCTestCase {
    private let calendar = Calendar.current

    private func at(_ hour: Int, daysFromNow: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: daysFromNow, to: calendar.startOfDay(for: .now))!
        return calendar.date(bySettingHour: hour, minute: 30, second: 0, of: day)!
    }

    private func snapshot(_ kind: CycleDayState.Kind, cycleDay: Int? = 10, until: Int? = 18) -> CycleSnapshot {
        var snapshot = CycleSnapshot()
        snapshot.days[CycleSnapshot.dayKey(for: .now)] = CycleDayState(kind: kind, cycleDay: cycleDay, daysUntilPeriod: until)
        return snapshot
    }

    func testOrdinaryDayFollowsTheClock() {
        let s = snapshot(.normal)
        XCTAssertEqual(MascotMoment.make(at: at(7), snapshot: s).scene, .breakfast)
        XCTAssertEqual(MascotMoment.make(at: at(10), snapshot: s).scene, .walk)
        XCTAssertEqual(MascotMoment.make(at: at(18), snapshot: s).scene, .fetch)
        XCTAssertEqual(MascotMoment.make(at: at(22), snapshot: s).scene, .journal)
        XCTAssertEqual(MascotMoment.make(at: at(2), snapshot: s).scene, .sleep)
    }

    func testPeriodDaysAreCozyButNightStaysTheSame() {
        let s = snapshot(.period, cycleDay: 2, until: nil)
        XCTAssertEqual(MascotMoment.make(at: at(7), snapshot: s).scene, .cozyTea)
        XCTAssertEqual(MascotMoment.make(at: at(13), snapshot: s).scene, .hotWaterNap)
        XCTAssertEqual(MascotMoment.make(at: at(22), snapshot: s).scene, .journal)
        XCTAssertTrue(MascotMoment.make(at: at(13), snapshot: s).line.hasPrefix("Day 2."))
    }

    func testDayBeforePeriodPacksPads() {
        let moment = MascotMoment.make(at: at(10), snapshot: snapshot(.beforePeriod, cycleDay: 27, until: 1))
        XCTAssertEqual(moment.scene, .packing)
        XCTAssertEqual(moment.line, "Period likely tomorrow. Pads packed.")
        XCTAssertEqual(moment.caption, "Day 27 \u{b7} period tomorrow")
    }

    func testHardDayDrizzles() {
        XCTAssertEqual(MascotMoment.make(at: at(15), snapshot: snapshot(.hard)).scene, .drizzle)
    }

    func testUnknownDayIsOrdinary() {
        XCTAssertEqual(MascotMoment.make(at: at(10), snapshot: CycleSnapshot()).scene, .walk)
    }

    func testTimelineChangesAreAllInTheFuture() {
        let now = Date.now
        let times = MascotMoment.changeTimes(from: now)
        XCTAssertFalse(times.isEmpty)
        XCTAssertTrue(times.allSatisfy { $0 > now })
    }

    func testBridgeMarksPeriodFromOnboardingStart() {
        var profile = CycleProfile()
        profile.lastPeriodStart = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: .now))
        profile.cycleLength = 28
        let snapshot = WidgetBridge.snapshot(logs: [], profile: profile, now: .now)
        let today = snapshot.state(on: .now)
        XCTAssertEqual(today.kind, .period)
        XCTAssertEqual(today.cycleDay, 2)
        XCTAssertEqual(today.daysUntilPeriod, 27)
    }
}
