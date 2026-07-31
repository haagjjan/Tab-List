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
        "com.apple.WindowManager",
    ]

    static func disposition(
        for record: WindowRecord,
        canonicalWindowCount: Int,
        tabListBundleIdentifier: String?
    ) -> WindowCloseDisposition {
        guard canonicalWindowCount == 1,
              record.id.pid != ProcessInfo.processInfo.processIdentifier,
              record.bundleIdentifier != tabListBundleIdentifier,
              record.bundleIdentifier.map({
                  !protectedBundleIdentifiers.contains($0)
              }) ?? true
        else {
            return .closeWindow
        }
        return .quitApplication
    }
}

/// Activates and closes an exact process-scoped window. Private activation is
/// attempted only when the bridge has a validated implementation; AX raising and
/// public application activation provide a safe fallback.
public final class WindowActionService: WindowActuating, @unchecked Sendable {
    private let registry: WindowRegistry
    private let accessibility: AccessibilityBridge
    private let windowServer: WindowServerBridge

    public init(
        registry: WindowRegistry,
        accessibility: AccessibilityBridge,
        windowServer: WindowServerBridge
    ) {
        self.registry = registry
        self.accessibility = accessibility
        self.windowServer = windowServer
    }

    public func activate(
        _ target: WindowActionTarget
    ) async -> WindowActionResult {
        let key = target.key
        guard let record = await resolveRecord(for: target) else {
            return .targetMissing
        }

        // Capture Space state before any operation can move the target. The
        // private activation call may front another Space immediately, and
        // computing this afterward would incorrectly apply the short
        // same-Space verification timeout while macOS is still animating.
        let initiallyVisibleSpaceIDs = windowServer.visibleSpaceIDs()
        let isCrossSpace = !record.spaceIDs.isEmpty
            && Set(record.spaceIDs).isDisjoint(with: initiallyVisibleSpaceIDs)

        if record.isMinimized {
            var preparation = await accessibility.unminimize(key)
            if case .targetMissing = preparation {
                accessibility.invalidate(pid: key.pid)
                preparation = await accessibility.unminimize(key)
            }
            guard preparation.isSuccess else {
                return map(preparation)
            }
        }

        await activateApplication(pid: key.pid)
        var operation = await accessibility.activate(key)

        if case .targetMissing = operation {
            await registry.invalidate()
            _ = await registry.refresh()
            operation = await accessibility.activate(key)
        }

        let usedPrivateActivation = windowServer.activateExactWindow(
            pid: key.pid,
            windowID: key.windowID
        )
        if usedPrivateActivation {
            // A Space transition can invalidate focus state established before
            // the private call. Reassert the target after WindowServer fronts it.
            operation = await accessibility.activate(key)
        }

        let firstTimeout: Duration = isCrossSpace
            ? .seconds(2)
            : .milliseconds(650)
        if await waitForFocus(key, timeout: firstTimeout) {
            await registry.noteFocused(key)
            return .success
        }
        if usedPrivateActivation {
            windowServer.disableExactActivationForProcessLifetime()
        }

        // Retry once with a freshly resolved AX element. Cross-Space
        // transitions are asynchronous, so success is only returned after a
        // bounded focus poll confirms the exact WindowKey.
        guard await resolveRecord(for: target) != nil else {
            return .targetMissing
        }
        accessibility.invalidate(pid: key.pid)
        _ = windowServer.activateExactWindow(
            pid: key.pid,
            windowID: key.windowID
        )
        await activateApplication(pid: key.pid)
        operation = await accessibility.activate(key)
        guard operation.isSuccess else { return map(operation) }

        let retryTimeout: Duration = isCrossSpace
            ? .seconds(2)
            : .milliseconds(750)
        guard await waitForFocus(key, timeout: retryTimeout) else {
            TabListLog.windowActions.warning(
                "Exact focus verification timed out for pid \(key.pid, privacy: .private(mask: .hash)) window \(key.windowID, privacy: .private(mask: .hash))"
            )
            return .timedOut
        }
        await registry.noteFocused(key)
        return .success
    }

    private func activateApplication(pid: pid_t) async {
        await MainActor.run {
            guard let application = NSRunningApplication(
                processIdentifier: pid
            ) else {
                return
            }
            if #available(macOS 14.0, *) {
                application.activate()
            } else {
                application.activate(options: [.activateIgnoringOtherApps])
            }
        }
    }

    public func close(
        _ target: WindowActionTarget
    ) async -> WindowActionResult {
        let key = target.key
        guard let record = await resolveRecord(for: target) else {
            return .targetMissing
        }

        let snapshot = await registry.snapshot(forceRefreshIfStale: true)
        let applicationWindows = snapshot.windows.filter {
            $0.id.pid == key.pid && $0.isStandardWindow && $0.isActionable
        }
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
        guard operation.isSuccess else {
            return map(operation)
        }

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
                // The original canonical window disappeared and its numeric
                // WindowServer ID has already been recycled.
                return .windowClosed
            }
        }

        // The most common reason a successful close-button press leaves the
        // window alive after the bounded verification period is a document
        // confirmation sheet.
        TabListLog.windowActions.notice(
            "Window close requires application confirmation for pid \(key.pid, privacy: .private(mask: .hash)) window \(key.windowID, privacy: .private(mask: .hash))"
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
            let terminated = await MainActor.run { application.isTerminated }
            if terminated {
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

        // A still-running app commonly has an unsaved-document or quit
        // confirmation sheet. Bring it forward without forcing termination.
        await activateApplication(pid: record.id.pid)
        return .confirmationRequired
    }

    private func resolveRecord(
        for target: WindowActionTarget
    ) async -> WindowRecord? {
        if let current = await registry.record(for: target.key),
           target.matches(current),
           current.isActionable {
            return current
        }
        _ = await registry.refresh()
        guard let refreshed = await registry.record(for: target.key),
              target.matches(refreshed),
              refreshed.isActionable else {
            return nil
        }
        return refreshed
    }

    private func map(
        _ operation: AccessibilityOperationResult
    ) -> WindowActionResult {
        switch operation {
        case .success:
            return .success
        case .targetMissing:
            return .targetMissing
        case .permissionDenied:
            return .permissionDenied
        case .unsupported:
            return .unsupported
        case .timedOut:
            return .timedOut
        case let .failed(reason):
            return .failed(reason: reason)
        }
    }

    private func waitForFocus(
        _ key: WindowKey,
        timeout: Duration
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        repeat {
            let focusedKey = await accessibility.focusedWindowKey(
                for: key.pid
            )
            let frontmostPID = await MainActor.run {
                NSWorkspace.shared.frontmostApplication?
                    .processIdentifier
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

private extension AccessibilityOperationResult {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
