import Foundation
import TabListCore
import Testing
@testable import TabList

private struct DefaultsSandbox: ~Copyable {
    let suiteName: String
    let defaults: UserDefaults

    init() {
        suiteName = "com.haagjjan.TabListTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }
}

@Suite
@MainActor
struct SettingsStoreTests {
    @Test
    func testAnEmptyDomainStartsFromTheShippedDefaults() {
        let sandbox = DefaultsSandbox()

        XCTAssertEqual(
            SettingsStore(defaults: sandbox.defaults).settings,
            .default
        )
    }

    @Test
    func testPreferencesSurviveARelaunch() {
        let sandbox = DefaultsSandbox()
        var written = TabListSettings.default
        written.theme = .dark
        written.includeMinimized = false
        written.excludedBundleIdentifiers = ["com.example.Excluded"]

        SettingsStore(defaults: sandbox.defaults).update(written)

        XCTAssertEqual(
            SettingsStore(defaults: sandbox.defaults).settings,
            written
        )
    }

    @Test
    func testUpdatingNormalizesBeforePersisting() {
        let sandbox = DefaultsSandbox()
        let store = SettingsStore(defaults: sandbox.defaults)
        var requested = TabListSettings.default
        requested.shortcut = ShortcutDefinition(
            keyCode: 48,
            modifiers: [.command, .shift]
        )
        requested.excludedBundleIdentifiers = ["  ", " com.example.App "]
        requested.holdCycleSpeed = 99

        store.update(requested)

        XCTAssertEqual(store.settings.shortcut, .commandTab)
        XCTAssertEqual(
            store.settings.excludedBundleIdentifiers,
            ["com.example.App"]
        )
        XCTAssertEqual(store.settings.holdCycleSpeed, 2)
    }

    @Test
    func testALegacyUnversionedPayloadIsMigratedAndRewritten() throws {
        let sandbox = DefaultsSandbox()
        var legacy = TabListSettings.default
        legacy.theme = .light
        sandbox.defaults.set(
            try JSONEncoder().encode(legacy),
            forKey: "settings.payload"
        )

        let store = SettingsStore(defaults: sandbox.defaults)
        let rewritten = try XCTUnwrap(
            sandbox.defaults.data(forKey: "settings.payload")
        )
        let source = try SettingsPersistence.decode(rewritten).source

        XCTAssertEqual(store.settings.theme, .light)
        XCTAssertEqual(
            source,
            .versioned(
                schemaVersion: PersistedSettingsEnvelope.currentSchemaVersion
            )
        )
    }

    @Test
    func testAPayloadFromARetiredSchemaLoadsWithoutLosingUsableSettings()
        throws
    {
        let sandbox = DefaultsSandbox()
        var envelope = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: try JSONEncoder().encode(
                    PersistedSettingsEnvelope(settings: .default)
                )
            ) as? [String: Any]
        )
        envelope["schemaVersion"] = 2
        var payload = try XCTUnwrap(envelope["settings"] as? [String: Any])
        payload["presentation"] = "thumbnails"
        payload["panelSize"] = "large"
        payload["theme"] = "dark"
        envelope["settings"] = payload
        sandbox.defaults.set(
            try JSONSerialization.data(withJSONObject: envelope),
            forKey: "settings.payload"
        )

        let store = SettingsStore(defaults: sandbox.defaults)

        XCTAssertEqual(store.settings.theme, .dark)
    }

    @Test
    func testACorruptPayloadFallsBackToDefaultsInsteadOfCrashing() {
        let sandbox = DefaultsSandbox()
        sandbox.defaults.set(
            Data("not a settings payload".utf8),
            forKey: "settings.payload"
        )

        XCTAssertEqual(
            SettingsStore(defaults: sandbox.defaults).settings,
            .default
        )
    }

    @Test
    func testOnboardingCompletionIsRememberedAcrossStores() {
        let sandbox = DefaultsSandbox()

        XCTAssertFalse(
            SettingsStore(defaults: sandbox.defaults).hasCompletedOnboarding
        )
        SettingsStore(defaults: sandbox.defaults).hasCompletedOnboarding = true
        XCTAssertTrue(
            SettingsStore(defaults: sandbox.defaults).hasCompletedOnboarding
        )
    }

    @Test
    func testResettingRestoresEveryStoredPreference() {
        let sandbox = DefaultsSandbox()
        let store = SettingsStore(defaults: sandbox.defaults)
        var customized = TabListSettings.default
        customized.theme = .dark
        customized.showMenuBarIcon = false
        store.update(customized)

        store.reset()

        XCTAssertEqual(store.settings, .default)
        XCTAssertEqual(
            SettingsStore(defaults: sandbox.defaults).settings,
            .default
        )
    }
}
