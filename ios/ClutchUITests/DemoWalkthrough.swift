import XCTest

/// The demo video's walkthrough: a fresh install from the landing screen,
/// through onboarding and today's cards, to the bouquet, sharing, details,
/// free period products and past bouquets. Paced for a viewer, not for
/// speed. `scripts/record-demo.sh` records the Simulator between the
/// marker files this writes; run on its own, it's just a long UI test.
final class DemoWalkthrough: XCTestCase {
    private let markerDirectory = ProcessInfo.processInfo.environment["DEMO_MARKER_DIR"] ?? "/tmp/clutch-demo"

    override func setUp() {
        continueAfterFailure = true
    }

    func testDemoWalkthrough() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demoHistory"]
        app.launch()
        mark("start")
        defer { mark("stop") }

        // Landing: the wordmark writes itself, then tap to continue.
        XCTAssertTrue(app.staticTexts["tap to continue"].waitForExistence(timeout: 15))
        pause(2)
        app.windows.firstMatch.tap()

        // Name: scribble it on the canvas.
        XCTAssertTrue(app.staticTexts["Your name"].waitForExistence(timeout: 5))
        pause(1)
        scribbleName(in: app.windows.firstMatch)
        pause(1.5)
        app.buttons["Next"].tap()

        // Age.
        XCTAssertTrue(app.staticTexts["How old are you?"].waitForExistence(timeout: 5))
        pause(2)
        app.buttons["Next"].tap()

        // Last period: pick the day the sample history's last period began.
        XCTAssertTrue(app.staticTexts["When did your last period start?"].waitForExistence(timeout: 5))
        pause(1.5)
        pickLastPeriodDay(in: app, daysAgo: 25)
        pause(1.5)
        app.buttons["Next"].tap()

        // Cycle length: "learn it for me" is the default.
        XCTAssertTrue(app.staticTexts["How long is your cycle usually?"].waitForExistence(timeout: 5))
        pause(2)
        app.buttons["Next"].tap()

        // Payoff: where she is in her cycle and her first flower.
        XCTAssertTrue(app.staticTexts["You're all set"].waitForExistence(timeout: 5))
        pause(3)
        app.buttons["Next"].tap()

        // Garden: start today's cards.
        let start = app.buttons["Start today"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        pause(2)
        start.tap()
        pause(1.5)
        answerDeck(in: app)

        // Bloom, flower lands, streak ticks up.
        let details = app.buttons["See full details"]
        XCTAssertTrue(details.waitForExistence(timeout: 15))
        pause(2.5)
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Done'")).firstMatch.tap()
        pause(2)

        // Share card.
        let share = app.buttons["Share bouquet"]
        if share.waitForExistence(timeout: 5) {
            share.tap()
            pause(3)
            app.buttons["Close"].firstMatch.tap()
            pause(1.5)
        }

        // Details: next period, today, what Clutch learned, doctor summary.
        if details.waitForExistence(timeout: 5) {
            details.tap()
            XCTAssertTrue(app.staticTexts["your details"].waitForExistence(timeout: 5))
            pause(3)
            for _ in 0..<4 {
                slowScroll(app, up: true)
                pause(2.2)
            }
            app.buttons["Back"].tap()
            pause(1.5)
        }

        // Free period products near her.
        let request = app.buttons["Request"]
        if request.waitForExistence(timeout: 5) {
            request.tap()
            allowLocation()
            pause(2.5)
            slowScroll(app, up: true)
            pause(2.5)
            app.swipeDown(velocity: .fast)
            pause(1.5)
        }

        // Every past bouquet, one per day she checked in.
        let bouquets = app.buttons["Bouquets"]
        if bouquets.waitForExistence(timeout: 5) {
            bouquets.tap()
            pause(3)
            app.buttons["Close"].firstMatch.tap()
            pause(1.5)
        }
    }

    // MARK: - Steps

