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

/// A session-scoped action reference. WindowServer IDs can be recycled, so an
/// action is valid only while both its process-scoped key and registry
/// incarnation still match the canonical record shown to the user.
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

/// Describes the evidence used to map an item to a real Accessibility window.
/// It is diagnostic metadata only and is never persisted across launches.
public enum WindowIdentitySource: String, Codable, Sendable {
    case exactAccessibilityID
    case uniqueGeometry
    case publicWindowSurface

    public var confidence: WindowIdentityConfidence {
        switch self {
        case .exactAccessibilityID: .exact
        case .uniqueGeometry: .unambiguousFallback
        case .publicWindowSurface: .unverified
        }
    }
}

public enum WindowIdentityConfidence: String, Codable, Sendable {
    case exact
    case unambiguousFallback
    case unverified
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
    public var identitySource: WindowIdentitySource
    public var isActionable: Bool
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
        identitySource: WindowIdentitySource = .publicWindowSurface,
        isActionable: Bool = true,
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
        self.identitySource = identitySource
        self.isActionable = isActionable
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
