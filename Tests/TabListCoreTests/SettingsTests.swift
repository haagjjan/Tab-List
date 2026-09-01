import Foundation
import Testing
@testable import TabListCore

@Suite
struct SettingsTests {
    @Test
    func testDefaultsMatchProductDecisions() {
        let settings = TabListSettings.default

        XCTAssertEqual(settings.theme, .system)
        XCTAssertEqual(settings.shortcut, .commandTab)
        XCTAssertEqual(settings.spaceScope, .allSpaces)
        XCTAssertEqual(settings.screenScope, .allScreens)
        XCTAssertTrue(settings.includeMinimized)
        XCTAssertTrue(settings.includeHiddenApps)
        XCTAssertTrue(settings.includeFullscreen)
        XCTAssertTrue(settings.excludedBundleIdentifiers.isEmpty)
        XCTAssertTrue(settings.showMenuBarIcon)
        XCTAssertTrue(settings.automaticallyChecksForUpdates)
        XCTAssertEqual(settings.reverseControl, .shiftWithForwardKey)
        XCTAssertEqual(settings.holdCycleSpeed, 1.0)
    }

    @Test
    func testNormalizationCleansExclusions() {
        var settings = TabListSettings.default
        settings.excludedBundleIdentifiers = ["", "  ", " com.example.App "]

        XCTAssertEqual(
            settings.normalized().excludedBundleIdentifiers,
            ["com.example.App"]
        )
    }

    @Test
    func testNormalizationReplacesAnInvalidShortcut() {
        var settings = TabListSettings.default
        settings.shortcut = ShortcutDefinition(
            keyCode: nil,
            modifiers: .command
        )

        XCTAssertEqual(settings.normalized().shortcut, .commandTab)
    }

    @Test
    func testHoldCycleSpeedIsClampedAndNonFiniteValueUsesDefault() {
        var settings = TabListSettings.default
        settings.holdCycleSpeed = 8
        XCTAssertEqual(settings.normalized().holdCycleSpeed, 2)

        settings.holdCycleSpeed = 0.1
        XCTAssertEqual(settings.normalized().holdCycleSpeed, 0.5)

        settings.holdCycleSpeed = .infinity
        XCTAssertEqual(settings.normalized().holdCycleSpeed, 1)
    }

    @Test
    func testScopePresetMappingsAreDeterministic() {
        XCTAssertEqual(
            ScopePreset(spaceScope: .allSpaces, screenScope: .allScreens),
            .everywhere
        )
        XCTAssertEqual(
            ScopePreset(spaceScope: .visibleSpaces, screenScope: .allScreens),
            .visibleNow
        )
        XCTAssertEqual(
            ScopePreset(
                spaceScope: .visibleSpaces,
                screenScope: .pointerScreen
            ),
            .pointerDisplay
        )
        XCTAssertEqual(
            ScopePreset(spaceScope: .allSpaces, screenScope: .pointerScreen),
            .custom
        )
    }

    @Test
    func testNormalizationReservesShiftForReverseCycling() {
        var settings = TabListSettings.default
        settings.shortcut = ShortcutDefinition(
            keyCode: 48,
            modifiers: [.command, .shift]
        )

        XCTAssertEqual(settings.normalized().shortcut, .commandTab)
    }

    @Test
    func testVersionedPersistenceRoundTrip() throws {
        var settings = TabListSettings.default
        settings.theme = .dark
        settings.excludedBundleIdentifiers = ["com.example.Secret"]

        let data = try SettingsPersistence.encode(settings)
        let decoded = try SettingsPersistence.decode(data)

        XCTAssertEqual(decoded.settings, settings.normalized())
        XCTAssertEqual(decoded.source, .versioned(schemaVersion: 3))
    }

    @Test
    func testLegacyUnversionedSettingsAreMigrated() throws {
        var settings = TabListSettings.default
        settings.theme = .light
        let data = try JSONEncoder().encode(settings)

        let decoded = try SettingsPersistence.decode(data)

        XCTAssertEqual(decoded.settings, settings)
        XCTAssertEqual(decoded.source, .legacyUnversioned)
    }

    @Test
    func testRetiredPresentationKeysAreIgnoredAndReplacedByDefaults() throws {
        let encoded = try JSONEncoder().encode(
            PersistedSettingsEnvelope(settings: .default)
        )
        var envelope = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        envelope["schemaVersion"] = 2
        var settings = try #require(envelope["settings"] as? [String: Any])
        settings["presentation"] = "thumbnails"
        settings["panelSize"] = "large"
        settings["opacity"] = 0.72
        settings["refreshThumbnailsInBackground"] = true
        settings.removeValue(forKey: "reverseControl")
        settings.removeValue(forKey: "holdCycleSpeed")
        settings.removeValue(forKey: "theme")
        envelope["settings"] = settings
        let legacyData = try JSONSerialization.data(withJSONObject: envelope)

        let decoded = try SettingsPersistence.decode(legacyData)

        XCTAssertEqual(decoded.source, .versioned(schemaVersion: 2))
        XCTAssertEqual(decoded.settings.theme, .system)
        XCTAssertEqual(decoded.settings.reverseControl, .shiftWithForwardKey)
        XCTAssertEqual(decoded.settings.holdCycleSpeed, 1)
    }

    @Test
    func testUnsupportedSchemaVersionIsRejected() throws {
        let data = try JSONEncoder().encode(
            PersistedSettingsEnvelope(schemaVersion: 99, settings: .default)
        )

        XCTAssertThrowsError(try SettingsPersistence.decode(data)) { error in
            XCTAssertEqual(
                error as? SettingsPersistenceError,
                .unsupportedSchemaVersion(99)
            )
        }
    }

    @Test
    func testMalformedSettingsAreRejected() {
        let data = Data("not json".utf8)

        XCTAssertThrowsError(try SettingsPersistence.decode(data)) { error in
            XCTAssertEqual(
                error as? SettingsPersistenceError,
                .malformedPayload
            )
        }
    }
}

@Suite
struct SettingsSchemaBoundaryTests {
    @Test
    func testSchemaVersionZeroIsRejected() throws {
        let data = try JSONEncoder().encode(
            PersistedSettingsEnvelope(schemaVersion: 0, settings: .default)
        )

        XCTAssertThrowsError(try SettingsPersistence.decode(data)) { error in
            XCTAssertEqual(
                error as? SettingsPersistenceError,
                .unsupportedSchemaVersion(0)
            )
        }
    }

    @Test
    func testEverySupportedSchemaVersionDecodes() throws {
        for version in 1 ... PersistedSettingsEnvelope.currentSchemaVersion {
            let data = try JSONEncoder().encode(
                PersistedSettingsEnvelope(
                    schemaVersion: version,
                    settings: .default
                )
            )

            let source = try SettingsPersistence.decode(data).source

            XCTAssertEqual(source, .versioned(schemaVersion: version))
        }
    }

    @Test
    func testAPayloadMissingEveryOptionalKeyStillDecodes() throws {
        let data = Data("{\"schemaVersion\":3,\"settings\":{}}".utf8)

        let decoded = try SettingsPersistence.decode(data).settings

        XCTAssertEqual(decoded, .default)
    }

    @Test
    func testNormalizationIsIdempotent() {
        var settings = TabListSettings.default
        settings.holdCycleSpeed = 5
        settings.excludedBundleIdentifiers = [" com.example.App "]

        let once = settings.normalized()

        XCTAssertEqual(once, once.normalized())
    }
}
