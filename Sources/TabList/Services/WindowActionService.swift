@preconcurrency import AppKit
import Foundation
import TabListCore

enum WindowCloseDisposition: Equatable {
    case closeWindow
    case quitApplication
}

enum WindowClosePolicy {
    private static let protectedBundleIdentifiers: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.systemuiserver",
        "com.apple.controlcenter",
        "com.apple.loginwindow",
        "com.apple.windowmanager",
    ]

    static func disposition(
        for record: WindowRecord,
        canonicalWindowCount: Int,
        tabListBundleIdentifier: String?
    ) -> WindowCloseDisposition {
        let bundleIdentifier = record.bundleIdentifier?.lowercased()
        let tabListBundleIdentifier = tabListBundleIdentifier?.lowercased()
        let isTabListBundle = bundleIdentifier != nil
            && bundleIdentifier == tabListBundleIdentifier
        guard canonicalWindowCount == 1,
              record.id.pid != ProcessInfo.processInfo.processIdentifier,
              !isTabListBundle,
              bundleIdentifier.map({
                  !protectedBundleIdentifiers.contains($0)
              }) ?? true
        else {
            return .closeWindow
        }
        return .quitApplication
    }
}

/// Activates and closes one exact window through Accessibility.
///
/// Raising a window and activating its process is enough to reach a window on
/// another Space or in a hidden application, so no private activation entry
/// point is involved. Success is only reported after a bounded poll confirms
/// that the requested window really holds focus.
public final class WindowActionService: WindowActuating, @unchecked Sendable {
    private let registry: WindowRegistry
    private let accessibility: AccessibilityBridge
    private let windowServer: WindowServerBridge
    private let focusTimeout: Duration
    private let spaceSwitchTimeout: Duration

    public init(
        registry: WindowRegistry,
        accessibility: AccessibilityBridge,
        windowServer: WindowServerBridge,
        focusTimeout: Duration = .milliseconds(1_200),
        spaceSwitchTimeout: Duration = .milliseconds(1_500)
    ) {
        self.registry = registry
        self.accessibility = accessibility
        self.windowServer = windowServer
        self.focusTimeout = focusTimeout
        self.spaceSwitchTimeout = spaceSwitchTimeout
    }

    public func activate(
        _ target: WindowActionTarget
    ) async -> WindowActionResult {
        let key = target.key
        guard let record = await resolveRecord(for: target) else {
            return .targetMissing
        }

        if record.isMinimized {
            var preparation = await accessibility.unminimize(key)
            if case .targetMissing = preparation {
                accessibility.invalidate(pid: key.pid)
                preparation = await accessibility.unminimize(key)
            }
            guard preparation.isSuccess else { return map(preparation) }
        }

        // Accessibility hands out no element for a window on another Space, so
        // the application is activated first to bring that Space forward and the
        // window is only raised once macOS has actually switched. The refresh
        // afterwards is what re-enumerates the window and caches its element.
        if isOnAnotherSpace(record) {
            await activateApplication(pid: key.pid)
            await waitForSpace(record.spaceIDs, timeout: spaceSwitchTimeout)
            accessibility.invalidate(pid: key.pid)
            _ = await registry.refresh()
            guard await resolveRecord(for: target) != nil else {
                return .targetMissing
            }
        }

        _ = await accessibility.activate(key)
        await activateApplication(pid: key.pid)
        if await waitForFocus(key, timeout: focusTimeout) {
            await registry.noteFocused(key)
            return .success
        }

        // A stale Accessibility element is the usual reason the first attempt
        // does not take effect. Resolve the window again and retry once.
        accessibility.invalidate(pid: key.pid)
        guard await resolveRecord(for: target) != nil else {
            return .targetMissing
        }
        let retry = await accessibility.activate(key)
        guard retry.isSuccess else { return map(retry) }
        await activateApplication(pid: key.pid)

        guard await waitForFocus(key, timeout: focusTimeout) else {
            TabListLog.windowActions.warning(
                "Focus verification timed out for pid \(key.pid, privacy: .private(mask: .hash))"
            )
            return .timedOut
        }
        await registry.noteFocused(key)
        return .success
    }

