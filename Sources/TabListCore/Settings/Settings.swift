import Foundation

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

/// User-controlled preferences.
///
/// Launch-at-login is absent because `SMAppService` owns that state. Unknown
/// keys from an older payload are ignored, and every field decodes with a
/// default, so preferences written by earlier schema versions still load.
public struct TabListSettings: Codable, Equatable, Sendable {
    public var theme: ThemePreference
    public var shortcut: ShortcutDefinition
    public var spaceScope: SpaceScope
    public var screenScope: ScreenScope
    public var includeMinimized: Bool
    public var includeHiddenApps: Bool
    public var includeFullscreen: Bool
    public var excludedBundleIdentifiers: Set<String>
    public var showMenuBarIcon: Bool
    public var automaticallyChecksForUpdates: Bool
    public var reverseControl: ReverseControlDefinition
    public var holdCycleSpeed: Double

    public init(
        theme: ThemePreference = .system,
        shortcut: ShortcutDefinition = .commandTab,
        spaceScope: SpaceScope = .allSpaces,
        screenScope: ScreenScope = .allScreens,
        includeMinimized: Bool = true,
        includeHiddenApps: Bool = true,
        includeFullscreen: Bool = true,
        excludedBundleIdentifiers: Set<String> = [],
        showMenuBarIcon: Bool = true,
        automaticallyChecksForUpdates: Bool = true,
        reverseControl: ReverseControlDefinition = .shiftWithForwardKey,
        holdCycleSpeed: Double = 1.0
    ) {
        self.theme = theme
        self.shortcut = shortcut
        self.spaceScope = spaceScope
        self.screenScope = screenScope
        self.includeMinimized = includeMinimized
        self.includeHiddenApps = includeHiddenApps
        self.includeFullscreen = includeFullscreen
        self.excludedBundleIdentifiers = excludedBundleIdentifiers
        self.showMenuBarIcon = showMenuBarIcon
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        self.reverseControl = reverseControl
        self.holdCycleSpeed = holdCycleSpeed
    }

    public static let `default` = TabListSettings()

    public func normalized() -> Self {
        var copy = self
        copy.excludedBundleIdentifiers = Set(
            excludedBundleIdentifiers.compactMap { identifier in
                let trimmed = identifier
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        )
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
        case theme
        case shortcut
        case spaceScope
        case screenScope
        case includeMinimized
        case includeHiddenApps
        case includeFullscreen
        case excludedBundleIdentifiers
        case showMenuBarIcon
        case automaticallyChecksForUpdates
        case reverseControl
        case holdCycleSpeed
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self.default
        self.init(
            theme: try values.decodeIfPresent(
                ThemePreference.self,
                forKey: .theme
            ) ?? fallback.theme,
            shortcut: try values.decodeIfPresent(
                ShortcutDefinition.self,
                forKey: .shortcut
            ) ?? fallback.shortcut,
            spaceScope: try values.decodeIfPresent(
                SpaceScope.self,
                forKey: .spaceScope
            ) ?? fallback.spaceScope,
            screenScope: try values.decodeIfPresent(
                ScreenScope.self,
                forKey: .screenScope
            ) ?? fallback.screenScope,
            includeMinimized: try values.decodeIfPresent(
                Bool.self,
                forKey: .includeMinimized
            ) ?? fallback.includeMinimized,
            includeHiddenApps: try values.decodeIfPresent(
                Bool.self,
                forKey: .includeHiddenApps
            ) ?? fallback.includeHiddenApps,
            includeFullscreen: try values.decodeIfPresent(
                Bool.self,
                forKey: .includeFullscreen
            ) ?? fallback.includeFullscreen,
            excludedBundleIdentifiers: try values.decodeIfPresent(
                Set<String>.self,
                forKey: .excludedBundleIdentifiers
            ) ?? fallback.excludedBundleIdentifiers,
            showMenuBarIcon: try values.decodeIfPresent(
                Bool.self,
                forKey: .showMenuBarIcon
            ) ?? fallback.showMenuBarIcon,
            automaticallyChecksForUpdates: try values.decodeIfPresent(
                Bool.self,
                forKey: .automaticallyChecksForUpdates
            ) ?? fallback.automaticallyChecksForUpdates,
            reverseControl: try values.decodeIfPresent(
                ReverseControlDefinition.self,
                forKey: .reverseControl
            ) ?? fallback.reverseControl,
            holdCycleSpeed: try values.decodeIfPresent(
                Double.self,
                forKey: .holdCycleSpeed
            ) ?? fallback.holdCycleSpeed
        )
    }
}
