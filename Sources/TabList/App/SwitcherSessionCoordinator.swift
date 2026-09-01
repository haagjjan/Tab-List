@preconcurrency import AppKit
import CoreGraphics
import Foundation
import OSLog
import TabListCore

private struct QueuedShortcutCycle: Sendable {
    let direction: SwitcherDirection
    let isRepeat: Bool
}

/// Owns one switcher session: it turns shortcut input into reducer actions and
/// performs the effects the reducer returns.
@MainActor
final class SwitcherSessionCoordinator {
    private static let signposter = OSSignposter(
        subsystem: TabListLog.subsystem,
        category: "switcher-performance"
    )
    private static let iconPointSize: CGFloat = 32
    private static let sessionPollInterval = Duration.milliseconds(400)

    private let snapshotProvider: any WindowSnapshotProviding
    private let focusHistoryProvider: any WindowFocusHistoryProviding
    private let windowActions: any WindowActuating
    private let shortcutService: GlobalShortcutService
    private let iconCache: any AppIconProviding
    private let panelController: SwitcherPanelController
    private let settingsProvider: () -> TabListSettings

    private var state = SwitcherSessionState()
    private var preparationTask: Task<Void, Never>?
    private var renderingTask: Task<Void, Never>?
    private var registryPollingTask: Task<Void, Never>?
    private var focusResolutionTask: Task<Void, Never>?

    private var sessionGeneration: UInt64 = 0
    private var resolvingInitialFocus = false
    private var queuedDirectionsBeforeBegin: [QueuedShortcutCycle] = []
    private var commitWhenPrepared = false
    private var prefetchedOpeningSnapshot: WindowSnapshot?
    private var sessionPointerDisplayID: CGDirectDisplayID?
    private var appearanceSignpost: OSSignpostIntervalState?

    init(
        snapshotProvider: any WindowSnapshotProviding,
        focusHistoryProvider: any WindowFocusHistoryProviding,
        windowActions: any WindowActuating,
        shortcutService: GlobalShortcutService,
        iconCache: any AppIconProviding,
        panelController: SwitcherPanelController,
        settingsProvider: @escaping () -> TabListSettings
    ) {
        self.snapshotProvider = snapshotProvider
        self.focusHistoryProvider = focusHistoryProvider
        self.windowActions = windowActions
        self.shortcutService = shortcutService
        self.iconCache = iconCache
        self.panelController = panelController
        self.settingsProvider = settingsProvider

        panelController.onActivate = { [weak self] key in
            self?.activateFromPointer(key)
        }
        panelController.onClose = { [weak self] key in
            self?.closeFromPointer(key)
        }
    }

    deinit {
        preparationTask?.cancel()
        renderingTask?.cancel()
        registryPollingTask?.cancel()
        focusResolutionTask?.cancel()
    }

    var isActive: Bool {
        state.phase != .idle || resolvingInitialFocus
    }

    func handle(_ command: ShortcutInputCommand) {
        switch command {
        case let .begin(reverse):
            begin(reverse: reverse)
        case let .cycle(reverse, isRepeat):
            let direction: SwitcherDirection = reverse ? .backward : .forward
            if resolvingInitialFocus {
                queuedDirectionsBeforeBegin.append(
                    QueuedShortcutCycle(
                        direction: direction,
                        isRepeat: isRepeat
                    )
                )
            } else {
                apply(isRepeat ? .repeatedCycle(direction) : .cycle(direction))
            }
        case .commit:
            if resolvingInitialFocus {
                commitWhenPrepared = true
            } else {
                apply(.modifierReleased)
            }
        case .cancel:
            cancel()
        case .closeSelectedWindow:
            apply(.closeSelected)
        }
    }

    func cancel() {
        guard resolvingInitialFocus else {
            apply(.cancel)
            return
        }
        resolvingInitialFocus = false
        focusResolutionTask?.cancel()
        focusResolutionTask = nil
        queuedDirectionsBeforeBegin.removeAll(keepingCapacity: true)
        commitWhenPrepared = false
        sessionPointerDisplayID = nil
        sessionGeneration &+= 1
        shortcutService.setSessionActive(false)
        endAppearanceSignpost()
    }

    func appearanceSettingsChanged() {
        guard state.phase == .visible else { return }
        scheduleRendering(present: true)
    }

    func warmCaches() {
        Task(priority: .utility) { [weak self, snapshotProvider] in
            let snapshot = await snapshotProvider.snapshot(
                forceRefreshIfStale: false
            )
            guard let self else { return }
            var seen: Set<String> = []
            for window in snapshot.windows {
                let identity = window.bundleIdentifier
                    ?? window.bundleURL?.standardizedFileURL.path
                    ?? "pid:\(window.id.pid)"
                guard seen.insert(identity).inserted else { continue }
                _ = await self.iconCache.icon(
                    for: window.bundleIdentifier,
                    bundleURL: window.bundleURL,
                    targetSize: Self.iconPointSize
                )
            }
        }
    }

