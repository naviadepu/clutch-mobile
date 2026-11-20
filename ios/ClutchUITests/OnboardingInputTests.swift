import XCTest

/// Real taps and drags on the screens where they used to be swallowed by
/// the "next" arrow's glass, plus the way from the finished bouquet to the
/// details page.
final class OnboardingInputTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ arguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    func testCalendarDateCanBeTapped() {
        let app = launch("-question3")
        let title = app.staticTexts["When did your last period start?"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))

        // Any day other than the selected one (today) in the month grid.
        let days = app.datePickers.firstMatch.buttons.matching(NSPredicate(format: "isEnabled == true"))
        let day = days.allElementsBoundByIndex.first { !$0.isSelected && $0.label.contains(",") }
        XCTAssertNotNil(day, "no other day to pick")
        day?.tap()

        // Still on the question — the tap picked a date rather than
        // skipping ahead — and the day is now the selected one.
        XCTAssertTrue(title.exists)
        XCTAssertTrue(day?.isSelected ?? false)
    }

    func testCycleLengthSliderDrags() {
        let app = launch("-question4")
        let title = app.staticTexts["How long is your cycle usually?"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["28"].exists)

        // Drag along the dot track, from the middle towards the right end.
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let track = app.staticTexts["20 – 45"]
        let trackY = track.frame.maxY + 50
        let from = start.withOffset(CGVector(dx: 0, dy: trackY - window.frame.midY))
        let to = from.withOffset(CGVector(dx: window.frame.width * 0.3, dy: 0))
        from.press(forDuration: 0.1, thenDragTo: to)

        XCTAssertTrue(title.exists)
        XCTAssertFalse(app.staticTexts["28"].exists, "the value didn't move off 28")
    }

    func testFinishedBouquetLeadsToDetails() {
        let app = launch("-finishedGarden")
        let details = app.buttons["See full details"]
        XCTAssertTrue(details.waitForExistence(timeout: 10))
        details.tap()
        XCTAssertTrue(app.staticTexts["your details"].waitForExistence(timeout: 5))
    }
}
