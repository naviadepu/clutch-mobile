import XCTest
@testable import Clutch

final class ClutchTests: XCTestCase {

    func testEmulatorsEnabledInDebugByDefault() {
        // The test bundle builds in the Debug configuration, and the scheme does
        // not set USE_FIREBASE_EMULATORS=0, so the app should target emulators.
        XCTAssertTrue(FirebaseBootstrap.useEmulators)
    }

    func testEmulatorHostIsLoopback() {
        XCTAssertEqual(FirebaseBootstrap.emulatorHost, "127.0.0.1")
        XCTAssertEqual(FirebaseBootstrap.authEmulatorPort, 9099)
        XCTAssertEqual(FirebaseBootstrap.firestoreEmulatorPort, 8080)
    }
}
