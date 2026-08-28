import XCTest

final class Snap_ShopUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Skip onboarding and auth so the camera tab is the first thing rendered.
        app.launchArguments += ["-UITesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: — Launch

    @MainActor
    func testAppLaunchCameraViewIsVisible() throws {
        // Shutter button is the defining element of CameraView; its accessibility label
        // is set by P4.007. At least one of these labels must be present within 5 s.
        let shutter = app.buttons.matching(
            NSPredicate(format: "label IN %@", ["Take photo", "Start recording"])
        ).firstMatch
        XCTAssertTrue(
            shutter.waitForExistence(timeout: 5),
            "Shutter button with accessibility label not found — CameraView may not have loaded"
        )
    }

    // MARK: — Camera control VoiceOver labels (P4.007 / P4.008)

    @MainActor
    func testCameraFlashButtonHasAccessibilityLabel() throws {
        let flash = app.buttons.matching(
            NSPredicate(format: "label IN %@", ["Flash on", "Flash off"])
        ).firstMatch
        XCTAssertTrue(
            flash.waitForExistence(timeout: 5),
            "Flash toggle button must expose 'Flash on' or 'Flash off' to VoiceOver"
        )
    }

    @MainActor
    func testScanModeButtonsHaveAccessibilityLabels() throws {
        XCTAssertTrue(
            app.buttons["Precision"].waitForExistence(timeout: 5),
            "Precision mode button accessibility label missing"
        )
        XCTAssertTrue(
            app.buttons["Deep"].waitForExistence(timeout: 5),
            "Deep mode button accessibility label missing"
        )
    }

    // MARK: — Launch performance

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let a = XCUIApplication()
            a.launchArguments += ["-UITesting"]
            a.launch()
        }
    }
}
