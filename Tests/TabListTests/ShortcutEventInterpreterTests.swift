import Carbon.HIToolbox
import TabListCore
import Testing
@testable import TabList

@Suite
struct ShortcutEventInterpreterTests {
    @Test
    func commandShiftTabBeginsAndCyclesBackward() {
        let held: ShortcutModifiers = [.command, .shift]

        XCTAssertEqual(
            ShortcutEventInterpreter.keyDown(
                keyCode: UInt16(kVK_Tab),
                heldModifiers: held,
                shortcut: .commandTab,
                sessionActive: false
            ),
            ShortcutEventOutcome(
                command: .begin(reverse: true),
                consumesEvent: true,
                sessionActive: true
            )
        )
        XCTAssertEqual(
            ShortcutEventInterpreter.keyDown(
                keyCode: UInt16(kVK_Tab),
                heldModifiers: held,
                shortcut: .commandTab,
                sessionActive: true
            ),
            ShortcutEventOutcome(
                command: .cycle(reverse: true, isRepeat: false),
                consumesEvent: true,
                sessionActive: true
            )
        )
    }

    @Test
    func autorepeatIsMarkedSoTheReducerCanStopAtTheBoundary() {
        XCTAssertEqual(
            ShortcutEventInterpreter.keyDown(
                keyCode: UInt16(kVK_Tab),
                heldModifiers: [.command],
                shortcut: .commandTab,
                sessionActive: true,
                isRepeat: true
            ),
            ShortcutEventOutcome(
                command: .cycle(reverse: false, isRepeat: true),
                consumesEvent: true,
                sessionActive: true
            )
        )
    }

    @Test
    func shiftAloneChangesDirectionWithoutMovingSelection() {
        XCTAssertEqual(
            ShortcutEventInterpreter.modifiersChanged(
                heldModifiers: [.command, .shift],
                shortcut: .commandTab,
                sessionActive: true
            ),
            ShortcutEventOutcome(
                command: nil,
                consumesEvent: false,
                sessionActive: true
            )
        )
    }

    @Test
    func releasingBaseModifierCommits() {
        XCTAssertEqual(
            ShortcutEventInterpreter.modifiersChanged(
                heldModifiers: [.shift],
                shortcut: .commandTab,
                sessionActive: true
            ),
            ShortcutEventOutcome(
                command: .commit,
                consumesEvent: false,
                sessionActive: false
            )
        )
    }

    @Test
    func deleteIsConsumedWithoutEndingActiveSession() {
        XCTAssertEqual(
            ShortcutEventInterpreter.keyDown(
                keyCode: UInt16(kVK_ForwardDelete),
                heldModifiers: [.command],
                shortcut: .commandTab,
                sessionActive: true
            ),
            ShortcutEventOutcome(
                command: .closeSelectedWindow,
                consumesEvent: true,
                sessionActive: true
            )
        )
        XCTAssertTrue(
            ShortcutEventInterpreter.consumesKeyUp(
                keyCode: UInt16(kVK_ForwardDelete),
                shortcut: .commandTab,
                reverseControl: .shiftWithForwardKey,
                sessionActive: true
            )
        )
    }

    @Test
    func activeForwardAndCustomReverseKeyUpsAreConsumed() {
        XCTAssertTrue(
            ShortcutEventInterpreter.consumesKeyUp(
                keyCode: UInt16(kVK_Tab),
                shortcut: .commandTab,
                reverseControl: .key(UInt16(kVK_ANSI_R)),
                sessionActive: true
            )
        )
        XCTAssertTrue(
            ShortcutEventInterpreter.consumesKeyUp(
                keyCode: UInt16(kVK_ANSI_R),
                shortcut: .commandTab,
                reverseControl: .key(UInt16(kVK_ANSI_R)),
                sessionActive: true
            )
        )
        XCTAssertFalse(
            ShortcutEventInterpreter.consumesKeyUp(
                keyCode: UInt16(kVK_ANSI_R),
                shortcut: .commandTab,
                reverseControl: .key(UInt16(kVK_ANSI_R)),
                sessionActive: false
            )
        )
    }

    @Test
    func holdCycleSpeedScalesSystemIntervalWithinBounds() {
        let slow = HoldCycleTiming.repeatInterval(
            systemInterval: 0.1,
            speed: 0.5
        )
        let fast = HoldCycleTiming.repeatInterval(
            systemInterval: 0.1,
            speed: 2
        )
        let nonfinite = HoldCycleTiming.repeatInterval(
            systemInterval: 0.1,
            speed: .infinity
        )

        #expect(abs(slow - 0.2) < 0.000_1)
        #expect(abs(fast - 0.05) < 0.000_1)
        #expect(abs(nonfinite - 0.1) < 0.000_1)
    }

    @Test
    func unrelatedOrConflictingKeyEventsPassThrough() {
        XCTAssertEqual(
            ShortcutEventInterpreter.keyDown(
                keyCode: UInt16(kVK_ANSI_A),
                heldModifiers: [.command],
                shortcut: .commandTab,
                sessionActive: true
            ).consumesEvent,
            false
        )
        XCTAssertEqual(
            ShortcutEventInterpreter.keyDown(
                keyCode: UInt16(kVK_Tab),
                heldModifiers: [.command, .option],
                shortcut: .commandTab,
                sessionActive: true
            ).consumesEvent,
            false
        )
    }
}