    func handleMemoryPressure() {
        iconCache.purgeMemory()
    }

    func shutdown() {
        sessionGeneration &+= 1
        state = SwitcherSessionState()
        resolvingInitialFocus = false
        queuedDirectionsBeforeBegin.removeAll()
        commitWhenPrepared = false
        prefetchedOpeningSnapshot = nil
        sessionPointerDisplayID = nil
        stopSessionWork()
        panelController.hide()
        shortcutService.setSessionActive(false)
        endAppearanceSignpost()
    }

    private func begin(reverse: Bool) {
        guard state.phase == .idle, !resolvingInitialFocus else { return }

        endAppearanceSignpost()
        appearanceSignpost = Self.signposter.beginInterval(
            "Switcher Appearance"
        )
        sessionGeneration &+= 1
        let generation = sessionGeneration
        resolvingInitialFocus = true
        queuedDirectionsBeforeBegin.removeAll(keepingCapacity: true)
        commitWhenPrepared = false
        sessionPointerDisplayID = Self.pointerDisplayID()

        let frontmostPID = NSWorkspace.shared.frontmostApplication?
            .processIdentifier
        focusResolutionTask = Task {
            [weak self, snapshotProvider, focusHistoryProvider] in
            async let snapshotTask = snapshotProvider.snapshot(
                forceRefreshIfStale: false
            )
            async let focusedTask = focusHistoryProvider.lastFocusedWindowKey()
            let (snapshot, lastFocusedKey) = await (snapshotTask, focusedTask)

            guard let self,
                  !Task.isCancelled,
                  generation == self.sessionGeneration,
                  self.resolvingInitialFocus
            else {
                return
            }

            self.resolvingInitialFocus = false
            self.focusResolutionTask = nil
            self.prefetchedOpeningSnapshot = snapshot
            let fallbackFocus = MRUOrdering.sorted(snapshot.windows)
                .first { $0.id.pid == frontmostPID }?
                .id
            let currentFocus = lastFocusedKey?.pid == frontmostPID
                ? lastFocusedKey
                : fallbackFocus
            self.apply(
                .begin(
                    originalFocus: FocusSnapshot(
                        applicationPID: frontmostPID,
                        windowKey: currentFocus
                    ),
                    initialDirection: reverse ? .backward : .forward
                )
            )

            let queued = self.queuedDirectionsBeforeBegin
            self.queuedDirectionsBeforeBegin.removeAll(keepingCapacity: true)
            for cycle in queued {
                self.apply(
                    cycle.isRepeat
                        ? .repeatedCycle(cycle.direction)
                        : .cycle(cycle.direction)
                )
            }
            if self.commitWhenPrepared {
                self.commitWhenPrepared = false
                self.apply(.modifierReleased)
            }
        }
    }

    private func activateFromPointer(_ key: WindowKey) {
        guard let index = state.items.firstIndex(where: { $0.id == key }) else {
            cancel()
            return
        }
        apply(.mouseActivate(index: index))
    }

    private func closeFromPointer(_ key: WindowKey) {
        guard let index = state.items.firstIndex(where: { $0.id == key }) else {
            NSSound.beep()
            return
        }
        apply(.close(index: index))
    }

    private func apply(_ action: SwitcherSessionAction) {
        let previousPendingClose = state.pendingClose
        let effects = SwitcherSessionReducer.reduce(
            state: &state,
            action: action
        )
        if previousPendingClose != state.pendingClose {
            panelController.setPendingClose(state.pendingClose)
        }
        execute(effects)

        if state.phase == .idle {
            sessionPointerDisplayID = nil
            shortcutService.setSessionActive(false)
            stopSessionWork()
            endAppearanceSignpost()
        }
    }

    private func execute(_ effects: [SwitcherSessionEffect]) {
        for effect in effects {
            switch effect {
            case let .requestSnapshot(forceRefreshIfStale):
                requestSnapshot(forceRefreshIfStale: forceRefreshIfStale)
            case .presentPanel:
                scheduleRendering(present: true)
                startRegistryPolling()
            case .reloadPanel:
                scheduleRendering(present: false)
            case let .selectionChanged(index):
                panelController.select(index: index)
            case .dismissPanel:
                panelController.hide()
                shortcutService.setSessionActive(false)
                registryPollingTask?.cancel()
                registryPollingTask = nil
                if state.phase == .cancelling || state.phase == .committing {
                    apply(.panelDismissed)
                }
            case let .activate(key):
                performActivation(key)
            case let .close(key):
                performClose(key)
            case let .showFeedback(feedback):
                switch feedback {
                case .activationFailed:
                    panelController.showFeedback(
                        String(localized: "Couldn’t switch to this window.")
                    )
                case .closeFailed:
                    panelController.showFeedback(
                        String(localized: "Couldn’t close this window.")
                    )
                }
            case .beep:
                NSSound.beep()
            }
        }
    }

