import CoreLocation
import XCTest
@testable import Clutch

final class ProductLocationTests: XCTestCase {
    /// The hackathon pins were dropped on purpose — conflicting
    /// coordinates, missing items, nothing verified.
    func testShippedListStartsEmpty() {
        XCTAssertTrue(ProductLocationStore.all.isEmpty)
    }

    func testEveryFieldDecodesFromJSON() throws {
        let json = """
        [
          {
            "id": "sparks-hall-2nd-floor",
            "name": "Sparks Hall",
            "floor": "2nd floor",
            "directions": "2nd floor, women's restroom by the elevators",
            "category": "campusRestroom",
            "address": "33 Gilmer St SE, Atlanta, GA 30303",
            "latitude": 33.7538,
            "longitude": -84.3855,
            "items": ["pads", "tampons"],
            "stockStatus": "low",
            "lastVerified": "2026-09-20",
            "lastReported": "2026-09-21",
            "refilledBy": "Student Government",
            "hours": "Mon–Fri, 7am–10pm",
            "notes": "Basket under the mirror."
          }
        ]
        """.data(using: .utf8)!

        let spot = try XCTUnwrap(ProductLocationStore.decoder.decode([ProductLocation].self, from: json).first)
        XCTAssertEqual(spot.id, "sparks-hall-2nd-floor")
        XCTAssertEqual(spot.floor, "2nd floor")
        XCTAssertEqual(spot.directions, "2nd floor, women's restroom by the elevators")
        XCTAssertEqual(spot.category, .campusRestroom)
        XCTAssertEqual(spot.items, [.pads, .tampons])
        XCTAssertEqual(spot.stockStatus, .low)
        XCTAssertEqual(spot.refilledBy, "Student Government")
        XCTAssertEqual(spot.hours, "Mon–Fri, 7am–10pm")
        XCTAssertNotNil(spot.lastVerified)
        XCTAssertNotNil(spot.lastReported)
        XCTAssertTrue(CLLocationCoordinate2DIsValid(spot.coordinate))
    }

    /// A hand-written entry can leave out everything optional.
    func testMinimalEntryDecodesWithSensibleDefaults() throws {
        let json = """
        [{"id": "x", "name": "Langdale Hall", "directions": "3rd floor restroom",
          "category": "campusRestroom", "latitude": 33.7533, "longitude": -84.3863}]
        """.data(using: .utf8)!

        let spot = try XCTUnwrap(ProductLocationStore.decoder.decode([ProductLocation].self, from: json).first)
        XCTAssertEqual(spot.stockStatus, .unknown, "unsaid means unknown, never 'stocked'")
        XCTAssertTrue(spot.items.isEmpty)
        XCTAssertNil(spot.lastVerified)
        XCTAssertNil(spot.floor)
    }

    func testStockingMatchesTheCatchAllForPeriodProductsOnly() {
        let spots = ProductLocation.samples
        XCTAssertTrue(ProductLocationStore.stocking(.pads, in: spots).map(\.id).contains("sample-student-center-west"),
                      "'period products' should cover pads")
        XCTAssertFalse(ProductLocationStore.stocking(.painRelief, in: spots).map(\.id).contains("sample-student-center-west"),
                       "'period products' shouldn't imply pain relief")
        XCTAssertEqual(ProductLocationStore.stocking(.painRelief, in: spots).map(\.id), ["sample-rec-center"])
    }

    func testSortedByDistancePutsTheNearestFirst() {
        let atSparks = CLLocation(latitude: 33.7538, longitude: -84.3855)
        let order = ProductLocationStore.sortedByDistance(from: atSparks, in: ProductLocation.samples).map(\.id)
        XCTAssertEqual(order.first, "sample-sparks-hall")
        XCTAssertEqual(order.last, "sample-rec-center")
    }
}

final class SpotReportsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "spots.emptyReports")
        UserDefaults.standard.removeObject(forKey: "spots.suggestions")
    }

    func testReportingEmptyIsKeptOnTheDevice() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        SpotReports.reportEmpty("sparks-hall-2nd-floor", at: now)

        XCTAssertEqual(SpotReports.emptyReports().count, 1)
        XCTAssertEqual(SpotReports.lastEmptyReport(for: "sparks-hall-2nd-floor"), now)
        XCTAssertNil(SpotReports.lastEmptyReport(for: "somewhere-else"))
    }

    func testLastEmptyReportIsTheMostRecentOne() {
        let earlier = Date(timeIntervalSince1970: 1_790_000_000)
        let later = earlier.addingTimeInterval(3600)
        SpotReports.reportEmpty("x", at: earlier)
        SpotReports.reportEmpty("x", at: later)

        XCTAssertEqual(SpotReports.lastEmptyReport(for: "x"), later)
    }

    func testSuggestionsAreKept() {
        SpotReports.suggest(name: "Langdale Hall", directions: "3rd floor, by the stairs")

        XCTAssertEqual(SpotReports.suggestions().count, 1)
        XCTAssertEqual(SpotReports.suggestions().first?.name, "Langdale Hall")
    }
}
