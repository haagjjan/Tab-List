import Testing
@testable import TabListCore

@Suite
struct BoundedCostLRUTests {
    @Test
    func testCostLimitEvictsLeastRecentlyUsedEntry() {
        var cache = BoundedCostLRU<Int>(
            totalCostLimit: 10,
            countLimit: 10
        )
        _ = cache.insert(1, cost: 4)
        _ = cache.insert(2, cost: 4)
        cache.touch(1)

        let insertion = cache.insert(3, cost: 4)

        XCTAssertEqual(insertion.evicted, [2])
        XCTAssertTrue(cache.contains(1))
        XCTAssertTrue(cache.contains(3))
        XCTAssertEqual(cache.totalCost, 8)
    }

    @Test
    func testCountLimitEvictsBeforeInsertion() {
        var cache = BoundedCostLRU<Int>(
            totalCostLimit: 100,
            countLimit: 2
        )
        _ = cache.insert(1, cost: 1)
        _ = cache.insert(2, cost: 1)

        let insertion = cache.insert(3, cost: 1)

        XCTAssertEqual(insertion.evicted, [1])
        XCTAssertEqual(cache.count, 2)
    }

    @Test
    func testRejectedOversizeEntryDoesNotReplaceExistingValue() {
        var cache = BoundedCostLRU<Int>(
            totalCostLimit: 8,
            countLimit: 2
        )
        _ = cache.insert(1, cost: 4)

        let insertion = cache.insert(1, cost: 9)

        XCTAssertFalse(insertion.accepted)
        XCTAssertTrue(cache.contains(1))
        XCTAssertEqual(cache.totalCost, 4)
    }

    @Test
    func testReplacementUpdatesCostWithoutGrowingCount() {
        var cache = BoundedCostLRU<Int>(
            totalCostLimit: 10,
            countLimit: 2
        )
        _ = cache.insert(1, cost: 4)
        _ = cache.insert(1, cost: 6)

        XCTAssertEqual(cache.count, 1)
        XCTAssertEqual(cache.totalCost, 6)
    }
}