    private func requestSnapshot(forceRefreshIfStale: Bool) {
        preparationTask?.cancel()
        let generation = sessionGeneration
        let settings = settingsProvider()
        let pointerDisplayID = sessionPointerDisplayID
        let currentWindowKey = state.originalFocus?.windowKey

        let hadPrefetchedSnapshot = prefetchedOpeningSnapshot != nil
        let validPrefetchedSnapshot = prefetchedOpeningSnapshot.flatMap {
            WindowSnapshotValidator.isValid($0) ? $0 : nil
        }
        prefetchedOpeningSnapshot = nil
        var requiresUnconditionalRefresh =
            hadPrefetchedSnapshot && validPrefetchedSnapshot == nil
        if let opening = SwitcherOpeningCandidates.cached(
            from: validPrefetchedSnapshot,
            settings: settings,
            pointerDisplayID: pointerDisplayID,
            currentWindowKey: currentWindowKey
        ) {
            if opening.containsAlternative(to: currentWindowKey) {
                apply(
                    .prepared(
                        snapshotGeneration: opening.snapshotGeneration,
                        orderedItems: opening.orderedItems
                    )
                )
                guard state.phase == .visible else { return }
                scheduleReconciliation(
                    generation: generation,
                    settings: settings,
                    pointerDisplayID: pointerDisplayID,
                    forceRefreshIfStale: forceRefreshIfStale
                )
                return
            }
            // A cached snapshot with no alternative must not end the session:
            // a just-created window may not have reached the registry yet.
            requiresUnconditionalRefresh = true
        }

        preparationTask = Task { [weak self, snapshotProvider] in
            let snapshot = if requiresUnconditionalRefresh {
                await snapshotProvider.refreshSnapshot()
            } else {
                await snapshotProvider.snapshot(
                    forceRefreshIfStale: forceRefreshIfStale
                )
            }
            guard WindowSnapshotValidator.isValid(snapshot) else {
                guard let self,
                      !Task.isCancelled,
                      generation == self.sessionGeneration,
                      self.state.phase == .preparing
                else {
                    return
                }
                self.apply(.preparationFailed)
                return
            }
            let opening = SwitcherOpeningCandidates.make(
                from: snapshot,
                settings: settings,
                pointerDisplayID: pointerDisplayID,
                currentWindowKey: currentWindowKey
            )

            guard let self,
                  !Task.isCancelled,
                  generation == self.sessionGeneration,
                  self.state.phase == .preparing
            else {
                return
            }

            self.apply(
                .prepared(
                    snapshotGeneration: opening.snapshotGeneration,
                    orderedItems: opening.orderedItems
                )
            )
            if self.state.phase == .visible {
                self.scheduleReconciliation(
                    generation: generation,
                    settings: settings,
                    pointerDisplayID: pointerDisplayID,
                    forceRefreshIfStale: forceRefreshIfStale
                )
            }
        }
    }

    private func scheduleReconciliation(
        generation: UInt64,
        settings: TabListSettings,
        pointerDisplayID: CGDirectDisplayID?,
        forceRefreshIfStale: Bool
    ) {
        preparationTask = Task { [weak self, snapshotProvider] in
            let fresh = await snapshotProvider.snapshot(
                forceRefreshIfStale: forceRefreshIfStale
            )
            guard let self,
                  !Task.isCancelled,
                  generation == self.sessionGeneration,
                  self.state.phase == .visible
            else {
                return
            }
            guard WindowSnapshotValidator.isValid(fresh) else {
                self.cancel()
                return
            }
            guard fresh.generation > (self.state.snapshotGeneration ?? 0) else {
                return
            }
            self.apply(
                .registryUpdated(
                    snapshotGeneration: fresh.generation,
                    orderedItems: WindowSelectionPipeline.candidates(
                        from: fresh,
                        settings: settings,
                        pointerDisplayID: pointerDisplayID
                    )
                )
            )
        }
    }

    private func scheduleRendering(present: Bool) {
        renderingTask?.cancel()
        let generation = sessionGeneration
        let windows = state.items
        let selectedIndex = state.selectedIndex ?? 0
        let theme = settingsProvider().theme

        if present {
            panelController.show(
                items: makeImmediateDisplayItems(windows),
                selectedIndex: selectedIndex,
                theme: theme,
                displayID: sessionPointerDisplayID
            )
            endAppearanceSignpost()
        }

        renderingTask = Task { [weak self] in
            guard let self else { return }
            let items = await self.makeDisplayItems(windows)
            guard !Task.isCancelled,
                  generation == self.sessionGeneration,
                  self.state.phase == .visible
            else {
                return
            }
            self.panelController.update(
                items: items,
                selectedIndex: self.state.selectedIndex ?? selectedIndex
            )
        }
    }

