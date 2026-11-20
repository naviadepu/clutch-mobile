import XCTest
@testable import Clutch

final class SharedSpotReportsTests: XCTestCase {
    private let now = Date.now
    private func report(_ kind: SharedSpotReports.Report.Kind, _ uid: String, minutesAgo: Double, spot: String = "a") -> SharedSpotReports.Report {
        .init(locationID: spot, kind: kind, uid: uid, at: now.addingTimeInterval(-minutesAgo * 60))
    }

    func testOnePersonOnlyMarksLow() {
        let result = SharedSpotReports.aggregate([report(.empty, "u1", minutesAgo: 5)])
        XCTAssertEqual(result["a"]?.status, .low)
    }

    func testTwoPeopleMarkEmpty() {
        let result = SharedSpotReports.aggregate([report(.empty, "u1", minutesAgo: 9), report(.empty, "u2", minutesAgo: 5)])
        XCTAssertEqual(result["a"]?.status, .empty)
    }

    func testSamePersonTwiceIsStillOne() {
        let result = SharedSpotReports.aggregate([report(.empty, "u1", minutesAgo: 9), report(.empty, "u1", minutesAgo: 5)])
        XCTAssertEqual(result["a"]?.status, .low)
    }

    func testStockedResetsEarlierEmpties() {
        let result = SharedSpotReports.aggregate([
            report(.empty, "u1", minutesAgo: 30), report(.empty, "u2", minutesAgo: 20), report(.stocked, "u3", minutesAgo: 10),
        ])
        XCTAssertEqual(result["a"]?.status, .stocked)
    }
}

final class GentleNudgesTests: XCTestCase {
    func testHeadsUpFindsFirstDayOfNextHardStretch() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var snapshot = CycleSnapshot()
        for offset in [4, 5, 6] {
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            snapshot.days[CycleSnapshot.dayKey(for: day)] = CycleDayState(kind: .hard)
        }
        let first = GentleNudges.nextHardStretch(in: snapshot, from: .now)
        XCTAssertEqual(first, calendar.date(byAdding: .day, value: 4, to: today))
    }

    func testNoHardDaysNoHeadsUp() {
        XCTAssertNil(GentleNudges.nextHardStretch(in: CycleSnapshot(), from: .now))
    }
}

final class RouterTests: XCTestCase {
    func testWidgetLinksOpenTheirScreens() {
        let router = AppRouter()
        router.handle(URL(string: "clutch://journal")!)
        XCTAssertEqual(router.pending, .journal)
        router.handle(URL(string: "clutch://wind-down")!)
        XCTAssertEqual(router.pending, .windDown)
        // Widgets placed before hard-time was retired.
        router.handle(URL(string: "clutch://hard-time")!)
        XCTAssertEqual(router.pending, .windDown)
    }

    func testUnknownLinksAreIgnored() {
        let router = AppRouter()
        router.handle(URL(string: "clutch://nowhere")!)
        XCTAssertNil(router.pending)
        router.handle(URL(string: "https://example.com/hard-time")!)
        XCTAssertNil(router.pending)
    }

    func testEveryWidgetRouteIsOneTheAppKnows() {
        for scene in MascotScene.allCases {
            let moment = MascotMoment(scene: scene, line: "", caption: nil, hasFlower: false)
            XCTAssertNotNil(AppRouter.Route(rawValue: moment.route), "\(scene) links to \(moment.route)")
        }
    }

    func testLowMoodMakesTheCloudGentle() {
        var snapshot = CycleSnapshot()
        snapshot.moods[CycleSnapshot.dayKey(for: .now)] = 1
        let noon = Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: .now)!
        let moment = MascotMoment.make(at: noon, snapshot: snapshot)
        XCTAssertEqual(moment.scene, .drizzle)
        XCTAssertFalse(moment.sparkle)
    }

    func testGreatMoodSparkles() {
        var snapshot = CycleSnapshot()
        snapshot.moods[CycleSnapshot.dayKey(for: .now)] = 5
        let noon = Calendar.current.date(bySettingHour: 12, minute: 30, second: 0, of: .now)!
        XCTAssertTrue(MascotMoment.make(at: noon, snapshot: snapshot).sparkle)
    }
}
