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
    func testRenderedContentIdentityAvoidsUnchangedRowReloads() {
        let window = AppTestFixtures.window(1, title: "Project plan")
        let icon = NSImage(size: NSSize(width: 32, height: 32))

        XCTAssertTrue(
            SwitcherDisplayItem(window: window, icon: icon)
                .hasSameRenderedContent(
                    as: SwitcherDisplayItem(window: window, icon: icon)
                )
        )
    }

    @Test
    func testRenderedContentIdentityDetectsMetadataAndImageChanges() {
        let window = AppTestFixtures.window(1, title: "Project plan")
        let icon = NSImage(size: NSSize(width: 32, height: 32))
        let first = SwitcherDisplayItem(window: window, icon: icon)

        XCTAssertFalse(
            first.hasSameRenderedContent(
                as: SwitcherDisplayItem(
                    window: AppTestFixtures.window(1, title: "Retitled"),
                    icon: icon
                )
            )
        )
        XCTAssertFalse(
            first.hasSameRenderedContent(
                as: SwitcherDisplayItem(
                    window: window,
                    icon: NSImage(size: NSSize(width: 32, height: 32))
                )
            )
        )
    }

    @Test
    func testReloadPlannerReloadsEveryRowWhenTheCountChanges() {
        let first = displayItem(window: AppTestFixtures.window(1))
        let second = displayItem(window: AppTestFixtures.window(2))

        XCTAssertEqual(
            SwitcherDisplayReloadPlanner.changedRows(
                previous: [first, second, displayItem(
                    window: AppTestFixtures.window(3)
                )],
                next: [first, second]
            ),
            IndexSet([0, 1])
        )
    }

    @Test
    func testReloadPlannerReloadsOnlyRowsWhoseContentChanged() {
        let first = displayItem(window: AppTestFixtures.window(1))
        let second = displayItem(window: AppTestFixtures.window(2))
        let retitledSecond = displayItem(
            window: AppTestFixtures.window(2, title: "Retitled"),
            icon: second.icon
        )

        XCTAssertEqual(
            SwitcherDisplayReloadPlanner.changedRows(
                previous: [first, second],
                next: [first, retitledSecond]
            ),
            IndexSet(integer: 1)
        )
    }

    @Test
    func testReloadPlannerLeavesUnchangedRowsAlone() {
        let first = displayItem(window: AppTestFixtures.window(1))
        let second = displayItem(window: AppTestFixtures.window(2))

        XCTAssertTrue(
            SwitcherDisplayReloadPlanner.changedRows(
                previous: [first, second],
                next: [first, second]
            ).isEmpty
        )
    }

    private func displayItem(
        window: WindowRecord,
        icon: NSImage = NSImage(size: NSSize(width: 32, height: 32))
    ) -> SwitcherDisplayItem {
        SwitcherDisplayItem(window: window, icon: icon)
    }
}

@Suite
struct SwitcherDisplayItemStateTests {
    private func item(_ window: WindowRecord) -> SwitcherDisplayItem {
        SwitcherDisplayItem(
            window: window,
            icon: NSImage(size: NSSize(width: 32, height: 32))
        )
    }

    @Test
    func testAnOrdinaryWindowShowsNoStateBadges() {
        XCTAssertTrue(item(AppTestFixtures.window(1)).stateDescriptions.isEmpty)
    }

    @Test
    func testEveryStateIsSurfacedInAStableOrder() {
        let states = item(
            AppTestFixtures.window(
                1,
                isMinimized: true,
                isHidden: true,
                isFullscreen: true
            )
        ).stateDescriptions

        XCTAssertEqual(states, ["Minimized", "Hidden", "Full Screen"])
    }

    @Test
    func testAnEmptyTitleFallsBackToAReadableLabel() {
        XCTAssertEqual(
            item(AppTestFixtures.window(1, title: "")).title,
            "Untitled window"
        )
    }

    @Test
    func testARealTitleIsUsedVerbatim() {
        XCTAssertEqual(
            item(AppTestFixtures.window(1, title: "  Draft  ")).title,
            "  Draft  "
        )
    }

    @Test
    func testAHiddenApplicationIsAnnouncedToVoiceOver() {
        XCTAssertEqual(
            item(
                AppTestFixtures.window(
                    1,
                    applicationName: "Mail",
                    title: "Inbox",
                    isHidden: true
                )
            ).accessibilityLabel(position: 1, total: 2),
            "Mail, Inbox, hidden — 1 of 2"
        )
    }
}
