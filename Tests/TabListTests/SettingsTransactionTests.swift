import TabListCore
import Testing
@testable import TabList

@Suite
struct SettingsTransactionTests {
    @Test
    func testFailedShortcutReplacementKeepsPreviousShortcutOnly() {
        var previous = SettingsV1.default
        previous.shortcut = ShortcutDefinition(
            keyCode: 49,
            modifiers: [.command, .option]
        )
        var requested = SettingsV1.default
        requested.opacity = 0.74
        requested.presentation = .titles

        let committed = SettingsTransaction.committed(
            previous: previous,
            requested: requested,
            shortcutRegistrationRequired: true,
            shortcutRegistrationSucceeded: false
        )

        XCTAssertEqual(committed.shortcut, previous.shortcut)
        XCTAssertEqual(committed.opacity, requested.opacity)
        XCTAssertEqual(committed.presentation, requested.presentation)
    }

    @Test
    func testSuccessfulShortcutReplacementCommitsRequestedSettings() {
        var requested = SettingsV1.default
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
        var requested = SettingsV1.default
        requested.opacity = 0.93

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
