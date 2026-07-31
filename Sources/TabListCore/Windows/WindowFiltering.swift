import CoreGraphics
import Foundation

public struct WindowFilterContext: Equatable, Sendable {
    public var visibleSpaceIDs: Set<UInt64>
    public var pointerDisplayID: CGDirectDisplayID?

    public init(
        visibleSpaceIDs: Set<UInt64>,
        pointerDisplayID: CGDirectDisplayID?
    ) {
        self.visibleSpaceIDs = visibleSpaceIDs
        self.pointerDisplayID = pointerDisplayID
    }
}

public enum WindowFilter {
    public static func includes(
        _ window: WindowRecord,
        settings: SettingsV1,
        context: WindowFilterContext
    ) -> Bool {
        guard window.isStandardWindow, window.isActionable else {
            return false
        }

        if window.isMinimized && !settings.includeMinimized {
            return false
        }
        if window.isHidden && !settings.includeHiddenApps {
            return false
        }
        if window.isFullscreen && !settings.includeFullscreen {
            return false
        }

        if let bundleIdentifier = window.bundleIdentifier {
            let isExcluded = settings.excludedBundleIdentifiers.contains {
                $0.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
            }
            if isExcluded {
                return false
            }
        }

        if settings.spaceScope == .visibleSpaces {
            guard !context.visibleSpaceIDs.isEmpty,
                  !Set(window.spaceIDs).isDisjoint(with: context.visibleSpaceIDs)
            else {
                return false
            }
        }

        if settings.screenScope == .pointerScreen,
           let pointerDisplayID = context.pointerDisplayID,
           window.displayID != pointerDisplayID
        {
            return false
        }

        return true
    }

    public static func filter(
        _ windows: [WindowRecord],
        settings: SettingsV1,
        context: WindowFilterContext
    ) -> [WindowRecord] {
        windows.filter {
            includes($0, settings: settings, context: context)
        }
    }
}

public enum WindowSelectionPipeline {
    /// Applies user filters and returns a deterministic window-level MRU list.
    public static func candidates(
        from snapshot: WindowSnapshot,
        settings: SettingsV1,
        pointerDisplayID: CGDirectDisplayID?
    ) -> [WindowRecord] {
        let context = WindowFilterContext(
            visibleSpaceIDs: snapshot.visibleSpaceIDs,
            pointerDisplayID: pointerDisplayID
        )
        return MRUOrdering.sorted(
            WindowFilter.filter(snapshot.windows, settings: settings, context: context)
        )
    }
}
