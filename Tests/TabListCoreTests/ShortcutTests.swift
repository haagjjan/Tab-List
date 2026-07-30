import XCTest
@testable import TabListCore

final class ShortcutTests: XCTestCase {
    func testCommandTabIsValid() {
        XCTAssertEqual(ShortcutValidator.validate(.commandTab), .valid)
    }

    func testModifierOnlyShortcutIsRejected() {
        let shortcut = ShortcutDefinition(keyCode: nil, modifiers: .command)

        XCTAssertEqual(
            ShortcutValidator.validate(shortcut),
            .invalid(.missingKey)
        )
    }

    func testShortcutWithoutModifierIsRejected() {
        let shortcut = ShortcutDefinition(keyCode: 48, modifiers: [])

        XCTAssertEqual(
            ShortcutValidator.validate(shortcut),
            .invalid(.missingModifier)
        )
    }

    func testSwitcherActionKeysAreRejectedAsTriggers() {
        for keyCode: UInt16 in [53, 51, 117] {
            let shortcut = ShortcutDefinition(
                keyCode: keyCode,
                modifiers: .command
            )

            XCTAssertEqual(
                ShortcutValidator.validate(shortcut),
                .invalid(.reservedActionKey)
            )
        }
    }

    func testShiftOnlyShortcutIsRejectedBecauseShiftReversesCycling() {
        let shortcut = ShortcutDefinition(keyCode: 48, modifiers: .shift)

        XCTAssertEqual(
            ShortcutValidator.validate(shortcut),
            .invalid(.shiftOnlyModifier)
        )
    }

    func testShiftCanAccompanyABaseModifier() {
        let shortcut = ShortcutDefinition(
            keyCode: 48,
            modifiers: [.command, .shift]
        )

        XCTAssertEqual(ShortcutValidator.validate(shortcut), .valid)
    }

    func testUnknownModifierBitsAreRejected() {
        let shortcut = ShortcutDefinition(
            keyCode: 48,
            modifiers: ShortcutModifiers(rawValue: 1 << 7)
        )

        XCTAssertEqual(
            ShortcutValidator.validate(shortcut),
            .invalid(.unsupportedModifiers)
        )
    }

    func testKnownAndRuntimeRegistrationConflictsAreRejected() {
        XCTAssertEqual(
            ShortcutValidator.validate(
                .commandTab,
                against: [.commandTab]
            ),
            .invalid(.conflictsWithExistingShortcut)
        )
        XCTAssertEqual(
            ShortcutValidator.validate(
                .commandTab,
                registrationConflict: true
            ),
            .invalid(.conflictsWithExistingShortcut)
        )
    }

    func testKnownConflictsCompareRegistrationIdentityWithoutShift() {
        let commandShiftTab = ShortcutDefinition(
            keyCode: 48,
            modifiers: [.command, .shift]
        )

        XCTAssertEqual(
            ShortcutValidator.validate(
                commandShiftTab,
                against: [.commandTab]
            ),
            .invalid(.conflictsWithExistingShortcut)
        )
    }
}
