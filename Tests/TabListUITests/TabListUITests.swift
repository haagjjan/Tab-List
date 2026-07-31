import XCTest

@MainActor
final class TabListUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAccessoryApplicationStaysRunning() throws {
        let application = configuredApplication(
            showing: "--ui-testing-show-onboarding"
        )
        application.launch()

        let deadline = Date().addingTimeInterval(5)
        var reachedRunningState = false
        while Date() < deadline {
            if application.state == .runningBackground ||
                application.state == .runningForeground
            {
                reachedRunningState = true
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTAssertTrue(
            reachedRunningState,
            "The accessory application should remain alive after launch."
        )
    }

    func testFirstRunExplainsBehaviorAndPrivacy() {
        let application = configuredApplication(
            showing: "--ui-testing-show-onboarding"
        )
        application.launch()

        XCTAssertTrue(
            application.windows["Welcome to Tab‑List"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            application.staticTexts[
                "Switch between windows, not just applications."
            ].exists
        )
        XCTAssertTrue(
            application.staticTexts[
                "Window information and previews stay on this Mac. "
                    + "Tab‑List has no analytics and never uploads window "
                    + "titles or screenshots."
            ].exists
        )
        XCTAssertTrue(
            application.buttons["onboarding.continue"].exists
                || application.buttons["Continue"].exists
        )
    }

    func testSettingsExposeAllVersionTwoSectionsAndModes() {
        let application = configuredApplication(
            showing: "--ui-testing-show-settings"
        )
        application.launch()

        XCTAssertTrue(
            application.windows.firstMatch.waitForExistence(timeout: 5),
            "The Settings window should be visible after the UI-test launch."
        )
        for section in [
            "Appearance",
            "Controls",
            "Filtering",
            "Exceptions",
            "General",
            "About",
        ] {
            XCTAssertTrue(
                application.staticTexts[section].exists
                    || application.buttons[section].exists,
                "Missing Settings section: \(section)"
            )
        }
        for mode in ["Thumbnails", "App Icons", "Titles"] {
            XCTAssertTrue(
                application.descendants(matching: .any)[mode].exists,
                "Missing presentation mode: \(mode)"
            )
        }
    }

    private func configuredApplication(showing launchArgument: String)
        -> XCUIApplication
    {
        let application = XCUIApplication()
        application.launchArguments = ["--ui-testing", launchArgument]
        application.launchEnvironment[
            "TABLIST_DISABLE_GLOBAL_SHORTCUT"
        ] = "1"
        return application
    }
}
