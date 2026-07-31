import Foundation
import Testing
@testable import TabListCore

@Suite
struct SettingsTests {
    @Test
    func testDefaultsMatchProductDecisions() {
        let settings = SettingsV1.default

        XCTAssertEqual(settings.presentation, .thumbnails)
        XCTAssertEqual(settings.panelSize, .auto)
        XCTAssertEqual(settings.theme, .system)
        XCTAssertEqual(settings.opacity, 1.0, accuracy: 0.000_1)
        XCTAssertEqual(settings.shortcut, .commandTab)
        XCTAssertEqual(settings.spaceScope, .allSpaces)
        XCTAssertEqual(settings.screenScope, .allScreens)
        XCTAssertTrue(settings.includeMinimized)
        XCTAssertTrue(settings.includeHiddenApps)
        XCTAssertTrue(settings.includeFullscreen)
        XCTAssertTrue(settings.excludedBundleIdentifiers.isEmpty)
        XCTAssertFalse(settings.refreshThumbnailsInBackground)
        XCTAssertTrue(settings.showMenuBarIcon)
        XCTAssertTrue(settings.automaticallyChecksForUpdates)
        XCTAssertEqual(settings.reverseControl, .shiftWithForwardKey)
        XCTAssertEqual(settings.holdCycleSpeed, 1.0)
    }

    @Test
    func testNormalizationMigratesLegacyOpacityAndCleansExclusions() {
        var settings = SettingsV1.default
        settings.opacity = 0.72
        settings.excludedBundleIdentifiers = ["", "  ", " com.example.App "]

        let normalized = settings.normalized()

        XCTAssertEqual(normalized.opacity, 1)
        XCTAssertEqual(normalized.excludedBundleIdentifiers, ["com.example.App"])
    }

    @Test
    func testNormalizationUsesDefaultsForNonFiniteOpacityAndInvalidShortcut() {
        var settings = SettingsV1.default
        settings.opacity = .nan
        settings.shortcut = ShortcutDefinition(keyCode: nil, modifiers: .command)

        let normalized = settings.normalized()

        XCTAssertEqual(normalized.opacity, SettingsV1.default.opacity)
        XCTAssertEqual(normalized.shortcut, .commandTab)
    }

    @Test
    func testHoldCycleSpeedIsClampedAndNonFiniteValueUsesDefault() {
        var settings = SettingsV1.default
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
        var settings = SettingsV1.default
        settings.shortcut = ShortcutDefinition(
            keyCode: 48,
            modifiers: [.command, .shift]
        )

        XCTAssertEqual(
            settings.normalized().shortcut,
            .commandTab
        )
    }

    @Test
    func testVersionedPersistenceRoundTrip() throws {
        var settings = SettingsV1.default
        settings.presentation = .titles
        settings.opacity = 0.75
        settings.excludedBundleIdentifiers = ["com.example.Secret"]

        let data = try SettingsPersistence.encode(settings)
        let decoded = try SettingsPersistence.decode(data)

        XCTAssertEqual(decoded.settings, settings.normalized())
        XCTAssertEqual(decoded.source, .versioned(schemaVersion: 2))
    }

    @Test
    func testLegacyUnversionedSettingsAreMigrated() throws {
        var settings = SettingsV1.default
        settings.presentation = .appIcons
        let data = try JSONEncoder().encode(settings)

        let decoded = try SettingsPersistence.decode(data)

        XCTAssertEqual(decoded.settings, settings)
        XCTAssertEqual(decoded.source, .legacyUnversioned)
    }

    @Test
    func testVersionOneEnvelopeMigratesNewControlsToDefaults() throws {
        let encoded = try JSONEncoder().encode(
            PersistedSettingsEnvelope(settings: .default)
        )
        var envelope = try #require(
            JSONSerialization.jsonObject(with: encoded)
                as? [String: Any]
        )
        envelope["schemaVersion"] = 1
        var settings = try #require(
            envelope["settings"] as? [String: Any]
        )
        settings.removeValue(forKey: "reverseControl")
        settings.removeValue(forKey: "holdCycleSpeed")
        envelope["settings"] = settings
        let legacyData = try JSONSerialization.data(withJSONObject: envelope)

        let decoded = try SettingsPersistence.decode(legacyData)

        XCTAssertEqual(decoded.source, .versioned(schemaVersion: 1))
        XCTAssertEqual(decoded.settings.reverseControl, .shiftWithForwardKey)
        XCTAssertEqual(decoded.settings.holdCycleSpeed, 1)
    }

    @Test
    func testUnsupportedSchemaVersionIsRejected() throws {
        let envelope = PersistedSettingsEnvelope(
            schemaVersion: 99,
            settings: .default
        )
        let data = try JSONEncoder().encode(envelope)

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