    public func close(
        _ target: WindowActionTarget
    ) async -> WindowActionResult {
        let key = target.key
        var snapshot = await registry.refreshSnapshot()
        guard var record = snapshot.window(for: key),
              target.matches(record) else {
            return .targetMissing
        }

        // Closing needs an Accessibility element just as activating does, so a
        // window on another Space is brought forward first. The snapshot is
        // retaken afterwards because the window count drives quit-vs-close.
        if isOnAnotherSpace(record) {
            let activation = await activate(target)
            guard case .success = activation else { return activation }
            snapshot = await registry.refreshSnapshot()
            guard let activated = snapshot.window(for: key),
                  target.matches(activated) else {
                return .targetMissing
            }
            record = activated
        }

        let applicationWindows = snapshot.windows.filter { $0.id.pid == key.pid }
        if WindowClosePolicy.disposition(
            for: record,
            canonicalWindowCount: applicationWindows.count,
            tabListBundleIdentifier: Bundle.main.bundleIdentifier
        ) == .quitApplication {
            return await quitApplication(for: record)
        }

        var operation = await accessibility.close(key)
        if case .targetMissing = operation {
            accessibility.invalidate(pid: key.pid)
            operation = await accessibility.close(key)
        }
        guard operation.isSuccess else { return map(operation) }

        let clock = ContinuousClock()
        for delay in [
            Duration.milliseconds(120),
            .milliseconds(100),
            .milliseconds(120),
            .milliseconds(160),
        ] {
            do {
                try await clock.sleep(for: delay)
            } catch {
                return .failed(
                    reason: "Window close verification was cancelled"
                )
            }
            _ = await registry.refresh()
            guard let current = await registry.record(for: key) else {
                return .windowClosed
            }
            if !target.matches(current) {
                return .windowClosed
            }
        }

        // A close-button press that leaves the window alive after the bounded
        // verification period almost always means a save confirmation sheet.
        TabListLog.windowActions.notice(
            "Window close requires application confirmation for pid \(key.pid, privacy: .private(mask: .hash))"
        )
        _ = await activate(target)
        return .confirmationRequired
    }

    private func quitApplication(
        for record: WindowRecord
    ) async -> WindowActionResult {
        let application = await MainActor.run {
            NSRunningApplication(processIdentifier: record.id.pid)
        }
        guard let application else { return .targetMissing }

        let requested = await MainActor.run { application.terminate() }
        guard requested else {
            return .failed(reason: "Application rejected graceful termination")
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        repeat {
            if await MainActor.run(body: { application.isTerminated }) {
                await registry.invalidate()
                _ = await registry.refresh()
                return .applicationQuit
            }
            do {
                try await clock.sleep(for: .milliseconds(50))
            } catch {
                return .failed(
                    reason: "Application termination verification was cancelled"
                )
            }
        } while clock.now < deadline

        await activateApplication(pid: record.id.pid)
        return .confirmationRequired
    }

    /// Mirrors the Space narrowing in `WindowFilter` so that a window the
    /// switcher shows from another desktop is judged the same way here.
    private func isOnAnotherSpace(_ record: WindowRecord) -> Bool {
        guard !record.spaceIDs.isEmpty else { return false }
        let visible = windowServer.visibleSpaceIDs()
        guard !visible.isEmpty else { return false }
        return Set(record.spaceIDs).isDisjoint(with: visible)
    }

    /// Waits for macOS to finish switching desktops. Returning on timeout is
    /// deliberate: the activation attempt still proceeds and reports its own
    /// outcome rather than failing here on a guess.
    private func waitForSpace(
        _ spaceIDs: [UInt64],
        timeout: Duration
    ) async {
        let targets = Set(spaceIDs)
        guard !targets.isEmpty else { return }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        repeat {
            if !windowServer.visibleSpaceIDs().isDisjoint(with: targets) {
                return
            }
            do {
                try await clock.sleep(for: .milliseconds(50))
            } catch {
                return
            }
        } while clock.now < deadline
        TabListLog.windowActions.warning(
            "Desktop switch did not complete within the timeout"
        )
    }

    private func activateApplication(pid: pid_t) async {
        _ = await MainActor.run {
            NSRunningApplication(processIdentifier: pid)?.activate() ?? false
        }
    }

    private func resolveRecord(
        for target: WindowActionTarget
    ) async -> WindowRecord? {
        if let current = await registry.record(for: target.key),
           target.matches(current) {
            return current
        }
        _ = await registry.refresh()
        guard let refreshed = await registry.record(for: target.key),
              target.matches(refreshed) else {
            return nil
        }
        return refreshed
    }

    private func map(
        _ operation: AccessibilityOperationResult
    ) -> WindowActionResult {
        switch operation {
        case .success:
            .success
        case .targetMissing:
            .targetMissing
        case .permissionDenied:
            .permissionDenied
        case .unsupported:
            .unsupported
        case .timedOut:
            .timedOut
        case let .failed(reason):
            .failed(reason: reason)
        }
    }

    private func waitForFocus(
        _ key: WindowKey,
        timeout: Duration
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        repeat {
            let focusedKey = await accessibility.focusedWindowKey(for: key.pid)
            let frontmostPID = await MainActor.run {
                NSWorkspace.shared.frontmostApplication?.processIdentifier
            }
            if GlobalFocusObservationGate.confirms(
                target: key,
                frontmostPID: frontmostPID,
                accessibilityFocusedKey: focusedKey
            ) {
                return true
            }
            do {
                try await clock.sleep(for: .milliseconds(25))
            } catch {
                return false
            }
        } while clock.now < deadline
        return false
    }
}
