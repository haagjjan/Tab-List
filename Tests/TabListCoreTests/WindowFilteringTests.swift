import Testing
@testable import TabListCore

@Suite
struct WindowFilteringTests {
    @Test
    func testDefaultSettingsIncludeSupportedWindowStates() {
        let windows = [
            TestFixtures.window(1, isMinimized: true),
            TestFixtures.window(2, isHidden: true),
            TestFixtures.window(3, isFullscreen: true),
        ]
        let context = WindowFilterContext(
            visibleSpaceIDs: [1],
            pointerDisplayID: 10
        )

        XCTAssertEqual(
            WindowFilter.filter(
                windows,
                settings: .default,
                context: context
            ).map(\.id),
            windows.map(\.id)
        )
    }

    @Test
    func testStateFiltersExcludeOnlyRequestedStates() {
        var settings = SettingsV1.default
        settings.includeMinimized = false
        settings.includeHiddenApps = false
        settings.includeFullscreen = false
        let ordinary = TestFixtures.window(1)
        let windows = [
            ordinary,
            TestFixtures.window(2, isMinimized: true),
            TestFixtures.window(3, isHidden: true),
            TestFixtures.window(4, isFullscreen: true),
        ]
        let context = WindowFilterContext(
            visibleSpaceIDs: [1],
            pointerDisplayID: 10
        )

        XCTAssertEqual(
            WindowFilter.filter(
                windows,
                settings: settings,
                context: context
            ),
            [ordinary]
        )
    }

    @Test
    func testNonstandardAndExcludedApplicationsAreRejected() {
        var settings = SettingsV1.default
        settings.excludedBundleIdentifiers = ["COM.EXAMPLE.APP"]
        let excluded = TestFixtures.window(1)
        let nonstandard = TestFixtures.window(
            2,
            bundleIdentifier: "com.other.App",
            isStandardWindow: false
        )
        let context = WindowFilterContext(
            visibleSpaceIDs: [1],
            pointerDisplayID: 10
        )

        XCTAssertFalse(
            WindowFilter.includes(
                excluded,
                settings: settings,
                context: context
            )
        )
        XCTAssertFalse(
            WindowFilter.includes(
                nonstandard,
                settings: settings,
                context: context
            )
        )
    }

    @Test
    func testUnresolvedWindowIdentityIsNeverSelectable() {
        let unresolved = TestFixtures.window(1, isActionable: false)

        XCTAssertFalse(
            WindowFilter.includes(
                unresolved,
                settings: .default,
                context: WindowFilterContext(
                    visibleSpaceIDs: [1],
                    pointerDisplayID: 10
                )
            )
        )
    }

    @Test
    func testVisibleSpaceScopeRequiresAnIntersectingKnownSpace() {
        var settings = SettingsV1.default
        settings.spaceScope = .visibleSpaces
        let visible = TestFixtures.window(1, spaceIDs: [1, 2])
        let hidden = TestFixtures.window(2, spaceIDs: [3])
        let unknown = TestFixtures.window(3, spaceIDs: [])
        let context = WindowFilterContext(
            visibleSpaceIDs: [2],
            pointerDisplayID: nil
        )

        XCTAssertEqual(
            WindowFilter.filter(
                [visible, hidden, unknown],
                settings: settings,
                context: context
            ),
            [visible]
        )
    }

    @Test
    func testPointerScreenScopeUsesPointerDisplayWhenKnown() {
        var settings = SettingsV1.default
        settings.screenScope = .pointerScreen
        let local = TestFixtures.window(1, displayID: 10)
        let remote = TestFixtures.window(2, displayID: 20)
        let unknown = TestFixtures.window(3, displayID: nil)

        XCTAssertEqual(
            WindowFilter.filter(
                [local, remote, unknown],
                settings: settings,
                context: WindowFilterContext(
                    visibleSpaceIDs: [1],
                    pointerDisplayID: 10
                )
            ),
            [local]
        )
    }

    @Test
    func testUnknownPointerDisplayFailsOpenInsteadOfEmptyingSwitcher() {
        var settings = SettingsV1.default
        settings.screenScope = .pointerScreen
        let windows = [
            TestFixtures.window(1, displayID: 10),
            TestFixtures.window(2, displayID: 20),
        ]

        XCTAssertEqual(
            WindowFilter.filter(
                windows,
                settings: settings,
                context: WindowFilterContext(
                    visibleSpaceIDs: [1],
                    pointerDisplayID: nil
                )
            ),
            windows
        )
    }

    @Test
    func testSelectionPipelineFiltersThenSortsByWindowMRU() {
        let older = TestFixtures.window(1, focusSequence: 10)
        let newest = TestFixtures.window(2, focusSequence: 30)
        let excluded = TestFixtures.window(
            3,
            isStandardWindow: false,
            focusSequence: 100
        )
        let snapshot = WindowSnapshot(
            generation: 1,
            windows: [older, excluded, newest],
            visibleSpaceIDs: [1]
        )

        XCTAssertEqual(
            WindowSelectionPipeline.candidates(
                from: snapshot,
                settings: .default,
                pointerDisplayID: 10
            ),
            [newest, older]
        )
    }

    @Test
    func testSelectionPipelineKeepsEachSameApplicationWindowAndItsTitle() {
        let browserWindows = [
            TestFixtures.window(
                1,
                bundleIdentifier: "org.mozilla.firefox",
                applicationName: "Firefox",
                title: "Project plan",
                focusSequence: 10
            ),
            TestFixtures.window(
                2,
                bundleIdentifier: "org.mozilla.firefox",
                applicationName: "Firefox",
                title: "Documentation",
                focusSequence: 30
            ),
            TestFixtures.window(
                3,
                bundleIdentifier: "org.mozilla.firefox",
                applicationName: "Firefox",
                title: "Project plan",
                focusSequence: 20
            ),
        ]
        let snapshot = WindowSnapshot(
            generation: 1,
            windows: browserWindows,
            visibleSpaceIDs: [1]
        )

        let candidates = WindowSelectionPipeline.candidates(
            from: snapshot,
            settings: .default,
            pointerDisplayID: 10
        )

        XCTAssertEqual(candidates.map(\.id.windowID), [2, 3, 1])
        XCTAssertEqual(
            candidates.map(\.windowTitle),
            ["Documentation", "Project plan", "Project plan"]
        )
    }

    @Test
    func testCombinedVisibleSpaceAndPointerScreenScopesRequireBoth() {
        var settings = SettingsV1.default
        settings.spaceScope = .visibleSpaces
        settings.screenScope = .pointerScreen
        let eligible = TestFixtures.window(
            1,
            spaceIDs: [2],
            displayID: 20
        )
        let wrongSpace = TestFixtures.window(
            2,
            spaceIDs: [3],
            displayID: 20
        )
        let wrongScreen = TestFixtures.window(
            3,
            spaceIDs: [2],
            displayID: 30
        )

        XCTAssertEqual(
            WindowFilter.filter(
                [eligible, wrongSpace, wrongScreen],
                settings: settings,
                context: WindowFilterContext(
                    visibleSpaceIDs: [2],
                    pointerDisplayID: 20
                )
            ),
            [eligible]
        )
    }
}
