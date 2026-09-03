@preconcurrency import AppKit
import Foundation
import TabListCore

@main
@MainActor
final class TabListApplication: NSObject, NSApplicationDelegate {
    private var settingsStore: SettingsStore!
    private var settingsModel: SettingsViewModel!
    private var onboardingModel: OnboardingViewModel!
    private var settingsWindow: SettingsWindowController!
    private var onboardingWindow: OnboardingWindowController!
    private var menuBar: MenuBarController!
#if DEBUG
    private var debugInspector: DebugInspectorWindowController!
#endif

    private var permissionService: PermissionService!
    private var windowServer: WindowServerBridge!
    private var accessibility: AccessibilityBridge!
    private var registry: WindowRegistry!
    private var registryObserver: WindowRegistryLifecycleObserver!
    private var focusMonitor: AccessibilityFocusMonitor!
    private var shortcutService: GlobalShortcutService!
    private var launchAtLogin: LaunchAtLoginService!
    private var updateController: UpdateController!
    private var session: SwitcherSessionCoordinator!

    private var permissions = SystemPermissionSnapshot(
        accessibility: .notDetermined
    )
    private var permissionTask: Task<Void, Never>?
    private var notificationTokens: [any NSObjectProtocol] = []
    private var workspaceNotificationTokens: [any NSObjectProtocol] = []
    private var distributedNotificationTokens: [any NSObjectProtocol] = []
    private var memoryPressureSource: (any DispatchSourceMemoryPressure)?
    private var isEnabled = true
    private let globalShortcutIsDisabledForTesting =
        ProcessInfo.processInfo.environment[
            "TABLIST_DISABLE_GLOBAL_SHORTCUT"
        ] == "1"

