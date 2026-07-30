import TabListCore
import Testing
@testable import TabList

@Suite
struct SettingsViewModelTests {
    @Test
    @MainActor
    func testResetPreferencesPreservesSystemOwnedState() {
        var customized = SettingsV1.default
        customized.presentation = .titles
        customized.opacity = 0.73
        customized.excludedBundleIdentifiers = ["com.example.Excluded"]
        customized.automaticallyChecksForUpdates = false

        let model = SettingsViewModel(settings: customized)
        model.launchAtLoginEnabled = true
        model.accessibilityGranted = true
        model.screenRecordingGranted = true
        var appliedSettings: SettingsV1?
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
        XCTAssertTrue(model.screenRecordingGranted)
    }
}
