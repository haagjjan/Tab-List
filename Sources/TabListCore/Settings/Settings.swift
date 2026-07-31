import Foundation

public enum PresentationMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case thumbnails
    case appIcons
    case titles

    public var id: Self { self }
}

public enum PanelSize: String, CaseIterable, Codable, Identifiable, Sendable {
    case small
    case medium
    case large
    case auto

    public var id: Self { self }
}

public enum ThemePreference: String, CaseIterable, Codable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: Self { self }
}

public enum SpaceScope: String, CaseIterable, Codable, Identifiable, Sendable {
    case allSpaces
    case visibleSpaces

    public var id: Self { self }
}

public enum ScreenScope: String, CaseIterable, Codable, Identifiable, Sendable {
    case allScreens
    case pointerScreen

    public var id: Self { self }
}

public enum ScopePreset: String, CaseIterable, Identifiable, Sendable {
    case everywhere
    case visibleNow
    case pointerDisplay
    case custom

    public var id: Self { self }

    public init(spaceScope: SpaceScope, screenScope: ScreenScope) {
        switch (spaceScope, screenScope) {
        case (.allSpaces, .allScreens): self = .everywhere
        case (.visibleSpaces, .allScreens): self = .visibleNow
        case (.visibleSpaces, .pointerScreen): self = .pointerDisplay
        case (.allSpaces, .pointerScreen): self = .custom
        }
    }

    public var scopes: (space: SpaceScope, screen: ScreenScope)? {
        switch self {
        case .everywhere: (.allSpaces, .allScreens)
        case .visibleNow: (.visibleSpaces, .allScreens)
        case .pointerDisplay: (.visibleSpaces, .pointerScreen)
        case .custom: nil
        }
    }
}

public enum ReverseControlDefinition: Codable, Equatable, Sendable {
    case shiftWithForwardKey
    case shiftOnly
    case key(UInt16)
}

/// Version 2 of the user-controlled settings payload.
///
/// Launch-at-login is intentionally absent because `SMAppService` is the source
/// of truth for that state.
public struct SettingsV2: Codable, Equatable, Sendable {
    public var presentation: PresentationMode
    public var panelSize: PanelSize
    public var theme: ThemePreference
    /// Retained in the version-1 payload so early alpha preferences continue
    /// to decode. Alpha 2 intentionally normalizes this legacy control to a
    /// fully opaque background.
    public var opacity: Double
    public var shortcut: ShortcutDefinition
    public var spaceScope: SpaceScope
    public var screenScope: ScreenScope
    public var includeMinimized: Bool
    public var includeHiddenApps: Bool
    public var includeFullscreen: Bool
    public var excludedBundleIdentifiers: Set<String>
    public var refreshThumbnailsInBackground: Bool
    public var showMenuBarIcon: Bool
    public var automaticallyChecksForUpdates: Bool
    public var reverseControl: ReverseControlDefinition
    public var holdCycleSpeed: Double

    public init(
        presentation: PresentationMode = .thumbnails,
        panelSize: PanelSize = .auto,
        theme: ThemePreference = .system,
        opacity: Double = 1.0,
        shortcut: ShortcutDefinition = .commandTab,
        spaceScope: SpaceScope = .allSpaces,
        screenScope: ScreenScope = .allScreens,
        includeMinimized: Bool = true,
        includeHiddenApps: Bool = true,
        includeFullscreen: Bool = true,
        excludedBundleIdentifiers: Set<String> = [],
        refreshThumbnailsInBackground: Bool = false,
        showMenuBarIcon: Bool = true,
        automaticallyChecksForUpdates: Bool = true,
        reverseControl: ReverseControlDefinition = .shiftWithForwardKey,
        holdCycleSpeed: Double = 1.0
    ) {
        self.presentation = presentation
        self.panelSize = panelSize
        self.theme = theme
        self.opacity = opacity
        self.shortcut = shortcut
        self.spaceScope = spaceScope
        self.screenScope = screenScope
        self.includeMinimized = includeMinimized
        self.includeHiddenApps = includeHiddenApps
        self.includeFullscreen = includeFullscreen
        self.excludedBundleIdentifiers = excludedBundleIdentifiers
        self.refreshThumbnailsInBackground = refreshThumbnailsInBackground
        self.showMenuBarIcon = showMenuBarIcon
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        self.reverseControl = reverseControl
        self.holdCycleSpeed = holdCycleSpeed
    }

