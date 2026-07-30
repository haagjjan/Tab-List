import Foundation
import XCTest
@testable import TabListCore

final class SettingsTests: XCTestCase {
    func testDefaultsMatchProductDecisions() {
        let settings = SettingsV1.default

        XCTAssertEqual(settings.presentation, .thumbnails)
        XCTAssertEqual(settings.panelSize, .auto)
        XCTAssertEqual(settings.theme, .system)
        XCTAssertEqual(settings.opacity, 0.88, accuracy: 0.000_1)
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
    }

    func testNormalizationClampsOpacityAndCleansExclusions() {
        var settings = SettingsV1.default
        settings.opacity = 2
        settings.excludedBundleIdentifiers = ["", "  ", " com.example.App "]

        let normalized = settings.normalized()

        XCTAssertEqual(normalized.opacity, 1)
        XCTAssertEqual(normalized.excludedBundleIdentifiers, ["com.example.App"])
    }

    func testNormalizationUsesDefaultsForNonFiniteOpacityAndInvalidShortcut() {
        var settings = SettingsV1.default
        settings.opacity = .nan
        settings.shortcut = ShortcutDefinition(keyCode: nil, modifiers: .command)

        let normalized = settings.normalized()

        XCTAssertEqual(normalized.opacity, SettingsV1.default.opacity)
        XCTAssertEqual(normalized.shortcut, .commandTab)
    }

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

    func testVersionedPersistenceRoundTrip() throws {
        var settings = SettingsV1.default
        settings.presentation = .titles
        settings.opacity = 0.75
        settings.excludedBundleIdentifiers = ["com.example.Secret"]

        let data = try SettingsPersistence.encode(settings)
        let decoded = try SettingsPersistence.decode(data)

        XCTAssertEqual(decoded.settings, settings)
        XCTAssertEqual(decoded.source, .versioned(schemaVersion: 1))
    }

    func testLegacyUnversionedSettingsAreMigrated() throws {
        var settings = SettingsV1.default
        settings.presentation = .appIcons
        let data = try JSONEncoder().encode(settings)

        let decoded = try SettingsPersistence.decode(data)

        XCTAssertEqual(decoded.settings, settings)
        XCTAssertEqual(decoded.source, .legacyUnversioned)
    }

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
