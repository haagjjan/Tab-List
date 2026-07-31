import Foundation

public enum WindowActionResult: Equatable, Sendable {
    case success
    case windowClosed
    case applicationQuit
    case targetMissing
    case permissionDenied
    case unsupported
    case timedOut
    case confirmationRequired
    case failed(reason: String)

    public var succeeded: Bool {
        switch self {
        case .success, .windowClosed, .applicationQuit:
            true
        case .targetMissing, .permissionDenied, .unsupported, .timedOut,
             .confirmationRequired, .failed:
            false
        }
    }

    public var diagnosticCode: String {
        switch self {
        case .success:
            "success"
        case .windowClosed:
            "window-closed"
        case .applicationQuit:
            "application-quit"
        case .targetMissing:
            "target-missing"
        case .permissionDenied:
            "permission-denied"
        case .unsupported:
            "unsupported"
        case .timedOut:
            "timed-out"
        case .confirmationRequired:
            "confirmation-required"
        case .failed:
            "failed"
        }
    }
}

public protocol WindowSnapshotProviding: Sendable {
    func snapshot(forceRefreshIfStale: Bool) async -> WindowSnapshot
    func refreshSnapshot() async -> WindowSnapshot
}

public protocol WindowFocusHistoryProviding: Sendable {
    func lastFocusedWindowKey() async -> WindowKey?
}

public protocol WindowActuating: Sendable {
    func activate(_ target: WindowActionTarget) async -> WindowActionResult
    func close(_ target: WindowActionTarget) async -> WindowActionResult
}
