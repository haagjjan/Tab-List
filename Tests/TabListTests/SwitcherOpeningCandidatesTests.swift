import TabListCore
import XCTest
@testable import TabList

final class SwitcherOpeningCandidatesTests: XCTestCase {
    func testMissingCachedSnapshotProducesNoOpeningBatch() {
        XCTAssertNil(
            SwitcherOpeningCandidates.cached(
                from: nil,
                settings: .default,
                pointerDisplayID: 10
            )
        )
    }

    func testCachedSnapshotImmediatelyProducesFilteredWindowMRUCandidates() {
        var settings = SettingsV1.default
        settings.screenScope = .pointerScreen

        let current = AppTestFixtures.window(
            1,
            applicationName: "Firefox",
            title: "Current",
            displayID: 10,
            focusSequence: 30
        )
        let previous = AppTestFixtures.window(
            2,
            applicationName: "Firefox",
            title: "Previous",
            displayID: 10,
            focusSequence: 20
        )
        let otherScreen = AppTestFixtures.window(
            3,
            applicationName: "Firefox",
            title: "Other screen",
            displayID: 20,
            focusSequence: 40
        )
        let cached = WindowSnapshot(
            generation: 17,
            windows: [previous, otherScreen, current],
            visibleSpaceIDs: [1]
        )

        let opening = SwitcherOpeningCandidates.cached(
            from: cached,
            settings: settings,
            pointerDisplayID: 10
        )

        XCTAssertEqual(opening?.snapshotGeneration, 17)
        XCTAssertEqual(opening?.orderedItems, [current, previous])
    }

    func testOpeningBatchDoesNotCollapseSameApplicationWindows() {
        let first = AppTestFixtures.window(
            1,
            bundleIdentifier: "org.mozilla.firefox",
            applicationName: "Firefox",
            title: "One",
            focusSequence: 10
        )
        let second = AppTestFixtures.window(
            2,
            bundleIdentifier: "org.mozilla.firefox",
            applicationName: "Firefox",
            title: "Two",
            focusSequence: 20
        )
        let snapshot = WindowSnapshot(
            generation: 5,
            windows: [first, second],
            visibleSpaceIDs: [1]
        )

        let opening = SwitcherOpeningCandidates.make(
            from: snapshot,
            settings: .default,
            pointerDisplayID: 10
        )

        XCTAssertEqual(opening.orderedItems, [second, first])
    }

    func testOpeningPromotesConfirmedCurrentWindowAheadOfStaleMRU() {
        let staleNewest = AppTestFixtures.window(
            1,
            title: "Previously focused",
            focusSequence: 30
        )
        let current = AppTestFixtures.window(
            2,
            title: "Actually focused",
            focusSequence: 20
        )
        let older = AppTestFixtures.window(
            3,
            title: "Older",
            focusSequence: 10
        )
        let snapshot = WindowSnapshot(
            generation: 8,
            windows: [staleNewest, current, older],
            visibleSpaceIDs: [1]
        )

        let opening = SwitcherOpeningCandidates.make(
            from: snapshot,
            settings: .default,
            pointerDisplayID: 10,
            currentWindowKey: current.id
        )

        XCTAssertEqual(
            opening.orderedItems,
            [current, staleNewest, older]
        )
    }
}
