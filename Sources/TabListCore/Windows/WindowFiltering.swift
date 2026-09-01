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
        settings: TabListSettings,
        context: WindowFilterContext
    ) -> Bool {
        if window.isMinimized && !settings.includeMinimized {
            return false
        }
        if window.isHidden && !settings.includeHiddenApps {
            return false
        }
        if window.isFullscreen && !settings.includeFullscreen {
            return false
        }

        if let bundleIdentifier = window.bundleIdentifier,
           settings.excludedBundleIdentifiers.contains(where: {
               $0.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
           })
        {
            return false
        }

        // Space membership is only known when the WindowServer Space query is
        // available. Without it the scope narrowing is skipped rather than
        // hiding every window.
        if settings.spaceScope == .visibleSpaces,
           !context.visibleSpaceIDs.isEmpty,
           !window.spaceIDs.isEmpty,
           Set(window.spaceIDs).isDisjoint(with: context.visibleSpaceIDs)
        {
            return false
        }

        if settings.screenScope == .pointerScreen,
           let pointerDisplayID = context.pointerDisplayID,
           let displayID = window.displayID,
           displayID != pointerDisplayID
        {
            return false
        }

        return true
    }

    public static func filter(
        _ windows: [WindowRecord],
        settings: TabListSettings,
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
        settings: TabListSettings,
        pointerDisplayID: CGDirectDisplayID?
    ) -> [WindowRecord] {
        let context = WindowFilterContext(
            visibleSpaceIDs: snapshot.visibleSpaceIDs,
            pointerDisplayID: pointerDisplayID
        )
        return MRUOrdering.sorted(
            WindowFilter.filter(
                snapshot.windows,
                settings: settings,
                context: context
            )
        )
    }
}
