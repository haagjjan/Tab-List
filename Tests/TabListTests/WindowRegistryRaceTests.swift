import CoreGraphics
import XCTest
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
            visibleSpaceIDs: [1],
            visibleWindowKeys: Set(windows.map(\.id))
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

final class WindowRegistryRaceTests: XCTestCase {
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
}
