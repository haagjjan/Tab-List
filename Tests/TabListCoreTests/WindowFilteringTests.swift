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
        var settings = TabListSettings.default
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
    func testExcludedApplicationsAreRejectedCaseInsensitively() {
        var settings = TabListSettings.default
        settings.excludedBundleIdentifiers = ["COM.EXAMPLE.APP"]
        let excluded = TestFixtures.window(1)
        let other = TestFixtures.window(2, bundleIdentifier: "com.other.App")
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
        XCTAssertTrue(
            WindowFilter.includes(other, settings: settings, context: context)
        )
    }

    @Test
    func testVisibleSpaceScopeExcludesOtherSpacesButKeepsUnknownMembership() {
        var settings = TabListSettings.default
        settings.spaceScope = .visibleSpaces
        let visible = TestFixtures.window(1, spaceIDs: [1, 2])
        let elsewhere = TestFixtures.window(2, spaceIDs: [3])
        let unknown = TestFixtures.window(3, spaceIDs: [])
        let context = WindowFilterContext(
            visibleSpaceIDs: [2],
            pointerDisplayID: nil
        )

        XCTAssertEqual(
            WindowFilter.filter(
                [visible, elsewhere, unknown],
                settings: settings,
                context: context
            ),
            [visible, unknown]
        )
    }

    @Test
    func testPointerScreenScopeExcludesOtherDisplaysButKeepsUnknownOnes() {
        var settings = TabListSettings.default
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
            [local, unknown]
        )
    }

    @Test
    func testUnknownPointerDisplayFailsOpenInsteadOfEmptyingSwitcher() {
        var settings = TabListSettings.default
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
        var settings = TabListSettings.default
        settings.excludedBundleIdentifiers = ["com.excluded.App"]
        let older = TestFixtures.window(1, focusSequence: 10)
        let newest = TestFixtures.window(2, focusSequence: 30)
        let excluded = TestFixtures.window(
            3,
            bundleIdentifier: "com.excluded.App",
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
                settings: settings,
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
        var settings = TabListSettings.default
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

@Suite
struct WindowFilterEdgeCaseTests {
    private let context = WindowFilterContext(
        visibleSpaceIDs: [1],
        pointerDisplayID: 10
    )

    @Test
    func testAWindowWithoutABundleIdentifierIsNeverExcludedByName() {
        var settings = TabListSettings.default
        settings.excludedBundleIdentifiers = ["com.example.App"]

        XCTAssertTrue(
            WindowFilter.includes(
                TestFixtures.window(1, bundleIdentifier: nil),
                settings: settings,
                context: context
            )
        )
    }

    @Test
    func testAnEmptyVisibleSpaceSetDoesNotEmptyTheSwitcher() {
        var settings = TabListSettings.default
        settings.spaceScope = .visibleSpaces
        let windows = [
            TestFixtures.window(1, spaceIDs: [4]),
            TestFixtures.window(2, spaceIDs: [5]),
        ]

        XCTAssertEqual(
            WindowFilter.filter(
                windows,
                settings: settings,
                context: WindowFilterContext(
                    visibleSpaceIDs: [],
                    pointerDisplayID: nil
                )
            ),
            windows
        )
    }

    @Test
    func testEveryStateFilterCanBeCombined() {
        var settings = TabListSettings.default
        settings.includeMinimized = false
        settings.includeFullscreen = false
        let mixed = TestFixtures.window(
            1,
            isMinimized: true,
            isFullscreen: true
        )

        XCTAssertFalse(
            WindowFilter.includes(
                mixed,
                settings: settings,
                context: context
            )
        )
    }

    @Test
    func testFilteringAnEmptyListIsEmptyRatherThanUndefined() {
        XCTAssertTrue(
            WindowFilter.filter(
                [],
                settings: .default,
                context: context
            ).isEmpty
        )
    }

    @Test
    func testThePipelineIsStableForWindowsThatHaveNeverBeenFocused() {
        let windows = (1 ... 4).map {
            TestFixtures.window(UInt32($0), focusSequence: 0)
        }
        let snapshot = WindowSnapshot(
            generation: 1,
            windows: windows,
            visibleSpaceIDs: [1]
        )

        XCTAssertEqual(
            WindowSelectionPipeline.candidates(
                from: snapshot,
                settings: .default,
                pointerDisplayID: 10
            ).map(\.id),
            windows.map(\.id)
        )
    }
}
