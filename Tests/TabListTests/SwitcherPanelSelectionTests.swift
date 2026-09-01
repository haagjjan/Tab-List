import TabListCore
import Testing
@testable import TabList

@Suite
@MainActor
struct SwitcherPanelSelectionTests {
    @Test
    func testAFirstSelectionDoesNotScrollTheList() {
        XCTAssertEqual(
            SwitcherPanelController.movement(from: nil, to: 3, itemCount: 8),
            .stationary
        )
    }

    @Test
    func testReselectingTheSameRowIsStationary() {
        XCTAssertEqual(
            SwitcherPanelController.movement(from: 2, to: 2, itemCount: 8),
            .stationary
        )
    }

    @Test
    func testASingleRowListNeverReportsMovement() {
        XCTAssertEqual(
            SwitcherPanelController.movement(from: 0, to: 0, itemCount: 1),
            .stationary
        )
    }

    @Test
    func testMovingDownAndUpIsReportedDirectionally() {
        XCTAssertEqual(
            SwitcherPanelController.movement(from: 1, to: 2, itemCount: 8),
            .forward
        )
        XCTAssertEqual(
            SwitcherPanelController.movement(from: 5, to: 1, itemCount: 8),
            .backward
        )
    }

    @Test
    func testWrappingPastEitherEndKeepsTheTravelDirection() {
        XCTAssertEqual(
            SwitcherPanelController.movement(from: 7, to: 0, itemCount: 8),
            .forward
        )
        XCTAssertEqual(
            SwitcherPanelController.movement(from: 0, to: 7, itemCount: 8),
            .backward
        )
    }

    @Test
    func testATwoRowListWrapsRatherThanReversing() {
        XCTAssertEqual(
            SwitcherPanelController.movement(from: 1, to: 0, itemCount: 2),
            .forward
        )
        XCTAssertEqual(
            SwitcherPanelController.movement(from: 0, to: 1, itemCount: 2),
            .backward
        )
    }
}

/// `displayString` reads the current keyboard layout through Text Input
/// Services, so it stays on the main actor.
@Suite
@MainActor
struct ShortcutDisplayStringTests {
    @Test
    func testModifiersAreRenderedInTheMacOSOrder() {
        XCTAssertEqual(
            ShortcutRecorderView.displayString(
                ShortcutDefinition(
                    keyCode: 48,
                    modifiers: [.command, .option, .control, .shift]
                )
            ),
            "⌃⌥⇧⌘⇥"
        )
    }

    @Test
    func testTheDefaultShortcutRendersAsCommandTab() {
        XCTAssertEqual(
            ShortcutRecorderView.displayString(.commandTab),
            "⌘⇥"
        )
    }

    @Test
    func testSwitcherActionKeysHaveDedicatedGlyphs() {
        let glyphs: [UInt16: String] = [
            36: "↩",
            49: "Space",
            51: "⌫",
            53: "⎋",
            117: "⌦",
            123: "←",
            124: "→",
            125: "↓",
            126: "↑",
        ]

        for (keyCode, glyph) in glyphs {
            XCTAssertEqual(
                ShortcutRecorderView.displayString(
                    ShortcutDefinition(keyCode: keyCode, modifiers: [])
                ),
                glyph
            )
        }
    }

    @Test
    func testAnIncompleteRecordingShowsAPlaceholderKey() {
        XCTAssertEqual(
            ShortcutRecorderView.displayString(
                ShortcutDefinition(keyCode: nil, modifiers: .command)
            ),
            "⌘…"
        )
    }
}
