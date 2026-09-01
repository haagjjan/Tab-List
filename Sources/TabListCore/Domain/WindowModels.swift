import CoreGraphics
import Darwin
import Foundation

/// A process-scoped window identifier.
///
/// `windowID` is the WindowServer identifier when that mapping is available,
/// and otherwise a per-process ordinal assigned by the inventory. Both forms
/// are unique within a process and valid only for that process's lifetime, so
/// a key must never be persisted between launches.
public struct WindowKey: Hashable, Codable, Sendable {
    public let pid: pid_t
    public let windowID: CGWindowID

    public init(pid: pid_t, windowID: CGWindowID) {
        self.pid = pid
        self.windowID = windowID
    }
}

/// A session-scoped action reference. An action is valid only while both its
/// key and registry incarnation still match the record shown to the user.
public struct WindowActionTarget: Equatable, Sendable {
    public let key: WindowKey
    public let incarnation: UInt64

    public init(key: WindowKey, incarnation: UInt64) {
        self.key = key
        self.incarnation = incarnation
    }

    public init(_ record: WindowRecord) {
        key = record.id
        incarnation = record.incarnation
    }

    public func matches(_ record: WindowRecord) -> Bool {
        key == record.id && incarnation == record.incarnation
    }
}

/// Diagnostic description of how a record's identity was resolved.
public enum WindowIdentitySource: String, Codable, Sendable {
    case windowServerID
    case accessibilityOrdinal
}

/// Framework-neutral metadata used by filtering, ordering, and the panel.
///
/// References to `AXUIElement` and AppKit images deliberately live outside this
/// type in their owning services.
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
    public var isClosable: Bool
    public var identitySource: WindowIdentitySource
    public var lastFocusSequence: UInt64
    /// Process-local registry identity that prevents a recycled WindowServer
    /// identifier from inheriting state from a previously closed window.
    public var incarnation: UInt64

    public init(
        id: WindowKey,
        bundleIdentifier: String?,
        applicationName: String,
        bundleURL: URL?,
        windowTitle: String,
        bounds: CGRect,
        spaceIDs: [UInt64] = [],
        displayID: CGDirectDisplayID? = nil,
        isMinimized: Bool = false,
        isHidden: Bool = false,
        isFullscreen: Bool = false,
        isClosable: Bool = true,
        identitySource: WindowIdentitySource = .accessibilityOrdinal,
        lastFocusSequence: UInt64 = 0,
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
        self.isClosable = isClosable
        self.identitySource = identitySource
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

    private let index: [WindowKey: Int]

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
        index = windows.enumerated().reduce(
            into: [WindowKey: Int](minimumCapacity: windows.count)
        ) { result, entry in
            result[entry.element.id] = entry.offset
        }
    }

    public func window(for key: WindowKey) -> WindowRecord? {
        index[key].map { windows[$0] }
    }
}
