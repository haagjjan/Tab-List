import Testing
@testable import TabListCore

@Suite
struct ShortcutTests {
    @Test
    func testCommandTabIsValid() {
        XCTAssertEqual(ShortcutValidator.validate(.commandTab), .valid)
    }

    @Test
    func testModifierOnlyShortcutIsRejected() {
        let shortcut = ShortcutDefinition(keyCode: nil, modifiers: .command)

        XCTAssertEqual(
            ShortcutValidator.validate(shortcut),
            .invalid(.missingKey)
        )
    }

    @Test
    func testShortcutWithoutModifierIsRejected() {
        let shortcut = ShortcutDefinition(keyCode: 48, modifiers: [])

        XCTAssertEqual(
            ShortcutValidator.validate(shortcut),
            .invalid(.missingModifier)
        )
    }

    @Test
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

    @Test
    func testShiftOnlyShortcutIsRejectedBecauseShiftReversesCycling() {
        let shortcut = ShortcutDefinition(keyCode: 48, modifiers: .shift)

        XCTAssertEqual(
            ShortcutValidator.validate(shortcut),
            .invalid(.shiftOnlyModifier)
        )
    }

    @Test
    func testShiftCanAccompanyABaseModifier() {
        let shortcut = ShortcutDefinition(
            keyCode: 48,
            modifiers: [.command, .shift]
        )

        XCTAssertEqual(ShortcutValidator.validate(shortcut), .valid)
    }

    @Test
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

    @Test
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

    @Test
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