    static func main() {
        let application = NSApplication.shared
        let delegate = TabListApplication()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildRuntime()
        configureCallbacks()
        configureLifecycleHandling()

        registryObserver.start()
        if let startupRegistry = registry {
            Task { [weak self, startupRegistry] in
                _ = await startupRegistry.refresh()
                guard let self else { return }
                self.updateCompatibilityWarning()
                self.session.warmCaches()
            }
        }
        startPermissionMonitoring()

        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing-show-onboarding") {
            onboardingWindow.show()
        } else if arguments.contains("--ui-testing-show-settings") {
            settingsWindow.show()
        } else if !settingsStore.hasCompletedOnboarding {
            onboardingWindow.show()
        } else if !settingsStore.settings.showMenuBarIcon {
            // Keep Settings reachable when the status item was deliberately
            // hidden during the previous launch.
            settingsWindow.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTask?.cancel()
        permissionTask = nil
        shortcutService.unregister()
        session.shutdown()
        registryObserver.stop()
        focusMonitor.stop()
        removeLifecycleHandling()
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            settingsWindow.show()
        }
        return true
    }

    private func buildRuntime() {
        settingsStore = SettingsStore()
        permissionService = PermissionService()
        windowServer = WindowServerBridge()
        accessibility = AccessibilityBridge(windowServer: windowServer)

        registry = WindowRegistry(
            inventory: WindowInventory(
                accessibility: accessibility,
                windowServer: windowServer
            )
        )
        registryObserver = WindowRegistryLifecycleObserver(
            registry: registry,
            accessibility: accessibility
        )
        focusMonitor = AccessibilityFocusMonitor {
            [weak registryObserver] event in
            switch event {
            case let .focusChanged(pid):
                registryObserver?.noteFocusChanged(pid: pid)
            case .inventoryChanged:
                registryObserver?.scheduleRefresh()
            }
        }

        shortcutService = GlobalShortcutService()
        launchAtLogin = LaunchAtLoginService()
        updateController = UpdateController(
            automaticallyChecksForUpdates:
                settingsStore.settings.automaticallyChecksForUpdates
        )

        settingsModel = SettingsViewModel(settings: settingsStore.settings)
        onboardingModel = OnboardingViewModel()
        settingsWindow = SettingsWindowController(model: settingsModel)
        onboardingWindow = OnboardingWindowController(model: onboardingModel)
        menuBar = MenuBarController()
#if DEBUG
        debugInspector = DebugInspectorWindowController()
#endif
        menuBar.setVisible(settingsStore.settings.showMenuBarIcon)

        session = SwitcherSessionCoordinator(
            snapshotProvider: registry,
            focusHistoryProvider: registry,
            windowActions: WindowActionService(
                registry: registry,
                accessibility: accessibility,
                windowServer: windowServer
            ),
            shortcutService: shortcutService,
            iconCache: AppIconCache(),
            panelController: SwitcherPanelController(),
            settingsProvider: { [weak self] in
                self?.settingsStore.settings ?? .default
            }
        )

        updateLaunchAtLoginState()
        updateCompatibilityWarning()
    }

    private func configureCallbacks() {
        menuBar.onOpenSettings = { [weak self] in self?.openSettings() }
        menuBar.onToggleEnabled = { [weak self] enabled in
            self?.setEnabled(enabled)
        }
        menuBar.onOpenPermissions = { [weak self] in
            self?.openPermissionSettings()
        }
        menuBar.onCheckForUpdates = { [weak self] in self?.checkForUpdates() }
        menuBar.onOpenAbout = { [weak self] in self?.showAbout() }
        menuBar.onQuit = { NSApp.terminate(nil) }
#if DEBUG
        menuBar.onOpenDebugInspector = { [weak self] in
            guard let self else { return }
            self.debugInspector.show(
                registry: self.registry,
                windowServer: self.windowServer
            )
        }
#endif

        settingsWindow.onWillClose = { [weak self] in self?.session.cancel() }

        settingsModel.onSettingsChanged = { [weak self] settings in
            self?.applySettings(settings)
        }
        settingsModel.onShortcutChanged = { [weak self] shortcut in
            guard let self else { return false }
            return self.replaceShortcut(with: shortcut)
        }
        settingsModel.onLaunchAtLoginChanged = { [weak self] enabled in
            guard let self else { return false }
            return self.setLaunchAtLogin(enabled)
        }
        settingsModel.onRequestAccessibility = { [weak self] in
            self?.requestAccessibility()
        }
        settingsModel.onOpenPermissions = { [weak self] in
            self?.openPermissionSettings()
        }
        settingsModel.onCheckForUpdates = { [weak self] in
            self?.checkForUpdates()
        }
        settingsModel.onExportDiagnostics = { [weak self] in
            self?.exportDiagnostics()
        }
        onboardingModel.onRequestAccessibility = { [weak self] in
            self?.requestAccessibility()
        }
        onboardingModel.onOpenAccessibilitySettings = { [weak self] in
            self?.openPermissionSettings()
        }
        onboardingModel.onReady = { [weak self] in
            self?.registerConfiguredShortcutIfPossible(
                allowDuringOnboarding: true
            )
        }
        onboardingModel.onFinish = { [weak self] in
            guard let self else { return }
            self.settingsStore.hasCompletedOnboarding = true
            self.onboardingWindow.close()
            self.registerConfiguredShortcutIfPossible()
        }
    }

    private func configureLifecycleHandling() {
        let center = NotificationCenter.default
        notificationTokens = [
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.session.cancel() }
            },
        ]
        workspaceNotificationTokens = [
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.session.shutdown()
                    self?.session.handleMemoryPressure()
                }
            },
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.recoverAfterSystemTransition()
                }
            },
        ]

        let distributed = DistributedNotificationCenter.default()
        distributedNotificationTokens = [
            distributed.addObserver(
                forName: .init("com.apple.screenIsLocked"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.session.shutdown()
                    self?.session.handleMemoryPressure()
                }
            },
            distributed.addObserver(
                forName: .init("com.apple.screenIsUnlocked"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.recoverAfterSystemTransition()
                }
            },
        ]

        let pressure = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        pressure.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.session.handleMemoryPressure()
            }
        }
        pressure.resume()
        memoryPressureSource = pressure
    }

    private func removeLifecycleHandling() {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        notificationTokens.removeAll()
        workspaceNotificationTokens.forEach(
            NSWorkspace.shared.notificationCenter.removeObserver
        )
        workspaceNotificationTokens.removeAll()

        let distributed = DistributedNotificationCenter.default()
        distributedNotificationTokens.forEach(distributed.removeObserver)
        distributedNotificationTokens.removeAll()
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
    }

    private func startPermissionMonitoring() {
        permissionTask?.cancel()
        guard let service = permissionService else { return }
        permissionTask = Task { [weak self, service] in
            let updates = await service.statusUpdates()
            for await status in updates {
                guard let self, !Task.isCancelled else { return }
                self.applyPermissionStatus(status)
            }
        }
    }

    private func applyPermissionStatus(_ status: SystemPermissionSnapshot) {
        let previous = permissions
        permissions = status
        if status != previous {
            TabListLog.permissions.notice(
                "Accessibility permission is now \(status.accessibility.rawValue, privacy: .public)"
            )
        }

        let granted = status.accessibility == .authorized
        settingsModel.accessibilityGranted = granted
        onboardingModel.accessibilityGranted = granted
        menuBar.updatePermissions(accessibility: granted)

        if granted, previous.accessibility != .authorized {
            focusMonitor.start()
            registryObserver.refreshNow()
            registerConfiguredShortcutIfPossible(
                allowDuringOnboarding: onboardingModel.step == .ready
            )
            updateCompatibilityWarning()
        } else if !granted, previous.accessibility == .authorized {
            session.cancel()
            shortcutService.unregister()
            focusMonitor.stop()
        }
    }

    private func applySettings(_ settings: TabListSettings) {
        let previous = settingsStore.settings
        let registrationRequired = previous.shortcut != settings.shortcut
            && shortcutService.registeredShortcut != settings.shortcut
        let registrationSucceeded = !registrationRequired
            || replaceShortcut(with: settings.shortcut)
        let committed = SettingsTransaction.committed(
            previous: previous,
            requested: settings,
            shortcutRegistrationRequired: registrationRequired,
            shortcutRegistrationSucceeded: registrationSucceeded
        )
        if registrationRequired, !registrationSucceeded {
            settingsModel.replaceSettingsWithoutNotification(committed)
        }
        settingsStore.update(committed)
        shortcutService.configureSessionControls(
            reverseControl: committed.reverseControl,
            holdCycleSpeed: committed.holdCycleSpeed
        )
        updateCompatibilityWarning()

        menuBar.setVisible(committed.showMenuBarIcon)
        updateController.setAutomaticallyChecksForUpdates(
            committed.automaticallyChecksForUpdates
        )

        if previous.theme != committed.theme {
            session.appearanceSettingsChanged()
        }
    }

    private func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        menuBar.setEnabled(enabled)
        if enabled {
            registerConfiguredShortcutIfPossible()
        } else {
            session.shutdown()
            shortcutService.unregister()
        }
    }

    @discardableResult
    private func replaceShortcut(with shortcut: ShortcutDefinition) -> Bool {
        if globalShortcutIsDisabledForTesting {
            return true
        }
        if shortcutService.registeredShortcut == shortcut {
            return true
        }
        guard isEnabled, permissions.accessibility == .authorized else {
            return permissions.accessibility == .authorized
        }
        do {
            let controls = settingsStore.settings
            shortcutService.configureSessionControls(
                reverseControl: controls.reverseControl,
                holdCycleSpeed: controls.holdCycleSpeed
            )
            try shortcutService.register(shortcut) { [weak self] command in
                self?.session.handle(command)
            }
            settingsModel.shortcutValidationMessage = nil
            return true
        } catch {
            settingsModel.shortcutValidationMessage = String(
                localized: "The shortcut could not be registered. The previous shortcut remains active."
            )
            TabListLog.input.error(
                "Global shortcut registration failed: \(String(describing: error), privacy: .public)"
            )
            return false
        }
    }

    private func registerConfiguredShortcutIfPossible(
        allowDuringOnboarding: Bool = false
    ) {
        guard !globalShortcutIsDisabledForTesting,
              isEnabled,
              settingsStore.hasCompletedOnboarding || allowDuringOnboarding,
              permissions.accessibility == .authorized,
              shortcutService.registeredShortcut
                != settingsStore.settings.shortcut
        else {
            return
        }
        _ = replaceShortcut(with: settingsStore.settings.shortcut)
    }

    private func requestAccessibility() {
        guard let service = permissionService else { return }
        Task { [weak self, service] in
            let status = await service.requestAccessibility()
            self?.applyPermissionStatus(status)
        }
    }

    private func openPermissionSettings() {
        permissionService.openAccessibilitySettings()
    }

    private func recoverAfterSystemTransition() {
        registryObserver.refreshNow()
        focusMonitor.refresh()
        guard isEnabled,
              settingsStore.hasCompletedOnboarding,
              permissions.accessibility == .authorized,
              !globalShortcutIsDisabledForTesting
        else {
            return
        }
        do {
            try shortcutService.recoverAfterSystemTransition()
        } catch {
            shortcutService.unregister()
            settingsModel.shortcutValidationMessage = String(
                localized: "Tab‑List could not restore its shortcut after wake. Toggle Tab‑List off and on to retry."
            )
        }
    }

    private func updateCompatibilityWarning() {
        let warning = windowServer.capabilityReport.usesPublicFallbacks
            ? String(
                localized: "This system does not expose the private Space queries Tab‑List uses for desktop filtering. Every window still appears and can be activated; the “Visible now” scope falls back to showing all desktops."
            )
            : nil
        settingsModel.compatibilityWarning = warning
        menuBar.updateCompatibilityWarning(warning)
    }

    private func openSettings() {
        session.cancel()
        updateLaunchAtLoginState()
        settingsWindow.show()
    }

    private func updateLaunchAtLoginState() {
        let state = launchAtLogin.state
        settingsModel.launchAtLoginEnabled = state == .enabled
        settingsModel.launchAtLoginRequiresApproval = state == .requiresApproval
    }

    private func setLaunchAtLogin(_ enabled: Bool) -> Bool {
        do {
            try launchAtLogin.setEnabled(enabled)
        } catch {
            if case LaunchAtLoginError.requiresUserApproval = error {
                settingsModel.launchAtLoginRequiresApproval = true
                launchAtLogin.openSystemSettings()
            }
            updateLaunchAtLoginState()
            return false
        }
        updateLaunchAtLoginState()
        switch launchAtLogin.state {
        case .enabled:
            return enabled
        case .disabled, .notFound:
            return !enabled
        case .requiresApproval:
            return false
        }
    }

    private func checkForUpdates() {
        guard updateController.checkForUpdates() else {
            showAlert(
                title: String(localized: "Updates are not configured"),
                message: String(
                    localized: "Set the Sparkle public EdDSA key in the Release build configuration before publishing Tab‑List."
                )
            )
            return
        }
    }

    private func exportDiagnostics() {
        guard let registry, let permissionService, let windowServer else {
            return
        }
        Task { [weak self, registry, permissionService, windowServer] in
            let snapshot = await registry.snapshot(forceRefreshIfStale: true)
            let permissions = await permissionService.currentStatus()
            let report = DiagnosticsService.makeReport(
                permissions: permissions,
                capabilities: windowServer.capabilityReport,
                snapshot: snapshot
            )

            guard let self else { return }
            let panel = NSSavePanel()
            panel.title = String(localized: "Export Redacted Diagnostics")
            panel.nameFieldStringValue = "Tab-List-Diagnostics.json"
            guard panel.runModal() == .OK, let url = panel.url else { return }

            do {
                try await DiagnosticsService.export(report, to: url)
            } catch {
                self.showAlert(
                    title: String(
                        localized: "Diagnostics could not be exported"
                    ),
                    message: error.localizedDescription
                )
            }
        }
    }

    private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(
            options: [
                .applicationName: "Tab‑List",
                .credits: NSAttributedString(
                    string: "MIT licensed. Inspired by AltTab’s window-switching interaction; implemented independently without AltTab code or assets."
                ),
            ]
        )
    }

    private func showAlert(title: String, message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }
}
