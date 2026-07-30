import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public enum SystemPermissionState: String, Codable, Sendable {
    case notDetermined
    case denied
    case authorized
}

public struct SystemPermissionSnapshot: Codable, Equatable, Sendable {
    public let accessibility: SystemPermissionState
    public let screenRecording: SystemPermissionState

    public init(
        accessibility: SystemPermissionState,
        screenRecording: SystemPermissionState
    ) {
        self.accessibility = accessibility
        self.screenRecording = screenRecording
    }
}

public enum ScreenRecordingPermissionRequestOutcome: String, Codable, Sendable {
    case alreadyAuthorized
    case authorized
    case restartRequired
    case denied
}

public struct ScreenRecordingPermissionRequestResult: Equatable, Sendable {
    public let status: SystemPermissionSnapshot
    public let outcome: ScreenRecordingPermissionRequestOutcome

    public init(
        status: SystemPermissionSnapshot,
        outcome: ScreenRecordingPermissionRequestOutcome
    ) {
        self.status = status
        self.outcome = outcome
    }

    public var requiresRestart: Bool {
        outcome == .restartRequired
    }
}

/// Owns the two privacy permissions used by Tab-List.
///
/// Merely inspecting permission state never prompts. Screen Recording is only
/// requested from `requestScreenRecording()`, allowing icon and title modes to
/// run without ever touching that prompt.
public actor PermissionService {
    private enum DefaultsKey {
        static let requestedAccessibility = "permissions.requestedAccessibility"
        static let requestedScreenRecording = "permissions.requestedScreenRecording"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func currentStatus() -> SystemPermissionSnapshot {
        SystemPermissionSnapshot(
            accessibility: accessibilityStatus(),
            screenRecording: screenRecordingStatus()
        )
    }

    @discardableResult
    public func requestAccessibility() -> SystemPermissionSnapshot {
        defaults.set(true, forKey: DefaultsKey.requestedAccessibility)
        let promptKey = "AXTrustedCheckOptionPrompt"
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        return currentStatus()
    }

    @discardableResult
    public func requestScreenRecording() async -> SystemPermissionSnapshot {
        await requestScreenRecordingResult().status
    }

    /// Requests capture access and distinguishes a denial from the macOS state
    /// where the user granted access but the current process must restart before
    /// `CGPreflightScreenCaptureAccess` observes that grant.
    @discardableResult
    public func requestScreenRecordingResult() async
        -> ScreenRecordingPermissionRequestResult
    {
        defaults.set(true, forKey: DefaultsKey.requestedScreenRecording)

        let wasAuthorized = CGPreflightScreenCaptureAccess()
        if wasAuthorized {
            return ScreenRecordingPermissionRequestResult(
                status: currentStatus(),
                outcome: .alreadyAuthorized
            )
        }

        let requestWasAccepted = await Task.detached(
            priority: .userInitiated
        ) {
            CGRequestScreenCaptureAccess()
        }.value
        let isAuthorizedNow = CGPreflightScreenCaptureAccess()
        let status = currentStatus()

        let outcome: ScreenRecordingPermissionRequestOutcome
        if isAuthorizedNow {
            outcome = .authorized
        } else if requestWasAccepted {
            outcome = .restartRequired
        } else {
            outcome = .denied
        }
        return ScreenRecordingPermissionRequestResult(
            status: status,
            outcome: outcome
        )
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

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    @MainActor
    public func openAccessibilitySettings() {
        openPrivacyPane(anchor: "Privacy_Accessibility")
    }

    @MainActor
    public func openScreenRecordingSettings() {
        openPrivacyPane(anchor: "Privacy_ScreenCapture")
    }

    private func accessibilityStatus() -> SystemPermissionState {
        if AXIsProcessTrusted() {
            return .authorized
        }
        return defaults.bool(forKey: DefaultsKey.requestedAccessibility)
            ? .denied
            : .notDetermined
    }

    private func screenRecordingStatus() -> SystemPermissionState {
        if CGPreflightScreenCaptureAccess() {
            return .authorized
        }
        return defaults.bool(forKey: DefaultsKey.requestedScreenRecording)
            ? .denied
            : .notDetermined
    }

    @MainActor
    private func openPrivacyPane(anchor: String) {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?\(anchor)",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)",
        ]

        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
