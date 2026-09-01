import AppKit
import ApplicationServices
import Foundation

public enum SystemPermissionState: String, Codable, Sendable {
    case notDetermined
    case denied
    case authorized
}

public struct SystemPermissionSnapshot: Codable, Equatable, Sendable {
    public let accessibility: SystemPermissionState

    public init(accessibility: SystemPermissionState) {
        self.accessibility = accessibility
    }
}

/// Owns the single privacy permission Tab-List needs.
///
/// Inspecting the state never prompts; only `requestAccessibility()` does.
public actor PermissionService {
    private enum DefaultsKey {
        static let requestedAccessibility = "permissions.requestedAccessibility"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func currentStatus() -> SystemPermissionSnapshot {
        SystemPermissionSnapshot(accessibility: accessibilityStatus())
    }

    @discardableResult
    public func requestAccessibility() -> SystemPermissionSnapshot {
        defaults.set(true, forKey: DefaultsKey.requestedAccessibility)
        _ = AXIsProcessTrustedWithOptions(
            ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        )
        return currentStatus()
    }

    public func statusUpdates(
        every interval: Duration = .seconds(1)
    ) -> AsyncStream<SystemPermissionSnapshot> {
        AsyncStream { continuation in
            let task = Task {
                var previous: SystemPermissionSnapshot?
                while !Task.isCancelled {
                    let status = self.currentStatus()
                    if status != previous {
                        continuation.yield(status)
                        previous = status
                    }
                    do {
                        try await ContinuousClock().sleep(for: interval)
                    } catch {
                        break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    @MainActor
    public func openAccessibilitySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
        ]
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private func accessibilityStatus() -> SystemPermissionState {
        if AXIsProcessTrusted() {
            return .authorized
        }
        return defaults.bool(forKey: DefaultsKey.requestedAccessibility)
            ? .denied
            : .notDetermined
    }
}
