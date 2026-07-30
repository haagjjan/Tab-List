import XCTest

final class WindowFixtureUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testInitialFixtureCreatesMultipleIndependentWindows() {
        let application = XCUIApplication()
        application.launch()

        XCTAssertTrue(
            application.windows[
                "Tab-List Window Fixture Controls"
            ].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(application.windows["Standard Window 1"].exists)
        XCTAssertTrue(application.windows["Standard Window 2"].exists)
        XCTAssertTrue(
            application.staticTexts["Untitled standard window"].exists
        )
    }

    func testFixtureControlsCreateSpecialWindowScenarios() {
        let application = XCUIApplication()
        application.launch()

        let scenarios = [
            "fixture.new-utility-panel",
            "fixture.new-unclosable-window",
            "fixture.new-unsaved-document",
            "fixture.new-native-tab-group",
        ]
        for identifier in scenarios {
            let button = application.buttons[identifier]
            XCTAssertTrue(
                button.waitForExistence(timeout: 3),
                "Missing fixture control \(identifier)"
            )
            button.click()
        }

        XCTAssertTrue(application.windows["Utility Palette 4"].exists)
        XCTAssertTrue(application.windows["Unclosable Window 5"].exists)
        XCTAssertTrue(application.windows["Unsaved Document 6"].exists)
        XCTAssertTrue(application.windows["Native Tab A"].exists)
    }

    func testFixtureExposesMutationAndHighWindowCountControls() {
        let application = XCUIApplication()
        application.launch()

        for identifier in [
            "fixture.new-identical-title-pair",
            "fixture.new-very-long-title-window",
            "fixture.retitle-a-standard-window",
            "fixture.move-and-resize-a-standard-window",
            "fixture.create-10-standard-windows",
            "fixture.create-50-standard-windows",
            "fixture.create-100-standard-windows",
            "fixture.hide-fixture-application",
            "fixture.block-fixture-main-thread-for-8-seconds",
        ] {
            XCTAssertTrue(
                application.buttons[identifier].waitForExistence(timeout: 3),
                "Missing fixture control \(identifier)"
            )
        }
    }

    func testFixtureLaunchArgumentCreatesTenTotalWindows() {
        let application = XCUIApplication()
        application.launchArguments = ["--fixture-window-count=10"]
        application.launch()

        XCTAssertTrue(
            application.windows[
                "Tab-List Window Fixture Controls"
            ].waitForExistence(timeout: 5)
        )
        XCTAssertGreaterThanOrEqual(application.windows.count, 10)
    }
}
