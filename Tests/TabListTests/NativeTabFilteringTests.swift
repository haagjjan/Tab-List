import CoreGraphics
import TabListCore
import Testing
@testable import TabList

@Suite
struct NativeTabFilteringTests {
    @Test
    func testExplicitNativeTabGroupCollapsesWhenEntireContainerIsOffscreen() {
        let activeTab = AppTestFixtures.window(
            1,
            title: "Active terminal tab",
            bounds: sharedBounds,
            spaceIDs: []
        )
        let inactiveTab = AppTestFixtures.window(
            2,
            title: "Inactive terminal tab",
            bounds: sharedBounds,
            spaceIDs: []
        )
        let metadata = [
            activeTab.id: accessibilityMetadata(
                title: activeTab.windowTitle,
                isMain: true,
                nativeTabGroupID: 42
            ),
            inactiveTab.id: accessibilityMetadata(
                title: inactiveTab.windowTitle,
                nativeTabGroupID: 42
            ),
        ]

        XCTAssertEqual(
            filter(
                [activeTab, inactiveTab],
                onscreenKeys: [],
                accessibilityMetadata: metadata
            ),
            [activeTab]
        )
    }

    @Test
    func testSingleMappedTabContainerCollapsesUnmappedNativeMembers() {
        let activeTab = AppTestFixtures.window(
            1,
            title: "Selected terminal tab",
            bounds: sharedBounds,
            spaceIDs: []
        )
        let unmappedTab = AppTestFixtures.window(
            2,
            title: "",
            bounds: sharedBounds,
            spaceIDs: []
        )

        XCTAssertEqual(
            filter(
                [activeTab, unmappedTab],
                onscreenKeys: [],
                accessibilityMetadata: [
                    activeTab.id: accessibilityMetadata(
                        title: activeTab.windowTitle,
                        nativeTabGroupID: 42,
                        nativeTabCount: 2
                    ),
                ]
            ),
            [activeTab]
        )
    }

    @Test
    func testSeparateSameGeometryWindowsWithDifferentTabGroupsRemain() {
        let first = AppTestFixtures.window(1, bounds: sharedBounds)
        let second = AppTestFixtures.window(2, bounds: sharedBounds)
        let metadata = [
            first.id: accessibilityMetadata(nativeTabGroupID: 10),
            second.id: accessibilityMetadata(nativeTabGroupID: 20),
        ]

        XCTAssertEqual(
            filter(
                [first, second],
                onscreenKeys: [],
                accessibilityMetadata: metadata
            ),
            [first, second]
        )
    }

    @Test
    func testPreferredTitleIgnoresBlankAccessibilityValue() {
        XCTAssertEqual(
            PublicWindowInventory.preferredWindowTitle(
                accessibilityTitle: "  ",
                windowServerTitle: "Firefox — Project"
            ),
            "Firefox — Project"
        )
        XCTAssertEqual(
            PublicWindowInventory.preferredWindowTitle(
                accessibilityTitle: "Active web tab",
                windowServerTitle: "Fallback"
            ),
            "Active web tab"
        )
    }

    @Test
    func testRemovesOnlyInactiveNativeTabMemberFromMatchingContainer() {
        let visible = AppTestFixtures.window(
            1,
            title: "Visible tab",
            bounds: sharedBounds,
            spaceIDs: [1]
        )
        let inactive = AppTestFixtures.window(
            2,
            title: "Inactive tab has a different title",
            bounds: sharedBounds,
            spaceIDs: [1]
        )
        let secondInactive = AppTestFixtures.window(
            3,
            title: "Another inactive tab",
            bounds: sharedBounds,
            spaceIDs: [1]
        )

        let filtered = filter(
            [visible, inactive, secondInactive],
            onscreenKeys: [visible.id]
        )

        XCTAssertEqual(filtered, [visible])
    }

    @Test
    func testRetainsMinimizedMemberOfMatchingContainer() {
        let visible = AppTestFixtures.window(
            1,
            bounds: sharedBounds
        )
        let minimized = AppTestFixtures.window(
            2,
            bounds: sharedBounds,
            isMinimized: true
        )

        XCTAssertEqual(
            filter([visible, minimized], onscreenKeys: [visible.id]),
            [visible, minimized]
        )
    }

    @Test
    func testDoesNotCollapseSeparateWindowsWithSameAppAndGeometry() {
        let first = AppTestFixtures.window(
            1,
            bounds: sharedBounds
        )
        let second = AppTestFixtures.window(
            2,
            bounds: sharedBounds
        )

        XCTAssertEqual(
            filter([first, second], onscreenKeys: [first.id, second.id]),
            [first, second]
        )
    }

    @Test
    func testDoesNotGroupAcrossProcessesSpacesOrGeometry() {
        let visible = AppTestFixtures.window(
            1,
            pid: 100,
            bounds: sharedBounds,
            spaceIDs: [1]
        )
        let otherProcess = AppTestFixtures.window(
            2,
            pid: 200,
            bounds: sharedBounds,
            spaceIDs: [1]
        )
        let otherSpace = AppTestFixtures.window(
            3,
            pid: 100,
            bounds: sharedBounds,
            spaceIDs: [2]
        )
        let otherGeometry = AppTestFixtures.window(
            4,
            pid: 100,
            bounds: sharedBounds.offsetBy(dx: 8, dy: 0),
            spaceIDs: [1]
        )

        XCTAssertEqual(
            filter(
                [visible, otherProcess, otherSpace, otherGeometry],
                onscreenKeys: [visible.id]
            ),
            [visible, otherProcess, otherSpace, otherGeometry]
        )
    }

