import AppKit
import TabListCore

/// UI-ready representation of one macOS window. Window content remains in memory
/// and is never persisted by the presentation layer.
struct SwitcherDisplayItem {
    let window: WindowRecord
    let icon: NSImage
    let thumbnail: CGImage?

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
}
