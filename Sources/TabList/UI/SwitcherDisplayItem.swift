import AppKit
import TabListCore

/// UI-ready representation of one macOS window. Window content stays in memory
/// and is never persisted by the presentation layer.
struct SwitcherDisplayItem {
    let window: WindowRecord
    let icon: NSImage

    var title: String {
        window.windowTitle.isEmpty
            ? String(localized: "Untitled window")
            : window.windowTitle
    }

    var stateDescriptions: [String] {
        var states: [String] = []
        if window.isMinimized { states.append(String(localized: "Minimized")) }
        if window.isHidden { states.append(String(localized: "Hidden")) }
        if window.isFullscreen {
            states.append(String(localized: "Full Screen"))
        }
        return states
    }

    func hasSameRenderedContent(as other: Self) -> Bool {
        window == other.window && icon === other.icon
    }

    func accessibilityLabel(position: Int, total: Int) -> String {
        var states: [String] = []
        if window.isMinimized { states.append(String(localized: "minimized")) }
        if window.isHidden { states.append(String(localized: "hidden")) }
        if window.isFullscreen {
            states.append(String(localized: "full screen"))
        }
        let suffix = states.isEmpty
            ? ""
            : ", " + states.joined(separator: ", ")
        return "\(window.applicationName), \(title)\(suffix) — \(position) of \(total)"
    }
}