    @Test
    func testAmbiguousGroupWithoutExactlyOneVisibleMemberFailsOpen() {
        let first = AppTestFixtures.window(1, bounds: sharedBounds)
        let second = AppTestFixtures.window(2, bounds: sharedBounds)

        XCTAssertEqual(
            filter([first, second], onscreenKeys: []),
            [first, second]
        )
        XCTAssertEqual(
            filter([first, second], onscreenKeys: [first.id, second.id]),
            [first, second]
        )
    }

    @Test
    func testMissingCandidateMetadataFailsOpenAndPreservesOrdering() {
        let visible = AppTestFixtures.window(1, bounds: sharedBounds)
        let unknown = AppTestFixtures.window(2, bounds: sharedBounds)
        let candidates = [
            visible.id: AppTestFixtures.candidate(
                for: visible,
                isOnScreen: true
            ),
        ]

        XCTAssertEqual(
            PublicWindowInventory.removingInactiveNativeTabMembers(
                from: [unknown, visible],
                candidates: candidates
            ),
            [unknown, visible]
        )
    }

    @Test
    func testUnknownSpaceMembershipNeverCollapsesSameGeometryWindows() {
        let visible = AppTestFixtures.window(
            1,
            bounds: sharedBounds,
            spaceIDs: []
        )
        let offscreen = AppTestFixtures.window(
            2,
            bounds: sharedBounds,
            spaceIDs: []
        )

        XCTAssertEqual(
            filter([visible, offscreen], onscreenKeys: [visible.id]),
            [visible, offscreen]
        )
    }

    private let sharedBounds = CGRect(
        x: 120,
        y: 80,
        width: 1_000,
        height: 700
    )

    private func filter(
        _ windows: [WindowRecord],
        onscreenKeys: Set<WindowKey>,
        accessibilityMetadata: [
            WindowKey: AccessibilityWindowMetadata
        ] = [:]
    ) -> [WindowRecord] {
        let candidates = Dictionary(
            uniqueKeysWithValues: windows.map { window in
                (
                    window.id,
                    AppTestFixtures.candidate(
                        for: window,
                        isOnScreen: onscreenKeys.contains(window.id)
                    )
                )
            }
        )
        return PublicWindowInventory.removingInactiveNativeTabMembers(
            from: windows,
            candidates: candidates,
            accessibilityMetadata: accessibilityMetadata
        )
    }

    private func accessibilityMetadata(
        title: String? = nil,
        isMain: Bool = false,
        nativeTabGroupID: UInt64? = nil,
        nativeTabCount: Int = 0
    ) -> AccessibilityWindowMetadata {
        AccessibilityWindowMetadata(
            role: "AXWindow",
            subrole: "AXStandardWindow",
            title: title,
            bounds: sharedBounds,
            isMinimized: false,
            isFullscreen: false,
            isStandardWindow: true,
            isClosable: true,
            isMain: isMain,
            nativeTabGroupID: nativeTabGroupID,
            nativeTabCount: nativeTabCount
        )
    }
}

@Suite
struct WindowClosePolicyTests {
    @Test
    func testSeveralCanonicalWindowsCloseOnlyTargetWindow() {
        let record = AppTestFixtures.window(1)

        XCTAssertEqual(
            WindowClosePolicy.disposition(
                for: record,
                canonicalWindowCount: 3,
                tabListBundleIdentifier: "com.haagjjan.TabList"
            ),
            .closeWindow
        )
    }

    @Test
    func testLastCanonicalWindowGracefullyQuitsApplication() {
        let record = AppTestFixtures.window(1)

        XCTAssertEqual(
            WindowClosePolicy.disposition(
                for: record,
                canonicalWindowCount: 1,
                tabListBundleIdentifier: "com.haagjjan.TabList"
            ),
            .quitApplication
        )
    }

    @Test
    func testFinderRemainsCloseOnly() {
        var record = AppTestFixtures.window(1)
        record = WindowRecord(
            id: record.id,
            bundleIdentifier: "com.apple.finder",
            applicationName: record.applicationName,
            bundleURL: record.bundleURL,
            windowTitle: record.windowTitle,
            bounds: record.bounds,
            spaceIDs: record.spaceIDs,
            displayID: record.displayID,
            isMinimized: record.isMinimized,
            isHidden: record.isHidden,
            isFullscreen: record.isFullscreen,
            isStandardWindow: record.isStandardWindow,
            isClosable: record.isClosable,
            identitySource: record.identitySource,
            isActionable: record.isActionable,
            lastFocusSequence: record.lastFocusSequence
        )

        XCTAssertEqual(
            WindowClosePolicy.disposition(
                for: record,
                canonicalWindowCount: 1,
                tabListBundleIdentifier: "com.haagjjan.TabList"
            ),
            .closeWindow
        )
    }
}
