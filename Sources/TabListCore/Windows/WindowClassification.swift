import CoreGraphics
import Foundation

public enum WindowOwnerActivationPolicy: String, Equatable, Sendable {
    case regular
    case accessory
    case prohibited
    case unknown

    public var canOwnSwitcherCandidates: Bool {
        switch self {
        case .regular, .unknown:
            true
        case .accessory, .prohibited:
            false
        }
    }
}

/// Facts read from one Accessibility window element and its owning process.
public struct WindowClassificationInput: Equatable, Sendable {
    public var ownerBundleIdentifier: String?
    public var ownerName: String
    public var ownerActivationPolicy: WindowOwnerActivationPolicy
    public var bounds: CGRect
    public var accessibilityRole: String?
    public var accessibilitySubrole: String?
    public var isOwnedByTabList: Bool

    public init(
        ownerBundleIdentifier: String?,
        ownerName: String,
        ownerActivationPolicy: WindowOwnerActivationPolicy = .unknown,
        bounds: CGRect,
        accessibilityRole: String?,
        accessibilitySubrole: String?,
        isOwnedByTabList: Bool = false
    ) {
        self.ownerBundleIdentifier = ownerBundleIdentifier
        self.ownerName = ownerName
        self.ownerActivationPolicy = ownerActivationPolicy
        self.bounds = bounds
        self.accessibilityRole = accessibilityRole
        self.accessibilitySubrole = accessibilitySubrole
        self.isOwnedByTabList = isOwnedByTabList
    }
}

public enum WindowExclusionReason: Equatable, Sendable {
    case ownApplication
    case systemSurface
    case nonUserApplication(WindowOwnerActivationPolicy)
    case invalidGeometry
    case unsupportedRole(String)
    case unsupportedSubrole(String)

    public var diagnosticCode: String {
        switch self {
        case .ownApplication:
            "own-application"
        case .systemSurface:
            "system-surface"
        case let .nonUserApplication(policy):
            "non-user-application-\(policy.rawValue)"
        case .invalidGeometry:
            "invalid-geometry"
        case let .unsupportedRole(role):
            "unsupported-role-\(role)"
        case let .unsupportedSubrole(subrole):
            "unsupported-subrole-\(subrole)"
        }
    }
}

public enum WindowClassification: Equatable, Sendable {
    case standard
    case excluded(WindowExclusionReason)

    public var isEligible: Bool {
        self == .standard
    }
}

/// Decides whether one Accessibility window is a user-switchable window.
///
/// The rule set is deliberately permissive: an unfamiliar subrole is accepted
/// rather than dropped, because a window that macOS exposes as a top-level
/// `AXWindow` is one the user can switch to. Only surfaces that are provably
/// not switchable — panels, palettes, system chrome — are excluded. Window
/// titles are never considered.
public enum WindowClassifier {
    private static let acceptedRoles: Set<String> = [
        "AXWindow",
        "AXDialog",
    ]

    private static let excludedSubroles: Set<String> = [
        "AXFloatingWindow",
        "AXSystemFloatingWindow",
        "AXUnknown",
    ]

    private static let excludedBundleIdentifiers: Set<String> = [
        "com.apple.dock",
        "com.apple.notificationcenterui",
        "com.apple.controlcenter",
        "com.apple.wallpaper.agent",
        "com.apple.windowmanager",
    ]

    private static let excludedOwnerNames: Set<String> = [
        "window server",
        "dock",
        "notification center",
    ]

    private static let minimumWindowEdge: CGFloat = 32

    public static func classify(
        _ input: WindowClassificationInput
    ) -> WindowClassification {
        if input.isOwnedByTabList {
            return .excluded(.ownApplication)
        }

        let identifier = input.ownerBundleIdentifier?.lowercased()
        let ownerName = input.ownerName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if identifier.map(excludedBundleIdentifiers.contains) == true
            || excludedOwnerNames.contains(ownerName)
        {
            return .excluded(.systemSurface)
        }

        guard input.ownerActivationPolicy.canOwnSwitcherCandidates else {
            return .excluded(
                .nonUserApplication(input.ownerActivationPolicy)
            )
        }

        if let role = input.accessibilityRole,
           !acceptedRoles.contains(role)
        {
            return .excluded(.unsupportedRole(role))
        }

        if let subrole = input.accessibilitySubrole,
           excludedSubroles.contains(subrole)
        {
            return .excluded(.unsupportedSubrole(subrole))
        }

        let bounds = input.bounds
        guard bounds.origin.x.isFinite,
              bounds.origin.y.isFinite,
              bounds.width.isFinite,
              bounds.height.isFinite,
              bounds.width >= minimumWindowEdge,
              bounds.height >= minimumWindowEdge
        else {
            return .excluded(.invalidGeometry)
        }

        return .standard
    }
}
