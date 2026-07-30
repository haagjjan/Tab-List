@preconcurrency import AppKit
import Foundation
import OSLog
import TabListCore

@main
@MainActor
final class TabListApplication: NSObject, NSApplicationDelegate {
    private static let resumeThumbnailOnboardingArgument =
        "--resume-thumbnail-onboarding"
    private static let logger = Logger(
        subsystem: "com.haagjjan.TabList",
        category: "application"
    )

    private var settingsStore: SettingsStore!
    private var settingsModel: SettingsViewModel!
    private var onboardingModel: OnboardingViewModel!
    private var settingsWindow: SettingsWindowController!
    private var onboardingWindow: OnboardingWindowController!
    private var menuBar: MenuBarController!

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
        accessibility: .notDetermined,
        screenRecording: .notDetermined
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
        guard let startupRegistry = registry else { return }
        Task { [weak self, startupRegistry] in
            _ = await startupRegistry.refresh()
            guard let self else { return }
            self.updateCompatibilityWarning()
            self.session.warmCaches()
        }
        startPermissionMonitoring()

        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing-show-onboarding") {
            onboardingWindow.show()
        } else if arguments.contains("--ui-testing-show-settings") {
            settingsWindow.show()
        } else if !settingsStore.hasCompletedOnboarding {
            onboardingWindow.show()
            resumeThumbnailOnboardingIfRequested()
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

        let inventory = PublicWindowInventory(
            accessibility: accessibility,
            windowServer: windowServer
        )
        registry = WindowRegistry(inventory: inventory)
        registryObserver = WindowRegistryLifecycleObserver(
            registry: registry,
            accessibility: accessibility
        )
        focusMonitor = AccessibilityFocusMonitor(
            windowServer: windowServer
        ) { [weak self, weak registryObserver, weak registry] event in
            switch event {
            case let .focused(key):
                guard GlobalFocusObservationGate.accepts(
                    observedPID: key.pid,
                    frontmostPID: NSWorkspace.shared
                        .frontmostApplication?.processIdentifier
                ) else {
                    return
                }
                Task { [weak registry] in
                    await registry?.noteFocused(key)
                }
            case let .focusChanged(pid):
                guard GlobalFocusObservationGate.accepts(
                    observedPID: pid,
                    frontmostPID: NSWorkspace.shared
                        .frontmostApplication?.processIdentifier
                ) else {
                    return
                }
                Task { [weak self, weak registry] in
                    guard let key = await self?.accessibility
                        .focusedWindowKey(for: pid)
                    else {
                        return
                    }
                    await registry?.noteFocused(key)
                }
            case .inventoryChanged:
                registryObserver?.scheduleRefresh()
            case let .windowDestroyed(key):
                Task { [weak registry] in
                    await registry?.remove(key)
                }
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
        menuBar.setVisible(settingsStore.settings.showMenuBarIcon)

        let actions = WindowActionService(
            registry: registry,
            accessibility: accessibility,
            windowServer: windowServer
        )
        session = SwitcherSessionCoordinator(
            snapshotProvider: registry,
            focusHistoryProvider: registry,
            windowActions: actions,
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
        menuBar.onOpenSettings = { [weak self] in
            self?.openSettings()
        }
        menuBar.onToggleEnabled = { [weak self] enabled in
            self?.setEnabled(enabled)
        }
        menuBar.onOpenPermissions = { [weak self] in
            self?.openPermissionSettings()
        }
        menuBar.onCheckForUpdates = { [weak self] in
            self?.checkForUpdates()
        }
        menuBar.onOpenAbout = { [weak self] in
            self?.showAbout()
        }
        menuBar.onQuit = {
            NSApp.terminate(nil)
        }

        settingsWindow.onWillClose = { [weak self] in
            self?.session.cancel()
        }
        session.onCompatibilityStatusChanged = { [weak self] in
            self?.updateCompatibilityWarning()
        }

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
        settingsModel.onRequestScreenRecording = { [weak self] in
            self?.requestScreenRecording(advanceOnboarding: false)
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
        onboardingModel.onRequestScreenRecording = { [weak self] in
            self?.requestScreenRecording(advanceOnboarding: true)
        }
        onboardingModel.onQuitAndReopen = { [weak self] in
            self?.quitAndReopenForScreenRecording()
        }
        onboardingModel.onContinueWithoutThumbnails = { [weak self] in
            guard let self else { return }
            var settings = self.settingsStore.settings
            settings.presentation = .titles
            self.settingsStore.update(settings)
            self.settingsModel.replaceSettingsWithoutNotification(settings)
            self.session.presentationSettingsChanged()
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
            }
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
                    self?.registryObserver.refreshNow()
                    self?.focusMonitor.refresh()
                    self?.recoverShortcutAfterSystemTransition()
                    self?.synchronizeBackgroundRefresh()
                }
            }
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
                    self?.registryObserver.refreshNow()
                    self?.focusMonitor.refresh()
                    self?.recoverShortcutAfterSystemTransition()
                    self?.synchronizeBackgroundRefresh()
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
        notificationTokens.forEach(
            NotificationCenter.default.removeObserver
        )
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

        let accessibilityGranted = status.accessibility == .authorized
        let screenRecordingGranted = status.screenRecording == .authorized
        settingsModel.accessibilityGranted = accessibilityGranted
        settingsModel.screenRecordingGranted = screenRecordingGranted
        onboardingModel.accessibilityGranted = accessibilityGranted
        onboardingModel.screenRecordingGranted = screenRecordingGranted
        menuBar.updatePermissions(
            accessibility: accessibilityGranted,
            screenRecording: screenRecordingGranted
        )
        session.updateThumbnailCaptureAuthorization(
            screenRecordingGranted
        )

        if status.accessibility == .authorized,
           previous.accessibility != .authorized {
            focusMonitor.start()
            registerConfiguredShortcutIfPossible(
                allowDuringOnboarding: onboardingModel.step == .ready
            )
        } else if status.accessibility != .authorized,
                  previous.accessibility == .authorized {
            session.cancel()
            shortcutService.unregister()
            focusMonitor.stop()
        }

        if status.screenRecording == .authorized,
           onboardingModel.screenRecordingRestartRequired {
            onboardingModel.showReady()
        }
        synchronizeBackgroundRefresh()
    }

    private func applySettings(_ settings: SettingsV1) {
        let previous = settingsStore.settings
        let registrationRequired =
            previous.shortcut != settings.shortcut
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
        updateCompatibilityWarning()

        menuBar.setVisible(committed.showMenuBarIcon)
        updateController.setAutomaticallyChecksForUpdates(
            committed.automaticallyChecksForUpdates
        )

        if previous.presentation != committed.presentation
            || previous.panelSize != committed.panelSize
            || previous.theme != committed.theme
            || previous.opacity != committed.opacity
        {
            session.presentationSettingsChanged()
        }
        synchronizeBackgroundRefresh()
    }

    private func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        menuBar.setEnabled(enabled)
        if enabled {
            registerConfiguredShortcutIfPossible()
            synchronizeBackgroundRefresh()
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
            try shortcutService.register(shortcut) { [weak self] command in
                self?.session.handle(command)
            }
            settingsModel.shortcutValidationMessage = nil
            return true
        } catch {
            settingsModel.shortcutValidationMessage = String(
                localized: "The shortcut could not be registered. The previous shortcut remains active."
            )
            Self.logger.error(
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
              settingsStore.hasCompletedOnboarding
                || allowDuringOnboarding,
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

    private func requestScreenRecording(advanceOnboarding: Bool) {
        guard let service = permissionService else { return }
        onboardingModel.isRequesting = true
        Task { [weak self, service] in
            let result = await service.requestScreenRecordingResult()
            guard let self else { return }
            self.onboardingModel.isRequesting = false
            self.applyPermissionStatus(result.status)

            if result.requiresRestart {
                self.onboardingModel.screenRecordingRestartRequired = true
            } else {
                self.onboardingModel.screenRecordingRestartRequired = false
                if advanceOnboarding,
                   result.status.screenRecording == .authorized {
                    self.onboardingModel.showReady()
                }
            }
        }
    }

    private func resumeThumbnailOnboardingIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains(
            Self.resumeThumbnailOnboardingArgument
        ) else {
            return
        }
        guard let service = permissionService else { return }
        Task { [weak self, service] in
            let status = await service.currentStatus()
            guard let self else { return }
            self.applyPermissionStatus(status)
            if status.accessibility != .authorized {
                self.onboardingModel.step = .accessibility
            } else if status.screenRecording == .authorized {
                self.onboardingModel.showReady()
            } else {
                self.onboardingModel.step = .thumbnails
                self.onboardingModel.screenRecordingRestartRequired = false
            }
        }
    }

    private func quitAndReopenForScreenRecording() {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension.caseInsensitiveCompare("app")
                == .orderedSame else {
            showAlert(
                title: String(localized: "Tab‑List could not restart"),
                message: String(
                    localized: "Quit Tab‑List and open it again to finish enabling thumbnail previews."
                )
            )
            return
        }

        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = [
            "-c",
            """
            while kill -0 "$1" 2>/dev/null; do
                /bin/sleep 0.1
            done
            exec /usr/bin/open "$2" --args "$3"
            """,
            "tab-list-relaunch",
            String(ProcessInfo.processInfo.processIdentifier),
            bundleURL.path,
            Self.resumeThumbnailOnboardingArgument,
        ]
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice

        do {
            try helper.run()
            NSApp.terminate(nil)
        } catch {
            showAlert(
                title: String(localized: "Tab‑List could not restart"),
                message: String(
                    localized: "Quit Tab‑List and open it again to finish enabling thumbnail previews."
                )
            )
        }
    }

    private func openPermissionSettings() {
        if permissions.accessibility != .authorized {
            permissionService.openAccessibilitySettings()
        } else if permissions.screenRecording != .authorized {
            permissionService.openScreenRecordingSettings()
        } else {
            permissionService.openAccessibilitySettings()
        }
    }

    private func synchronizeBackgroundRefresh() {
        session.updateBackgroundRefresh(
            enabled: isEnabled
                && permissions.screenRecording == .authorized
        )
    }

    private func updateCompatibilityWarning() {
        let report = windowServer.capabilityReport
        let thumbnailCaptureIsDegraded =
            settingsStore.settings.presentation == .thumbnails
                && ProcessInfo.processInfo.operatingSystemVersion
                    .majorVersion == 15
                && !report.operational.contains(.hardwareCapture)
        let warning = report.usesPublicFallbacks
            || thumbnailCaptureIsDegraded
            ? String(
                localized: "Some private macOS window capabilities are unavailable. Current-Space switching remains available through public fallbacks; cross-Space activation or previews may be limited on this system."
            )
            : nil
        settingsModel.compatibilityWarning = warning
        menuBar.updateCompatibilityWarning(warning)
    }

    private func recoverShortcutAfterSystemTransition() {
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

    private func openSettings() {
        session.cancel()
        updateLaunchAtLoginState()
        settingsWindow.show()
    }

    private func updateLaunchAtLoginState() {
        let state = launchAtLogin.state
        settingsModel.launchAtLoginEnabled = state == .enabled
        settingsModel.launchAtLoginRequiresApproval =
            state == .requiresApproval
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
        guard let registry,
              let permissionService,
              let windowServer
        else {
            return
        }
        Task { [weak self, registry, permissionService, windowServer] in
            let snapshot = await registry.snapshot(
                forceRefreshIfStale: true
            )
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
                    title: String(localized: "Diagnostics could not be exported"),
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
