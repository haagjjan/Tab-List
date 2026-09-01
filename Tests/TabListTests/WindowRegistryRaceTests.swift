import CoreGraphics
import Testing
@testable import TabList
import TabListCore

private actor SuspendedFocusInventory: WindowInventoryProviding {
    private let result: WindowInventoryResult
    private let staleFocusedKey: WindowKey
    private var focusReadStartedContinuation:
        CheckedContinuation<Void, Never>?
    private var focusReadStarted = false
    private var focusReadReleaseContinuation:
        CheckedContinuation<Void, Never>?
    private var focusReadWasReleased = false

    init(windows: [WindowRecord], staleFocusedKey: WindowKey) {
        result = WindowInventoryResult(
            windows: windows,
            visibleSpaceIDs: [1]
        )
        self.staleFocusedKey = staleFocusedKey
    }

    func discover() async -> WindowInventoryResult {
        result
    }

    func currentFocusedWindowKey() async -> WindowKey? {
        focusReadStarted = true
        focusReadStartedContinuation?.resume()
        focusReadStartedContinuation = nil

        if !focusReadWasReleased {
            await withCheckedContinuation { continuation in
                focusReadReleaseContinuation = continuation
            }
        }
        return staleFocusedKey
    }

    func waitUntilFocusReadStarts() async {
        if focusReadStarted { return }
        await withCheckedContinuation { continuation in
            focusReadStartedContinuation = continuation
        }
    }

    func releaseStaleFocusRead() {
        focusReadWasReleased = true
        focusReadReleaseContinuation?.resume()
        focusReadReleaseContinuation = nil
    }
}

private actor SequencedInventory: WindowInventoryProviding {
    private let first: WindowRecord
    private let second: WindowRecord
    private var discoveries = 0

    init(first: WindowRecord, second: WindowRecord) {
        self.first = first
        self.second = second
    }

    func discover() -> WindowInventoryResult {
        discoveries += 1
        let windows = discoveries == 1 ? [first] : [first, second]
        return WindowInventoryResult(
            windows: windows,
            visibleSpaceIDs: [1]
        )
    }

    func currentFocusedWindowKey() -> WindowKey? {
        first.id
    }
}

@Suite
struct WindowRegistryRaceTests {
    @Test
    func testNewFocusEventWinsOverSuspendedStaleRefreshFocus() async {
        let staleWindow = AppTestFixtures.window(1, title: "Stale")
        let newlyFocusedWindow = AppTestFixtures.window(
            2,
            title: "Newest"
        )
        let inventory = SuspendedFocusInventory(
            windows: [staleWindow, newlyFocusedWindow],
            staleFocusedKey: staleWindow.id
        )
        let registry = WindowRegistry(inventory: inventory)

        let refresh = Task {
            await registry.refresh()
        }
        await inventory.waitUntilFocusReadStarts()
        await registry.noteFocused(newlyFocusedWindow.id)
        await inventory.releaseStaleFocusRead()

        let snapshot = await refresh.value
        let staleSequence = snapshot.windows.first {
            $0.id == staleWindow.id
        }?.lastFocusSequence
        let newestSequence = snapshot.windows.first {
            $0.id == newlyFocusedWindow.id
        }?.lastFocusSequence
        let lastFocusedWindowKey = await registry.lastFocusedWindowKey()

        XCTAssertEqual(lastFocusedWindowKey, newlyFocusedWindow.id)
        XCTAssertGreaterThan(newestSequence ?? 0, staleSequence ?? 0)
    }

    @Test
    func testUnconditionalRefreshBypassesFreshSnapshotAge() async {
        let first = AppTestFixtures.window(1)
        let second = AppTestFixtures.window(2)
        let inventory = SequencedInventory(first: first, second: second)
        let registry = WindowRegistry(
            inventory: inventory,
            staleAfter: .seconds(60)
        )

        let cached = await registry.snapshot(forceRefreshIfStale: false)
        let refreshed = await registry.refreshSnapshot()

        XCTAssertEqual(cached.windows.map(\.id), [first.id])
        XCTAssertEqual(
            Set(refreshed.windows.map(\.id)),
            [first.id, second.id]
        )
        XCTAssertGreaterThan(refreshed.generation, cached.generation)
    }
}