    /// Mood, energy, symptoms, flow: whichever cards today's deck holds.
    private func answerDeck(in app: XCUIApplication) {
        for _ in 0..<6 {
            pause(1)
            if app.buttons["See full details"].exists { return }
            if app.staticTexts["How's your mood today?"].exists {
                pause(1.5); tapFront(app, "Okay")
            } else if app.staticTexts["How's your energy today?"].exists {
                pause(1.5); tapFront(app, "Low")
            } else if app.staticTexts["Anything else today?"].exists {
                pause(1.5)
                for label in ["cramps", "bloating", "cravings"] {
                    tapFront(app, label); pause(0.6)
                }
                pause(0.8)
                tapFront(app, "Done")
            } else if app.staticTexts["How's your flow today?"].exists {
                pause(1.5); tapFront(app, "Light flow")
            } else if app.staticTexts["Yesterday was rough. What helped?"].exists {
                pause(1.5)
                tapFront(app, "heating pad"); pause(0.5)
                tapFront(app, "rest"); pause(0.5)
                tapFront(app, "Done")
            } else {
                return
            }
        }
    }

    /// The cards behind the top one are still in the tree, a little lower
    /// down, so tap the highest match.
    private func tapFront(_ app: XCUIApplication, _ label: String) {
        let matches = app.buttons.matching(NSPredicate(format: "label ==[c] %@", label)).allElementsBoundByIndex
        matches.filter(\.isHittable).min { $0.frame.minY < $1.frame.minY }?.tap()
    }

    /// "Navi" in straight strokes on the PencilKit canvas.
    private func scribbleName(in window: XCUIElement) {
        let origin = window.coordinate(withNormalizedOffset: CGVector(dx: 0.24, dy: 0.46))
        let w = window.frame.width * 0.12
        let h = window.frame.width * 0.16
        func stroke(_ points: [(CGFloat, CGFloat)]) {
            for (a, b) in zip(points, points.dropFirst()) {
                origin.withOffset(CGVector(dx: a.0 * w, dy: a.1 * h))
                    .press(forDuration: 0.02, thenDragTo: origin.withOffset(CGVector(dx: b.0 * w, dy: b.1 * h)), withVelocity: 600, thenHoldForDuration: 0)
            }
        }
        stroke([(0, 1), (0, 0), (0.8, 1), (0.8, 0)])                  // N
        stroke([(1.9, 0.45), (1.3, 0.5), (1.2, 0.9), (1.6, 1), (1.9, 0.75)])
        stroke([(1.9, 0.4), (1.9, 1)])                                   // a
        stroke([(2.3, 0.4), (2.65, 1), (3.0, 0.4)])                      // v
        stroke([(3.4, 0.45), (3.4, 1)])                                  // i
        stroke([(3.4, 0.18), (3.43, 0.22)])
    }

    /// Taps the day `daysAgo` before today, going back a month if needed.
    private func pickLastPeriodDay(in app: XCUIApplication, daysAgo: Int) {
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        let wanted = formatter.string(from: day)
        let picker = app.datePickers.firstMatch
        func button() -> XCUIElement {
            picker.buttons.matching(NSPredicate(format: "label CONTAINS %@", ", \(wanted)")).firstMatch
        }
        if !button().exists {
            let previous = picker.buttons["Previous Month"]
            if previous.exists { previous.tap(); pause(1) }
        }
        if button().exists { button().tap() }
    }

    /// The system location prompt the Request screen asks for.
    private func allowLocation() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow While Using App"]
        if allow.waitForExistence(timeout: 4) {
            pause(1.5)
            allow.tap()
        }
    }

    private func slowScroll(_ app: XCUIApplication, up: Bool) {
        let window = app.windows.firstMatch
        let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.75 : 0.3))
        let to = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.3 : 0.75))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: 450, thenHoldForDuration: 0.2)
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func mark(_ name: String) {
        try? FileManager.default.createDirectory(atPath: markerDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: "\(markerDirectory)/\(name)", contents: nil)
    }
}
