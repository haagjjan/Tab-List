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

/// Version 1 of the user-controlled settings payload.
///
/// Launch-at-login is intentionally absent because `SMAppService` is the source
/// of truth for that state.
public struct SettingsV1: Codable, Equatable, Sendable {
    public var presentation: PresentationMode
    public var panelSize: PanelSize
    public var theme: ThemePreference
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

    public init(
        presentation: PresentationMode = .thumbnails,
        panelSize: PanelSize = .auto,
        theme: ThemePreference = .system,
        opacity: Double = 0.88,
        shortcut: ShortcutDefinition = .commandTab,
        spaceScope: SpaceScope = .allSpaces,
        screenScope: ScreenScope = .allScreens,
        includeMinimized: Bool = true,
        includeHiddenApps: Bool = true,
        includeFullscreen: Bool = true,
        excludedBundleIdentifiers: Set<String> = [],
        refreshThumbnailsInBackground: Bool = false,
        showMenuBarIcon: Bool = true,
        automaticallyChecksForUpdates: Bool = true
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
    }

    public static let `default` = SettingsV1()

    /// Returns a safe persisted representation without unexpectedly changing
    /// valid user choices.
    public func normalized() -> SettingsV1 {
        var copy = self
        copy.opacity = min(max(opacity.isFinite ? opacity : Self.default.opacity, 0.70), 1.0)
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
        return copy
    }
}

public typealias TabListSettings = SettingsV1
