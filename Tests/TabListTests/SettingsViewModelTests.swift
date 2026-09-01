import TabListCore
import Testing
@testable import TabList

@Suite
struct SettingsViewModelTests {
    @Test
    @MainActor
    func testResetPreferencesPreservesSystemOwnedState() {
        var customized = TabListSettings.default
        customized.theme = .dark
        customized.excludedBundleIdentifiers = ["com.example.Excluded"]
        customized.automaticallyChecksForUpdates = false

        let model = SettingsViewModel(settings: customized)
        model.launchAtLoginEnabled = true
        model.accessibilityGranted = true
        var appliedSettings: TabListSettings?
        model.onSettingsChanged = { appliedSettings = $0 }
        model.onLaunchAtLoginChanged = { _ in
            XCTFail("Resetting preferences must not change Launch at Login.")
            return false
        }

        model.resetPreferences()

        XCTAssertEqual(model.settings, .default)
        XCTAssertEqual(appliedSettings, .default)
        XCTAssertTrue(model.launchAtLoginEnabled)
        XCTAssertTrue(model.accessibilityGranted)
    }

    @Test
    @MainActor
    func testReverseControlRejectsReservedKeysAndAcceptsARegularKey() {
        let model = SettingsViewModel(settings: .default)

        model.updateReverseControl(.key(48))
        XCTAssertEqual(model.settings.reverseControl, .shiftWithForwardKey)
        XCTAssertTrue(model.reverseControlValidationMessage != nil)

        model.updateReverseControl(.key(15))
        XCTAssertEqual(model.settings.reverseControl, .key(15))
        XCTAssertNil(model.reverseControlValidationMessage)
    }
}
