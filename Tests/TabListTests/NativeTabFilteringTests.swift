import CoreGraphics
import TabListCore
import XCTest
@testable import TabList

final class NativeTabFilteringTests: XCTestCase {
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
        onscreenKeys: Set<WindowKey>
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
            candidates: candidates
        )
    }
}
