import AppKit
import TabListCore
import Testing
@testable import TabList

@Suite
struct SwitcherDisplayItemTests {
    @Test
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

    @Test
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

    @Test
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

    @Test
    func testRenderedContentIdentityAvoidsUnchangedCellReloads() {
        let window = AppTestFixtures.window(1, title: "Project plan")
        let icon = NSImage(size: NSSize(width: 32, height: 32))
        let first = SwitcherDisplayItem(
            window: window,
            icon: icon,
            thumbnail: nil
        )
        let same = SwitcherDisplayItem(
            window: window,
            icon: icon,
            thumbnail: nil
        )

        XCTAssertTrue(first.hasSameRenderedContent(as: same))
    }

    @Test
    func testRenderedContentIdentityDetectsMetadataAndImageChanges() {
        let window = AppTestFixtures.window(1, title: "Project plan")
        let icon = NSImage(size: NSSize(width: 32, height: 32))
        let first = SwitcherDisplayItem(
            window: window,
            icon: icon,
            thumbnail: nil
        )
        let changedWindow = SwitcherDisplayItem(
            window: AppTestFixtures.window(1, title: "Retitled"),
            icon: icon,
            thumbnail: nil
        )
        let changedIcon = SwitcherDisplayItem(
            window: window,
            icon: NSImage(size: NSSize(width: 32, height: 32)),
            thumbnail: nil
        )

        XCTAssertFalse(first.hasSameRenderedContent(as: changedWindow))
        XCTAssertFalse(first.hasSameRenderedContent(as: changedIcon))
    }

    @Test
    func testReloadPlannerRefreshesAccessibilityPositionAfterReorder() {
        let first = displayItem(window: AppTestFixtures.window(1))
        let second = displayItem(window: AppTestFixtures.window(2))

        XCTAssertEqual(
            SwitcherDisplayReloadPlanner.keys(
                previous: [first, second],
                next: [second, first],
                forceReload: false
            ),
            [first.window.id, second.window.id]
        )
    }

    @Test
    func testReloadPlannerRefreshesRetainedItemsAfterCountChange() {
        let first = displayItem(window: AppTestFixtures.window(1))
        let second = displayItem(window: AppTestFixtures.window(2))
        let third = displayItem(window: AppTestFixtures.window(3))

        XCTAssertEqual(
            SwitcherDisplayReloadPlanner.keys(
                previous: [first, second, third],
                next: [first, second],
                forceReload: false
            ),
            [first.window.id, second.window.id]
        )
    }

    @Test
    func testReloadPlannerLeavesUnchangedPositionsAlone() {
        let first = displayItem(window: AppTestFixtures.window(1))
        let second = displayItem(window: AppTestFixtures.window(2))

        XCTAssertTrue(
            SwitcherDisplayReloadPlanner.keys(
                previous: [first, second],
                next: [first, second],
                forceReload: false
            ).isEmpty
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
