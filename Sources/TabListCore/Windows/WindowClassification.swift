import CoreGraphics
import Foundation

/// Raw facts used to decide whether a WindowServer surface represents a
/// user-switchable window.
public struct WindowClassificationInput: Equatable, Sendable {
    public var ownerBundleIdentifier: String?
    public var ownerName: String
    public var bounds: CGRect
    public var layer: Int
    public var alpha: Double
    public var accessibilityRole: String?
    public var accessibilitySubrole: String?
    public var isOwnedByTabList: Bool
    public var isDesktopElement: Bool
    public var isNotification: Bool
    public var isTabGroupChild: Bool
    public var isTransparentSurface: Bool

    public init(
        ownerBundleIdentifier: String?,
        ownerName: String,
        bounds: CGRect,
        layer: Int,
        alpha: Double,
        accessibilityRole: String?,
        accessibilitySubrole: String?,
        isOwnedByTabList: Bool = false,
        isDesktopElement: Bool = false,
        isNotification: Bool = false,
        isTabGroupChild: Bool = false,
        isTransparentSurface: Bool = false
    ) {
        self.ownerBundleIdentifier = ownerBundleIdentifier
        self.ownerName = ownerName
        self.bounds = bounds
        self.layer = layer
        self.alpha = alpha
        self.accessibilityRole = accessibilityRole
        self.accessibilitySubrole = accessibilitySubrole
        self.isOwnedByTabList = isOwnedByTabList
        self.isDesktopElement = isDesktopElement
        self.isNotification = isNotification
        self.isTabGroupChild = isTabGroupChild
        self.isTransparentSurface = isTransparentSurface
    }
}

public enum WindowExclusionReason: Equatable, Sendable {
    case ownApplication
    case systemSurface
    case nonzeroLayer
    case invalidGeometry
    case invisibleSurface
    case desktopElement
    case notification
    case inactiveTab
    case unsupportedRole(String)
    case unsupportedSubrole(String)
}

public enum WindowClassification: Equatable, Sendable {
    case standard
    case excluded(WindowExclusionReason)

    public var isEligible: Bool {
        self == .standard
    }
}

/// Conservative classification based on independent WindowServer and
/// Accessibility facts. Window titles are intentionally not considered.
public enum WindowClassifier {
    private static let acceptedRoles: Set<String> = [
        "AXWindow",
        "AXDialog",
        "AXSheet",
    ]

    private static let acceptedSubroles: Set<String> = [
        "AXStandardWindow",
        "AXDialog",
        "AXSystemDialog",
    ]

    private static let excludedSubroles: Set<String> = [
        "AXFloatingWindow",
        "AXSystemFloatingWindow",
        "AXUnknown",
    ]

    private static let excludedSystemBundleIdentifiers: Set<String> = [
        "com.apple.dock",
        "com.apple.notificationcenterui",
        "com.apple.controlcenter",
    ]

    public static func classify(_ input: WindowClassificationInput) -> WindowClassification {
        if input.isOwnedByTabList {
            return .excluded(.ownApplication)
        }

        let normalizedBundleIdentifier = input.ownerBundleIdentifier?.lowercased()
        let normalizedOwnerName = input.ownerName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalizedBundleIdentifier.map(excludedSystemBundleIdentifiers.contains) == true
            || normalizedOwnerName == "window server"
            || normalizedOwnerName == "dock"
        {
            return .excluded(.systemSurface)
        }

        guard input.layer == 0 else {
            return .excluded(.nonzeroLayer)
        }

        let bounds = input.bounds
        guard bounds.origin.x.isFinite,
              bounds.origin.y.isFinite,
              bounds.width.isFinite,
              bounds.height.isFinite,
              bounds.width > 1,
              bounds.height > 1
        else {
            return .excluded(.invalidGeometry)
        }

        guard input.alpha.isFinite,
              input.alpha > 0.01,
              !input.isTransparentSurface
        else {
            return .excluded(.invisibleSurface)
        }

        if input.isDesktopElement {
            return .excluded(.desktopElement)
        }
        if input.isNotification {
            return .excluded(.notification)
        }
        if input.isTabGroupChild {
            return .excluded(.inactiveTab)
        }

        if let role = input.accessibilityRole,
           !acceptedRoles.contains(role)
        {
            return .excluded(.unsupportedRole(role))
        }

        if let subrole = input.accessibilitySubrole {
            if excludedSubroles.contains(subrole) {
                return .excluded(.unsupportedSubrole(subrole))
            }
            if !acceptedSubroles.contains(subrole) {
                return .excluded(.unsupportedSubrole(subrole))
            }
        }

        return .standard
    }
}