    private func makeImmediateDisplayItems(
        _ windows: [WindowRecord]
    ) -> [SwitcherDisplayItem] {
        let placeholder = iconCache.placeholderIcon(
            targetSize: Self.iconPointSize
        )
        return windows.map { window in
            SwitcherDisplayItem(
                window: window,
                icon: iconCache.cachedIcon(
                    for: window.bundleIdentifier,
                    bundleURL: window.bundleURL,
                    targetSize: Self.iconPointSize
                ) ?? placeholder
            )
        }
    }

    private func makeDisplayItems(
        _ windows: [WindowRecord]
    ) async -> [SwitcherDisplayItem] {
        var icons: [String: NSImage] = [:]
        var items: [SwitcherDisplayItem] = []
        items.reserveCapacity(windows.count)

        for window in windows {
            guard !Task.isCancelled else { return [] }
            let identity = window.bundleIdentifier
                ?? window.bundleURL?.standardizedFileURL.path
                ?? "pid:\(window.id.pid)"
            let icon: NSImage
            if let cached = icons[identity] {
                icon = cached
            } else {
                icon = await iconCache.icon(
                    for: window.bundleIdentifier,
                    bundleURL: window.bundleURL,
                    targetSize: Self.iconPointSize
                )
                icons[identity] = icon
            }
            items.append(SwitcherDisplayItem(window: window, icon: icon))
        }
        return items
    }

    private func startRegistryPolling() {
        registryPollingTask?.cancel()
        let generation = sessionGeneration
        registryPollingTask = Task { [weak self, snapshotProvider] in
            while !Task.isCancelled {
                do {
                    try await ContinuousClock().sleep(
                        for: Self.sessionPollInterval
                    )
                } catch {
                    return
                }

                guard let self,
                      !Task.isCancelled,
                      generation == self.sessionGeneration,
                      self.state.phase == .visible
                else {
                    return
                }
                let snapshot = await snapshotProvider.snapshot(
                    forceRefreshIfStale: true
                )
                guard !Task.isCancelled,
                      generation == self.sessionGeneration,
                      self.state.phase == .visible
                else {
                    return
                }
                guard WindowSnapshotValidator.isValid(snapshot) else {
                    self.cancel()
                    return
                }
                guard snapshot.generation
                    > (self.state.snapshotGeneration ?? 0) else {
                    continue
                }
                self.apply(
                    .registryUpdated(
                        snapshotGeneration: snapshot.generation,
                        orderedItems: WindowSelectionPipeline.candidates(
                            from: snapshot,
                            settings: self.settingsProvider(),
                            pointerDisplayID: self.sessionPointerDisplayID
                        )
                    )
                )
            }
        }
    }

    private func performActivation(_ key: WindowKey) {
        guard let record = state.items.first(where: { $0.id == key }) else {
            apply(.activationCompleted(.targetMissing))
            return
        }
        let target = WindowActionTarget(record)
        let generation = sessionGeneration
        endAppearanceSignpost()
        let interval = Self.signposter.beginInterval("Window Activation")
        Task { [weak self, windowActions] in
            let result = await windowActions.activate(target)
            Self.signposter.endInterval("Window Activation", interval)
            guard let self, generation == self.sessionGeneration else { return }
            self.apply(.activationCompleted(result))
        }
    }

    private func performClose(_ key: WindowKey) {
        guard let record = state.items.first(where: { $0.id == key }) else {
            apply(.closeCompleted(key: key, result: .targetMissing))
            return
        }
        let target = WindowActionTarget(record)
        let generation = sessionGeneration
        Task { [weak self, windowActions] in
            let result = await windowActions.close(target)
            guard let self, generation == self.sessionGeneration else { return }
            TabListLog.windowActions.debug(
                "Close completed for pid \(key.pid, privacy: .private(mask: .hash)) result \(result.diagnosticCode, privacy: .public)"
            )
            self.apply(.closeCompleted(key: key, result: result))
        }
    }

    private func stopSessionWork() {
        preparationTask?.cancel()
        preparationTask = nil
        renderingTask?.cancel()
        renderingTask = nil
        registryPollingTask?.cancel()
        registryPollingTask = nil
    }

    private func endAppearanceSignpost() {
        guard let appearanceSignpost else { return }
        Self.signposter.endInterval("Switcher Appearance", appearanceSignpost)
        self.appearanceSignpost = nil
    }

    private static func pointerDisplayID() -> CGDirectDisplayID? {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(
            where: { NSMouseInRect(pointer, $0.frame, false) }
        ) else {
            return nil
        }
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }
}
