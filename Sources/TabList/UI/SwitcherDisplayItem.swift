import AppKit
import TabListCore

/// UI-ready representation of one macOS window. Window content remains in memory
/// and is never persisted by the presentation layer.
struct SwitcherDisplayItem {
    let window: WindowRecord
    let icon: NSImage
    let thumbnail: CGImage?

    func hasSameRenderedContent(as other: Self) -> Bool {
        window == other.window
            && icon === other.icon
            && Self.sameImage(thumbnail, other.thumbnail)
    }

    func accessibilityLabel(position: Int, total: Int) -> String {
        let title = window.windowTitle.isEmpty ? String(localized: "Untitled window") : window.windowTitle
        var states: [String] = []
        if window.isMinimized { states.append(String(localized: "minimized")) }
        if window.isFullscreen { states.append(String(localized: "full screen")) }
        let stateDescription = states.isEmpty
            ? ""
            : ", " + states.joined(separator: ", ")
        return "\(window.applicationName), \(title)\(stateDescription) — \(position) of \(total)"
    }

    private static func sameImage(
        _ lhs: CGImage?,
        _ rhs: CGImage?
    ) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return lhs === rhs
        default:
            return false
        }
    }
}

enum SwitcherDisplayReloadPlanner {
    static func keys(
        previous: [SwitcherDisplayItem],
        next: [SwitcherDisplayItem],
        forceReload: Bool
    ) -> Set<WindowKey> {
        let previousByKey = previous.enumerated().reduce(
            into: [WindowKey: (index: Int, item: SwitcherDisplayItem)]()
        ) { result, pair in
            result[pair.element.window.id] = (
                index: pair.offset,
                item: pair.element
            )
        }
        let countChanged = previous.count != next.count

        return Set(next.enumerated().compactMap { index, item in
            guard let old = previousByKey[item.window.id] else {
                return nil
            }
            return forceReload
                || countChanged
                || old.index != index
                || !item.hasSameRenderedContent(as: old.item)
                ? item.window.id
                : nil
        })
    }
}
