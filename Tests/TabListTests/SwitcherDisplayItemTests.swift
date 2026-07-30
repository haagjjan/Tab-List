import AppKit
import TabListCore
import XCTest
@testable import TabList

final class SwitcherDisplayItemTests: XCTestCase {
    func testAccessibilityLabelIncludesAppTitleAndPosition() {
        let item = displayItem(
            window: AppTestFixtures.window(
                1,
                applicationName: "Firefox",
                title: "Project plan"
            )
        )

        XCTAssertEqual(
            item.accessibilityLabel(position: 2, total: 8),
            "Firefox, Project plan — 2 of 8"
        )
    }

    func testAccessibilityLabelUsesLocalizedUntitledFallback() {
        let item = displayItem(
            window: AppTestFixtures.window(
                1,
                applicationName: "TextEdit",
                title: ""
            )
        )

        XCTAssertEqual(
            item.accessibilityLabel(position: 1, total: 3),
            "TextEdit, Untitled window — 1 of 3"
        )
    }

    func testAccessibilityLabelAnnouncesEveryRelevantWindowState() {
        let item = displayItem(
            window: AppTestFixtures.window(
                1,
                applicationName: "Preview",
                title: "Contract",
                isMinimized: true,
                isFullscreen: true
            )
        )

        XCTAssertEqual(
            item.accessibilityLabel(position: 3, total: 3),
            "Preview, Contract, minimized, full screen — 3 of 3"
        )
    }

    private func displayItem(
        window: WindowRecord
    ) -> SwitcherDisplayItem {
        SwitcherDisplayItem(
            window: window,
            icon: NSImage(size: NSSize(width: 32, height: 32)),
            thumbnail: nil
        )
    }
}
