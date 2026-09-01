import CoreGraphics
import TabListCore
import Testing
@testable import TabList

private actor ScriptedInventory: WindowInventoryProviding {
    private var remaining: [[WindowRecord]]
    private var focusedKey: WindowKey?
    private var discoveries = 0

    init(_ scripted: [[WindowRecord]], focusedKey: WindowKey? = nil) {
        remaining = scripted
        self.focusedKey = focusedKey
    }

    func discover() async -> WindowInventoryResult {
        discoveries += 1
        let windows = remaining.count > 1
            ? remaining.removeFirst()
            : (remaining.first ?? [])
        return WindowInventoryResult(windows: windows, visibleSpaceIDs: [1])
    }

    func currentFocusedWindowKey() async -> WindowKey? {
        focusedKey
    }

    func setFocusedKey(_ key: WindowKey?) {
        focusedKey = key
    }

    func discoveryCount() -> Int {
        discoveries
    }
}

@Suite
struct WindowRegistryLifecycleTests {
    @Test
    func testTheFirstSnapshotDiscoversEvenWhenNotForced() async {
        let inventory = ScriptedInventory([[AppTestFixtures.window(1)]])
        let registry = WindowRegistry(inventory: inventory)

        let snapshot = await registry.snapshot(forceRefreshIfStale: false)
        let discoveries = await inventory.discoveryCount()

        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(discoveries, 1)
    }

    @Test
    func testAFreshSnapshotIsReusedWithoutRediscovering() async {
        let inventory = ScriptedInventory([[AppTestFixtures.window(1)]])
        let registry = WindowRegistry(inventory: inventory, staleAfter: .seconds(60))

        _ = await registry.snapshot(forceRefreshIfStale: true)
        _ = await registry.snapshot(forceRefreshIfStale: true)
        let discoveries = await inventory.discoveryCount()

        XCTAssertEqual(discoveries, 1)
    }

    @Test
    func testInvalidationForcesTheNextSnapshotToRediscover() async {
        let inventory = ScriptedInventory([[AppTestFixtures.window(1)]])
        let registry = WindowRegistry(inventory: inventory, staleAfter: .seconds(60))

        _ = await registry.snapshot(forceRefreshIfStale: true)
        await registry.invalidate()
        _ = await registry.snapshot(forceRefreshIfStale: false)
        let discoveries = await inventory.discoveryCount()

        XCTAssertEqual(discoveries, 2)
    }

    @Test
    func testASurvivingWindowKeepsItsIncarnationAcrossRefreshes() async {
        let window = AppTestFixtures.window(1)
        let inventory = ScriptedInventory([[window], [window]])
        let registry = WindowRegistry(inventory: inventory)

        _ = await registry.refresh()
        let first = await registry.record(for: window.id)?.incarnation
        _ = await registry.refresh()
        let second = await registry.record(for: window.id)?.incarnation

        XCTAssertNotEqual(first, nil)
        XCTAssertEqual(first, second)
    }

    @Test
    func testARecycledWindowIdentifierNeverInheritsTheClosedWindow() async {
        let window = AppTestFixtures.window(1)
        let inventory = ScriptedInventory([[window], [], [window]])
        let registry = WindowRegistry(inventory: inventory)

        _ = await registry.refresh()
        let original = await registry.record(for: window.id)
        _ = await registry.refresh()
        let whileClosed = await registry.record(for: window.id)
        _ = await registry.refresh()
        let recycled = await registry.record(for: window.id)

        XCTAssertNil(whileClosed)
        XCTAssertNotEqual(original?.incarnation, recycled?.incarnation)
        let target = original.map(WindowActionTarget.init)
        if let target, let recycled {
            XCTAssertFalse(target.matches(recycled))
        } else {
            XCTFail("The window should be rediscovered with a new identity.")
        }
    }

    @Test
    func testClosedWindowsLeaveTheSnapshot() async {
        let first = AppTestFixtures.window(1)
        let second = AppTestFixtures.window(2)
        let inventory = ScriptedInventory([[first, second], [first]])
        let registry = WindowRegistry(inventory: inventory)

        _ = await registry.refresh()
        let after = await registry.refresh()
        let closedRecord = await registry.record(for: second.id)

        XCTAssertEqual(after.windows.map(\.id), [first.id])
        XCTAssertNil(closedRecord)
    }

    @Test
    func testTheGenerationAdvancesOnEveryAppliedRefresh() async {
        let inventory = ScriptedInventory([[AppTestFixtures.window(1)]])
        let registry = WindowRegistry(inventory: inventory)

        let first = await registry.refresh()
        let second = await registry.refresh()

        XCTAssertGreaterThan(second.generation, first.generation)
    }

    @Test
    func testAConfirmedFocusPromotesItsWindowInMRUOrder() async {
        let first = AppTestFixtures.window(1)
        let second = AppTestFixtures.window(2)
        let inventory = ScriptedInventory([[first, second]])
        let registry = WindowRegistry(inventory: inventory)
        _ = await registry.refresh()

        await registry.noteFocused(second.id)
        let snapshot = await registry.snapshot(forceRefreshIfStale: false)
        let lastFocused = await registry.lastFocusedWindowKey()

        XCTAssertEqual(
            MRUOrdering.sorted(snapshot.windows).map(\.id),
            [second.id, first.id]
        )
        XCTAssertEqual(lastFocused, second.id)
    }

    @Test
    func testFocusOnAnUnknownWindowIsNotRecordedAsHistory() async {
        let inventory = ScriptedInventory([[AppTestFixtures.window(1)]])
        let registry = WindowRegistry(inventory: inventory)
        _ = await registry.refresh()

        await registry.noteFocused(AppTestFixtures.key(99))
        let lastFocused = await registry.lastFocusedWindowKey()

        XCTAssertNil(lastFocused)
    }

    @Test
    func testDiscoveredFocusSeedsHistoryOnTheFirstRefresh() async {
        let window = AppTestFixtures.window(7)
        let inventory = ScriptedInventory([[window]], focusedKey: window.id)
        let registry = WindowRegistry(inventory: inventory)

        _ = await registry.refresh()
        let lastFocused = await registry.lastFocusedWindowKey()

        XCTAssertEqual(lastFocused, window.id)
    }

    @Test
    func testTheSnapshotPreservesDiscoveryOrderAndCarriesMRUSequences() async {
        let first = AppTestFixtures.window(1)
        let second = AppTestFixtures.window(2)
        let inventory = ScriptedInventory([[first, second]])
        let registry = WindowRegistry(inventory: inventory)

        let snapshot = await registry.refresh()

        XCTAssertEqual(snapshot.windows.map(\.id), [first.id, second.id])
        XCTAssertGreaterThan(
            snapshot.windows[0].lastFocusSequence,
            snapshot.windows[1].lastFocusSequence
        )
    }

    @Test
    func testAnUnknownKeyHasNoRecord() async {
        let inventory = ScriptedInventory([[AppTestFixtures.window(1)]])
        let registry = WindowRegistry(inventory: inventory)
        _ = await registry.refresh()

        let unknown = await registry.record(for: AppTestFixtures.key(404))

        XCTAssertNil(unknown)
    }

    @Test
    func testConcurrentRefreshesShareASingleDiscovery() async {
        let inventory = ScriptedInventory([[AppTestFixtures.window(1)]])
        let registry = WindowRegistry(inventory: inventory)

        async let first = registry.refresh()
        async let second = registry.refresh()
        _ = await (first, second)
        let discoveries = await inventory.discoveryCount()

        XCTAssertEqual(discoveries, 1)
    }
}
