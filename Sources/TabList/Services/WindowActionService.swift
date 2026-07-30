@preconcurrency import AppKit
import Foundation
import TabListCore

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

    public func activate(_ key: WindowKey) async -> WindowActionResult {
        guard let record = await resolveRecord(for: key) else {
            return .targetMissing
        }

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

        let usedPrivateActivation = windowServer.activateExactWindow(
            pid: key.pid,
            windowID: key.windowID
        )
        var operation = await accessibility.activate(key)

        if case .targetMissing = operation {
            await registry.invalidate()
            _ = await registry.refresh()
            operation = await accessibility.activate(key)
        }

        if !usedPrivateActivation {
            await MainActor.run {
                guard let application = NSRunningApplication(
                    processIdentifier: key.pid
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

        if await waitForFocus(key, timeout: .milliseconds(300)) {
            await registry.noteFocused(key)
            return .success
        }
        if usedPrivateActivation {
            windowServer.disableExactActivationForProcessLifetime()
        }

        // Retry once with a freshly resolved AX element. Cross-Space
        // transitions are asynchronous, so success is only returned after a
        // bounded focus poll confirms the exact WindowKey.
        accessibility.invalidate(pid: key.pid)
        _ = windowServer.activateExactWindow(
            pid: key.pid,
            windowID: key.windowID
        )
        operation = await accessibility.activate(key)
        guard operation.isSuccess else { return map(operation) }

        guard await waitForFocus(key, timeout: .milliseconds(500)) else {
            TabListLog.windowActions.warning(
                "Exact focus verification timed out for pid \(key.pid, privacy: .private(mask: .hash)) window \(key.windowID, privacy: .private(mask: .hash))"
            )
            return .timedOut
        }
        await registry.noteFocused(key)
        return .success
    }

    public func close(_ key: WindowKey) async -> WindowActionResult {
        guard await resolveRecord(for: key) != nil else {
            return .targetMissing
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
            if !(await registry.contains(key)) {
                return .success
            }
        }

        // The most common reason a successful close-button press leaves the
        // window alive after the bounded verification period is a document
        // confirmation sheet.
        TabListLog.windowActions.notice(
            "Window close requires application confirmation for pid \(key.pid, privacy: .private(mask: .hash)) window \(key.windowID, privacy: .private(mask: .hash))"
        )
        _ = await activate(key)
        return .confirmationRequired
    }

    private func resolveRecord(for key: WindowKey) async -> WindowRecord? {
        if let current = await registry.record(for: key) {
            return current
        }
        _ = await registry.refresh()
        return await registry.record(for: key)
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
