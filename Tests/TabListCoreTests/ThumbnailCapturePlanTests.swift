import Testing
@testable import TabListCore

@Suite
struct ThumbnailCapturePlanTests {
    @Test
    func testSeparatesImmediateVisibleAndOffscreenWindows() {
        let keys = (1...6).map(windowKey)

        let plan = ThumbnailCapturePlan(
            allKeys: keys,
            priorityKeys: [keys[2], keys[1], keys[3]],
            visibleKeys: [keys[0], keys[1], keys[4]]
        )

        XCTAssertEqual(plan.immediate, [keys[2], keys[1], keys[3]])
        XCTAssertEqual(plan.visible, [keys[0], keys[4]])
        XCTAssertEqual(plan.remaining, [keys[5]])
    }

    @Test
    func testDropsDuplicatesAndUnknownKeysWithoutReordering() {
        let keys = (1...3).map(windowKey)
        let unknown = windowKey(99)

        let plan = ThumbnailCapturePlan(
            allKeys: [keys[0], keys[1], keys[0], keys[2]],
            priorityKeys: [unknown, keys[1], keys[1]],
            visibleKeys: [keys[2], unknown, keys[0]]
        )

        XCTAssertEqual(plan.immediate, [keys[1]])
        XCTAssertEqual(plan.visible, [keys[2], keys[0]])
        XCTAssertEqual(plan.remaining, [])
    }

    @Test
    func testEmptyInputsProduceEmptyPlan() {
        let plan = ThumbnailCapturePlan(
            allKeys: [],
            priorityKeys: [],
            visibleKeys: []
        )

        XCTAssertTrue(plan.isEmpty)
    }

    private func windowKey(_ id: Int) -> WindowKey {
        WindowKey(pid: 42, windowID: UInt32(id))
    }
}
