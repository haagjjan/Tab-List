import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    var onOpenSettings: (() -> Void)?
    var onToggleEnabled: ((Bool) -> Void)?
    var onOpenPermissions: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var onOpenAbout: (() -> Void)?
    var onQuit: (() -> Void)?
#if DEBUG
    var onOpenDebugInspector: (() -> Void)?
#endif

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let enabledItem = NSMenuItem()
    private let permissionItem = NSMenuItem()
    private let compatibilityItem = NSMenuItem()
    private var isEnabled = true
    private var accessibilityGranted = false
    private var screenRecordingGranted = false

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureStatusItem()
        configureMenu()
    }

    func setVisible(_ visible: Bool) {
        statusItem.isVisible = visible
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        enabledItem.state = enabled ? .on : .off
        enabledItem.title = enabled ? String(localized: "Tab‑List Enabled") : String(localized: "Tab‑List Disabled")
        statusItem.button?.contentTintColor = enabled ? nil : .tertiaryLabelColor
    }

    func updatePermissions(accessibility: Bool, screenRecording: Bool) {
        accessibilityGranted = accessibility
        screenRecordingGranted = screenRecording
        updatePermissionItem()
    }

    func updateCompatibilityWarning(_ warning: String?) {
        compatibilityItem.isHidden = warning == nil
        compatibilityItem.title = String(
            localized: "Compatibility mode — some advanced window features are limited"
        )
        compatibilityItem.toolTip = warning
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "rectangle.3.group",
            accessibilityDescription: String(localized: "Tab‑List")
        )
        button.toolTip = String(localized: "Tab‑List")
        statusItem.menu = menu
    }

    private func configureMenu() {
        menu.delegate = self

        let settings = NSMenuItem(
            title: String(localized: "Open Settings…"),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        enabledItem.title = String(localized: "Tab‑List Enabled")
        enabledItem.target = self
        enabledItem.action = #selector(toggleEnabled)
        enabledItem.state = .on
        menu.addItem(enabledItem)

        menu.addItem(.separator())

        permissionItem.target = self
        permissionItem.action = #selector(openPermissions)
        menu.addItem(permissionItem)

        compatibilityItem.isEnabled = false
        compatibilityItem.isHidden = true
        menu.addItem(compatibilityItem)

        let updates = NSMenuItem(
            title: String(localized: "Check for Updates…"),
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updates.target = self
        menu.addItem(updates)

        menu.addItem(.separator())

#if DEBUG
        let inspector = NSMenuItem(
            title: "Open Window Inspector…",
            action: #selector(openDebugInspector),
            keyEquivalent: ""
        )
        inspector.target = self
        menu.addItem(inspector)
#endif

        let about = NSMenuItem(
            title: String(localized: "About Tab‑List"),
            action: #selector(openAbout),
            keyEquivalent: ""
        )
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(
            title: String(localized: "Quit Tab‑List"),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        updatePermissionItem()
    }

    private func updatePermissionItem() {
        let accessibility = accessibilityGranted ? "✓" : "!"
        let recording = screenRecordingGranted ? "✓" : "–"
        permissionItem.title = String(
            localized: "Permissions  Accessibility \(accessibility)  Thumbnails \(recording)"
        )
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func toggleEnabled() {
        setEnabled(!isEnabled)
        onToggleEnabled?(isEnabled)
    }

    @objc private func openPermissions() {
        onOpenPermissions?()
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates?()
    }

    @objc private func openAbout() {
        onOpenAbout?()
    }

#if DEBUG
    @objc private func openDebugInspector() {
        onOpenDebugInspector?()
    }
#endif

    @objc private func quit() {
        onQuit?()
    }
}
