import CoreGraphics
import Darwin
import Foundation

/// A process-scoped identifier for a WindowServer window.
///
/// Window identifiers are only valid for the lifetime of the owning process and
/// must not be persisted between application launches.
public struct WindowKey: Hashable, Codable, Sendable {
    public let pid: pid_t
    public let windowID: CGWindowID

    public init(pid: pid_t, windowID: CGWindowID) {
        self.pid = pid
        self.windowID = windowID
    }
}

/// Framework-neutral metadata used by filtering, ordering, and switcher UI code.
///
/// References to `AXUIElement`, `SCWindow`, and AppKit images deliberately live
/// outside this type in their owning services.
public struct WindowRecord: Identifiable, Equatable, Sendable {
    public let id: WindowKey
    public let bundleIdentifier: String?
    public let applicationName: String
    public let bundleURL: URL?
    public var windowTitle: String
    public var bounds: CGRect
    public var spaceIDs: [UInt64]
    public var displayID: CGDirectDisplayID?
    public var isMinimized: Bool
    public var isHidden: Bool
    public var isFullscreen: Bool
    public var isStandardWindow: Bool
    public var isClosable: Bool
    public var lastFocusSequence: UInt64
    /// Process-local registry identity used to prevent a recycled WindowServer
    /// ID from inheriting cached pixels from a previously closed window.
    public var incarnation: UInt64

    public init(
        id: WindowKey,
        bundleIdentifier: String?,
        applicationName: String,
        bundleURL: URL?,
        windowTitle: String,
        bounds: CGRect,
        spaceIDs: [UInt64],
        displayID: CGDirectDisplayID?,
        isMinimized: Bool,
        isHidden: Bool,
        isFullscreen: Bool,
        isStandardWindow: Bool,
        isClosable: Bool,
        lastFocusSequence: UInt64,
        incarnation: UInt64 = 0
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.bundleURL = bundleURL
        self.windowTitle = windowTitle
        self.bounds = bounds
        self.spaceIDs = spaceIDs
        self.displayID = displayID
        self.isMinimized = isMinimized
        self.isHidden = isHidden
        self.isFullscreen = isFullscreen
        self.isStandardWindow = isStandardWindow
        self.isClosable = isClosable
        self.lastFocusSequence = lastFocusSequence
        self.incarnation = incarnation
    }
}

/// An immutable, internally consistent view of all known windows.
public struct WindowSnapshot: Sendable {
    public let generation: UInt64
    public let windows: [WindowRecord]
    public let visibleSpaceIDs: Set<UInt64>
    public let createdAt: ContinuousClock.Instant

    public init(
        generation: UInt64,
        windows: [WindowRecord],
        visibleSpaceIDs: Set<UInt64>,
        createdAt: ContinuousClock.Instant = ContinuousClock().now
    ) {
        self.generation = generation
        self.windows = windows
        self.visibleSpaceIDs = visibleSpaceIDs
        self.createdAt = createdAt
    }

    public func window(for key: WindowKey) -> WindowRecord? {
        windows.first { $0.id == key }
    }
}
