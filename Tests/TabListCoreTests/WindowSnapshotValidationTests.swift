import CoreGraphics
import Testing
@testable import TabListCore

@Suite
struct WindowSnapshotValidationTests {
    @Test
    func testAcceptsUniqueProcessScopedWindowsWithFiniteGeometry() {
        let snapshot = WindowSnapshot(
            generation: 1,
            windows: [
                TestFixtures.window(1),
                TestFixtures.window(1, pid: 200),
            ],
            visibleSpaceIDs: [1]
        )

        XCTAssertTrue(WindowSnapshotValidator.isValid(snapshot))
    }

    @Test
    func testRejectsDuplicateProcessScopedWindowKeys() {
        let window = TestFixtures.window(1)
        let snapshot = WindowSnapshot(
            generation: 1,
            windows: [window, window],
            visibleSpaceIDs: [1]
        )

        XCTAssertFalse(WindowSnapshotValidator.isValid(snapshot))
    }

    @Test
    func testRejectsInvalidIdentityAndGeometry() {
        let zeroPID = replacing(
            TestFixtures.window(1),
            key: WindowKey(pid: 0, windowID: 1)
        )
        let zeroWindowID = replacing(
            TestFixtures.window(2),
            key: WindowKey(pid: 100, windowID: 0)
        )
        let invalidBounds = replacing(
            TestFixtures.window(3),
            bounds: CGRect(
                x: 0,
                y: 0,
                width: CGFloat.infinity,
                height: 100
            )
        )

        for window in [zeroPID, zeroWindowID, invalidBounds] {
            let snapshot = WindowSnapshot(
                generation: 1,
                windows: [window],
                visibleSpaceIDs: [1]
            )
            XCTAssertFalse(WindowSnapshotValidator.isValid(snapshot))
        }
    }

    private func replacing(
        _ window: WindowRecord,
        key: WindowKey? = nil,
        bounds: CGRect? = nil
    ) -> WindowRecord {
        WindowRecord(
            id: key ?? window.id,
            bundleIdentifier: window.bundleIdentifier,
            applicationName: window.applicationName,
            bundleURL: window.bundleURL,
            windowTitle: window.windowTitle,
            bounds: bounds ?? window.bounds,
            spaceIDs: window.spaceIDs,
            displayID: window.displayID,
            isMinimized: window.isMinimized,
            isHidden: window.isHidden,
            isFullscreen: window.isFullscreen,
            isStandardWindow: window.isStandardWindow,
            isClosable: window.isClosable,
            lastFocusSequence: window.lastFocusSequence,
            incarnation: window.incarnation
        )
    }
}
