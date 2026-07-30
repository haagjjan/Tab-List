import Testing
@testable import TabList
import TabListCore

@Suite
struct BackgroundThumbnailRefreshTrackerTests {
    @Test
    func testRetriesFailuresAndSkipsRecentlyCapturedStableWindows() {
        let now = ContinuousClock().now
        let first = AppTestFixtures.window(1, title: "First")
        let second = AppTestFixtures.window(2, title: "Second")
        var tracker = BackgroundThumbnailRefreshTracker()

        XCTAssertEqual(
            tracker.candidates(
                from: [first, second],
                at: now,
                stableRefreshInterval: .seconds(300)
            ).map(\.id),
            [first.id, second.id]
        )

        tracker.recordCaptured(
            [first.id],
            from: [first, second],
            at: now
        )

        XCTAssertEqual(
            tracker.candidates(
                from: [first, second],
                at: now.advanced(by: .seconds(30)),
                stableRefreshInterval: .seconds(300)
            ).map(\.id),
            [second.id]
        )
    }

    @Test
    func testRefreshesStablePixelsPeriodicallyAndMetadataImmediately() {
        let now = ContinuousClock().now
        let original = AppTestFixtures.window(1, title: "Original")
        var tracker = BackgroundThumbnailRefreshTracker()
        tracker.recordCaptured([original.id], from: [original], at: now)

        XCTAssertTrue(
            tracker.candidates(
                from: [original],
                at: now.advanced(by: .seconds(299)),
                stableRefreshInterval: .seconds(300)
            ).isEmpty
        )
        XCTAssertEqual(
            tracker.candidates(
                from: [original],
                at: now.advanced(by: .seconds(300)),
                stableRefreshInterval: .seconds(300)
            ).map(\.id),
            [original.id]
        )

        var retitled = original
        retitled.windowTitle = "Changed"
        XCTAssertEqual(
            tracker.candidates(
                from: [retitled],
                at: now.advanced(by: .seconds(30)),
                stableRefreshInterval: .seconds(300)
            ).map(\.id),
            [original.id]
        )
    }

    @Test
    func testRemovedWindowsAreForgottenAndRecapturedIfTheyReturn() {
        let now = ContinuousClock().now
        let window = AppTestFixtures.window(1)
        var tracker = BackgroundThumbnailRefreshTracker()
        tracker.recordCaptured([window.id], from: [window], at: now)

        XCTAssertTrue(
            tracker.candidates(
                from: [],
                at: now,
                stableRefreshInterval: .seconds(300)
            ).isEmpty
        )
        XCTAssertEqual(
            tracker.candidates(
                from: [window],
                at: now.advanced(by: .seconds(1)),
                stableRefreshInterval: .seconds(300)
            ).map(\.id),
            [window.id]
        )
    }
}