    public static let `default` = SettingsV2()

    /// Returns a safe representation for the current product decisions,
    /// including migrations for controls retired during the alpha.
    public func normalized() -> SettingsV2 {
        var copy = self
        // The continuous translucency control was removed after the first
        // hands-on alpha. Keep the field for backwards-compatible decoding,
        // while migrating every saved value to the new opaque default.
        copy.opacity = 1.0
        copy.excludedBundleIdentifiers = Set(
            excludedBundleIdentifiers.compactMap { identifier in
                let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        )

        // Shift is session input for reverse cycling, never part of the stored
        // base shortcut.
        copy.shortcut.modifiers.remove(.shift)
        if !ShortcutValidator.validate(copy.shortcut).isValid {
            copy.shortcut = .commandTab
        }
        if !copy.holdCycleSpeed.isFinite {
            copy.holdCycleSpeed = Self.default.holdCycleSpeed
        }
        copy.holdCycleSpeed = min(max(copy.holdCycleSpeed, 0.5), 2.0)
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case presentation
        case panelSize
        case theme
        case opacity
        case shortcut
        case spaceScope
        case screenScope
        case includeMinimized
        case includeHiddenApps
        case includeFullscreen
        case excludedBundleIdentifiers
        case refreshThumbnailsInBackground
        case showMenuBarIcon
        case automaticallyChecksForUpdates
        case reverseControl
        case holdCycleSpeed
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            presentation: try values.decode(
                PresentationMode.self,
                forKey: .presentation
            ),
            panelSize: try values.decode(PanelSize.self, forKey: .panelSize),
            theme: try values.decode(ThemePreference.self, forKey: .theme),
            opacity: try values.decode(Double.self, forKey: .opacity),
            shortcut: try values.decode(
                ShortcutDefinition.self,
                forKey: .shortcut
            ),
            spaceScope: try values.decode(SpaceScope.self, forKey: .spaceScope),
            screenScope: try values.decode(ScreenScope.self, forKey: .screenScope),
            includeMinimized: try values.decode(
                Bool.self,
                forKey: .includeMinimized
            ),
            includeHiddenApps: try values.decode(
                Bool.self,
                forKey: .includeHiddenApps
            ),
            includeFullscreen: try values.decode(
                Bool.self,
                forKey: .includeFullscreen
            ),
            excludedBundleIdentifiers: try values.decode(
                Set<String>.self,
                forKey: .excludedBundleIdentifiers
            ),
            refreshThumbnailsInBackground: try values.decode(
                Bool.self,
                forKey: .refreshThumbnailsInBackground
            ),
            showMenuBarIcon: try values.decode(
                Bool.self,
                forKey: .showMenuBarIcon
            ),
            automaticallyChecksForUpdates: try values.decode(
                Bool.self,
                forKey: .automaticallyChecksForUpdates
            ),
            reverseControl: try values.decodeIfPresent(
                ReverseControlDefinition.self,
                forKey: .reverseControl
            ) ?? .shiftWithForwardKey,
            holdCycleSpeed: try values.decodeIfPresent(
                Double.self,
                forKey: .holdCycleSpeed
            ) ?? 1.0
        )
    }
}

/// Source compatibility for alpha code while the persisted payload migrates to
/// schema V2. New code should prefer `TabListSettings` or `SettingsV2`.
public typealias SettingsV1 = SettingsV2
public typealias TabListSettings = SettingsV2
