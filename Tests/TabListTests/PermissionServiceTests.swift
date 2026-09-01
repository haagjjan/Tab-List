import Foundation
import Testing
@testable import TabList

private let requestedKey = "permissions.requestedAccessibility"

/// `UserDefaults` is thread-safe but not `Sendable`, so each test opens its own
/// throwaway suite through an explicit unsafe local rather than sharing one.
private func withSandboxedDefaults(
    seedingRequestFlag seedRequestFlag: Bool = false,
    _ body: (PermissionService, @Sendable () -> Bool) async -> Void
) async {
    let name = "com.haagjjan.TabListTests.\(UUID().uuidString)"
    nonisolated(unsafe) let defaults = UserDefaults(suiteName: name)!
    if seedRequestFlag {
        defaults.set(true, forKey: requestedKey)
    }
    await body(
        PermissionService(defaults: defaults),
        { defaults.bool(forKey: requestedKey) }
    )
    UserDefaults.standard.removePersistentDomain(forName: name)
}

/// These assertions hold whether or not the test host happens to be trusted,
/// so the suite stays deterministic on a developer Mac and in CI.
@Suite
struct PermissionServiceTests {
    @Test
    func testAFreshInstallIsNeverReportedAsDenied() async {
        await withSandboxedDefaults { service, _ in
            let status = await service.currentStatus()
            XCTAssertNotEqual(status.accessibility, .denied)
        }
    }

    @Test
    func testOnceRequestedTheStateIsNeverUndetermined() async {
        await withSandboxedDefaults(seedingRequestFlag: true) { service, _ in
            let status = await service.currentStatus()
            XCTAssertNotEqual(status.accessibility, .notDetermined)
        }
    }

    @Test
    func testInspectingTheStateNeverRecordsARequest() async {
        await withSandboxedDefaults { service, wasRequested in
            _ = await service.currentStatus()
            _ = await service.currentStatus()
            XCTAssertFalse(wasRequested())
        }
    }

    @Test
    func testTheStatusStreamEmitsTheCurrentStateImmediately() async {
        await withSandboxedDefaults { service, _ in
            let expected = await service.currentStatus()
            var received: SystemPermissionSnapshot?
            for await status in await service.statusUpdates(
                every: .seconds(30)
            ) {
                received = status
                break
            }
            XCTAssertEqual(received, expected)
        }
    }

    @Test
    func testTheSnapshotIsValueComparable() {
        XCTAssertEqual(
            SystemPermissionSnapshot(accessibility: .authorized),
            SystemPermissionSnapshot(accessibility: .authorized)
        )
        XCTAssertNotEqual(
            SystemPermissionSnapshot(accessibility: .authorized),
            SystemPermissionSnapshot(accessibility: .denied)
        )
    }
}
