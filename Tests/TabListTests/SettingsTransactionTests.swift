import TabListCore
import Testing
@testable import TabList

@Suite
struct SettingsTransactionTests {
    @Test
    func testFailedShortcutReplacementKeepsPreviousShortcutOnly() {
        var previous = TabListSettings.default
        previous.shortcut = ShortcutDefinition(
            keyCode: 49,
            modifiers: [.command, .option]
        )
        var requested = TabListSettings.default
        requested.theme = .dark
        requested.includeMinimized = false

        let committed = SettingsTransaction.committed(
            previous: previous,
            requested: requested,
            shortcutRegistrationRequired: true,
            shortcutRegistrationSucceeded: false
        )

        XCTAssertEqual(committed.shortcut, previous.shortcut)
        XCTAssertEqual(committed.theme, requested.theme)
        XCTAssertEqual(committed.includeMinimized, requested.includeMinimized)
    }

    @Test
    func testSuccessfulShortcutReplacementCommitsRequestedSettings() {
        var requested = TabListSettings.default
        requested.shortcut = ShortcutDefinition(
            keyCode: 49,
            modifiers: [.command, .option]
        )

        XCTAssertEqual(
            SettingsTransaction.committed(
                previous: .default,
                requested: requested,
                shortcutRegistrationRequired: true,
                shortcutRegistrationSucceeded: true
            ),
            requested
        )
    }

    @Test
    func testUnchangedShortcutDoesNotDependOnRegistrationResult() {
        var requested = TabListSettings.default
        requested.theme = .light

        XCTAssertEqual(
            SettingsTransaction.committed(
                previous: .default,
                requested: requested,
                shortcutRegistrationRequired: false,
                shortcutRegistrationSucceeded: false
            ),
            requested
        )
    }
}
