import Foundation

public enum WindowActionResult: Equatable, Sendable {
    case success
    case targetMissing
    case permissionDenied
    case unsupported
    case timedOut
    case confirmationRequired
    case failed(reason: String)

    public var succeeded: Bool {
        self == .success
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
    func activate(_ key: WindowKey) async -> WindowActionResult
    func close(_ key: WindowKey) async -> WindowActionResult
}
