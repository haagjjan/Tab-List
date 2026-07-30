@preconcurrency import AppKit
import CoreGraphics
import Foundation
import OSLog
import TabListCore

private struct BackgroundThumbnailFingerprint: Equatable, Sendable {
    let incarnation: UInt64
    let title: String
    let bounds: CGRect
    let isMinimized: Bool
    let isHidden: Bool
    let isFullscreen: Bool

    init(_ window: WindowRecord) {
        incarnation = window.incarnation
        title = window.windowTitle
        bounds = window.bounds
        isMinimized = window.isMinimized
        isHidden = window.isHidden
        isFullscreen = window.isFullscreen
    }
}

struct BackgroundThumbnailRefreshTracker: Sendable {
    private struct Entry: Sendable {
        let fingerprint: BackgroundThumbnailFingerprint
        let capturedAt: ContinuousClock.Instant
    }

    private var entries: [WindowKey: Entry] = [:]

    mutating func candidates(
        from windows: [WindowRecord],
        at now: ContinuousClock.Instant,
        stableRefreshInterval: Duration
    ) -> [WindowRecord] {
        let retainedKeys = Set(windows.map(\.id))
        entries = entries.filter { retainedKeys.contains($0.key) }

        return windows.filter { window in
            guard let entry = entries[window.id] else { return true }
            if entry.fingerprint != BackgroundThumbnailFingerprint(window) {
                return true
            }
            return entry.capturedAt.duration(to: now)
                >= stableRefreshInterval
        }
    }

    mutating func recordCaptured(
        _ keys: Set<WindowKey>,
        from windows: [WindowRecord],
        at now: ContinuousClock.Instant
    ) {
        for window in windows where keys.contains(window.id) {
            entries[window.id] = Entry(
                fingerprint: BackgroundThumbnailFingerprint(window),
                capturedAt: now
            )
        }
    }

    mutating func reset() {
        entries.removeAll(keepingCapacity: true)
    }
}

/// Main-actor orchestration around the pure switcher reducer.
///
/// The coordinator never asks WindowServer or Accessibility for data on the
/// main thread. It presents immutable registry snapshots and discards all
/// generation-bound work after a session ends.
@MainActor
final class SwitcherSessionCoordinator {
    var onCompatibilityStatusChanged: (() -> Void)?

    private static let signposter = OSSignposter(
        subsystem: "com.haagjjan.TabList",
        category: "switcher-performance"
    )

    private let snapshotProvider: any WindowSnapshotProviding
    private let focusHistoryProvider: any WindowFocusHistoryProviding
    private let windowActions: any WindowActuating
    private let shortcutService: GlobalShortcutService
    private let iconCache: any AppIconProviding
    private let panelController: SwitcherPanelController
    private let settingsProvider: () -> SettingsV1
    private let thumbnailFactory: () -> any ThumbnailProviding
    private let backgroundRefreshClock = ContinuousClock()

    private var state = SwitcherSessionState()
    private var thumbnailService: (any ThumbnailProviding)?
    private var preparationTask: Task<Void, Never>?
    private var renderingTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var registryPollingTask: Task<Void, Never>?
    private var focusResolutionTask: Task<Void, Never>?
    private var backgroundRefreshTask: Task<Void, Never>?

    private var sessionGeneration: UInt64 = 0
    private var resolvingInitialFocus = false
    private var queuedDirectionsBeforeBegin: [SwitcherDirection] = []
    private var commitWhenPrepared = false
    private var prefetchedOpeningSnapshot: WindowSnapshot?
    private var sessionPointerDisplayID: CGDirectDisplayID?
    private var appearanceSignpost: OSSignpostIntervalState?
    private var thumbnailCaptureIsAuthorized = false
    private var backgroundThumbnailTracker =
        BackgroundThumbnailRefreshTracker()

    init(
        snapshotProvider: any WindowSnapshotProviding,
        focusHistoryProvider: any WindowFocusHistoryProviding,
        windowActions: any WindowActuating,
        shortcutService: GlobalShortcutService,
        iconCache: any AppIconProviding,
        panelController: SwitcherPanelController,
        settingsProvider: @escaping () -> SettingsV1,
        thumbnailFactory: @escaping () -> any ThumbnailProviding = {
            ThumbnailService()
        }
    ) {
        self.snapshotProvider = snapshotProvider
        self.focusHistoryProvider = focusHistoryProvider
        self.windowActions = windowActions
        self.shortcutService = shortcutService
        self.iconCache = iconCache
        self.panelController = panelController
        self.settingsProvider = settingsProvider
        self.thumbnailFactory = thumbnailFactory

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
        captureTask?.cancel()
        registryPollingTask?.cancel()
        focusResolutionTask?.cancel()
        backgroundRefreshTask?.cancel()
    }

    var isActive: Bool {
        state.phase != .idle || resolvingInitialFocus
    }

    func handle(_ command: ShortcutInputCommand) {
        switch command {
        case let .begin(reverse):
            begin(reverse: reverse)
        case let .cycle(reverse):
            let direction: SwitcherDirection = reverse ? .backward : .forward
            if resolvingInitialFocus {
                queuedDirectionsBeforeBegin.append(direction)
            } else {
                apply(.cycle(direction))
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
        if resolvingInitialFocus {
            resolvingInitialFocus = false
            focusResolutionTask?.cancel()
            focusResolutionTask = nil
            queuedDirectionsBeforeBegin.removeAll(keepingCapacity: true)
            commitWhenPrepared = false
            sessionPointerDisplayID = nil
            sessionGeneration &+= 1
            shortcutService.setSessionActive(false)
            endAppearanceSignpost()
            return
        }
        apply(.cancel)
    }

    func presentationSettingsChanged() {
        guard settingsProvider().presentation != .thumbnails else {
            if state.phase == .visible {
                scheduleRendering(present: true)
                if thumbnailCaptureIsAuthorized {
                    scheduleThumbnailRefresh()
                }
            }
            return
        }
        captureTask?.cancel()
        captureTask = nil
        if let thumbnailService {
            Task { await thumbnailService.cancelPending() }
        }
        if state.phase == .visible {
            scheduleRendering(present: true)
        }
    }

    func updateThumbnailCaptureAuthorization(_ isAuthorized: Bool) {
        guard thumbnailCaptureIsAuthorized != isAuthorized else { return }
        thumbnailCaptureIsAuthorized = isAuthorized

        guard !isAuthorized else {
            if state.phase == .visible,
               settingsProvider().presentation == .thumbnails {
                scheduleRendering(present: true)
                scheduleThumbnailRefresh()
            }
            return
        }

        captureTask?.cancel()
        captureTask = nil
        backgroundRefreshTask?.cancel()
        backgroundRefreshTask = nil
        backgroundThumbnailTracker.reset()
        renderingTask?.cancel()
        renderingTask = nil

        if state.phase == .visible,
           settingsProvider().presentation == .thumbnails {
            panelController.update(
                items: makeImmediateDisplayItems(
                    state.items,
                    presentation: .thumbnails
                ),
                selectedIndex: state.selectedIndex ?? 0
            )
        }

        if let thumbnailService {
            Task {
                await thumbnailService.purge()
            }
        }
    }

    func warmCaches() {
        let presentation = settingsProvider().presentation
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
                    targetSize: presentation == .titles ? 32 : 128
                )
            }
        }
    }

    func updateBackgroundRefresh(enabled: Bool) {
        let shouldCancelBackgroundCaptures =
            backgroundRefreshTask != nil && !isActive
        backgroundRefreshTask?.cancel()
        backgroundRefreshTask = nil
        backgroundThumbnailTracker.reset()
        if shouldCancelBackgroundCaptures, let thumbnailService {
            Task { await thumbnailService.cancelPending() }
        }
        let settings = settingsProvider()
        guard enabled,
              thumbnailCaptureIsAuthorized,
              settings.presentation == .thumbnails,
              settings.refreshThumbnailsInBackground
        else {
            return
        }

        let service = thumbnailProvider()
        backgroundRefreshTask = Task(priority: .utility) {
            [weak self, snapshotProvider] in
            while !Task.isCancelled {
                do {
                    try await ContinuousClock().sleep(for: .seconds(30))
                } catch {
                    return
                }
                guard let self, !self.isActive else { continue }
                let snapshot = await snapshotProvider.snapshot(
                    forceRefreshIfStale: false
                )
                guard !Task.isCancelled,
                      !self.isActive,
                      self.settingsProvider().presentation == .thumbnails,
                      self.settingsProvider().refreshThumbnailsInBackground
                else {
                    continue
                }
                let visible = snapshot.windows.filter { window in
                    !Set(window.spaceIDs).isDisjoint(
                        with: snapshot.visibleSpaceIDs
                    )
                }
                let boundedVisible = Array(visible.prefix(24))
                let changed = self.backgroundThumbnailTracker.candidates(
                    from: boundedVisible,
                    at: self.backgroundRefreshClock.now,
                    stableRefreshInterval: .seconds(300)
                )
                let keys = changed.map(\.id)
                guard !keys.isEmpty else { continue }
                let captured = await service.refresh(
                    changed,
                    priority: keys,
                    targetSize: Self.thumbnailTargetSize(
                        for: self.settingsProvider().panelSize
                    )
                )
                guard !Task.isCancelled, !self.isActive else { continue }
                self.backgroundThumbnailTracker.recordCaptured(
                    captured,
                    from: boundedVisible,
                    at: self.backgroundRefreshClock.now
                )
            }
        }
    }

    func handleMemoryPressure() {
        iconCache.purgeMemory()
        backgroundThumbnailTracker.reset()
        captureTask?.cancel()
        captureTask = nil
        guard let thumbnailService else { return }
        Task { await thumbnailService.purge() }
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
        backgroundRefreshTask?.cancel()
        backgroundRefreshTask = nil
        backgroundThumbnailTracker.reset()
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
            async let focusedTask =
                focusHistoryProvider.lastFocusedWindowKey()
            let (snapshot, lastFocusedKey) = await (
                snapshotTask,
                focusedTask
            )

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
            let focus = FocusSnapshot(
                applicationPID: frontmostPID,
                windowKey: currentFocus
            )
            self.apply(
                .begin(
                    originalFocus: focus,
                    initialDirection: reverse ? .backward : .forward
                )
            )

            let queued = self.queuedDirectionsBeforeBegin
            self.queuedDirectionsBeforeBegin.removeAll(keepingCapacity: true)
            for direction in queued {
                self.apply(.cycle(direction))
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
        let effects = SwitcherSessionReducer.reduce(
            state: &state,
            action: action
        )
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
                scheduleThumbnailRefresh()
            case let .selectionChanged(index):
                Self.signposter.emitEvent(
                    "Selection Changed",
                    "index: \(index, privacy: .public)"
                )
                panelController.select(index: index)
                if captureTask != nil {
                    scheduleThumbnailRefresh()
                }
            case .dismissPanel:
                panelController.hide()
                shortcutService.setSessionActive(false)
                captureTask?.cancel()
                captureTask = nil
                registryPollingTask?.cancel()
                registryPollingTask = nil
                if let thumbnailService {
                    Task { await thumbnailService.cancelPending() }
                }
                if state.phase == .cancelling
                    || state.phase == .committing
                {
                    apply(.panelDismissed)
                }
            case let .activate(key):
                performActivation(key)
            case let .close(key):
                performClose(key)
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
            // Remain in `preparing` until the requested forced refresh decides.
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
        settings: SettingsV1,
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
            guard
                  fresh.generation >
                    (self.state.snapshotGeneration ?? 0)
            else {
                return
            }
            let candidates = WindowSelectionPipeline.candidates(
                from: fresh,
                settings: settings,
                pointerDisplayID: pointerDisplayID
            )
            self.apply(
                .registryUpdated(
                    snapshotGeneration: fresh.generation,
                    orderedItems: candidates
                )
            )
        }
    }

    private func scheduleRendering(present: Bool) {
        renderingTask?.cancel()
        let generation = sessionGeneration
        let windows = state.items
        let selectedIndex = state.selectedIndex ?? 0
        let settings = settingsProvider()

        let immediateItems: [SwitcherDisplayItem]?
        if present {
            let items = makeImmediateDisplayItems(
                windows,
                presentation: settings.presentation
            )
            immediateItems = items
            panelController.show(
                items: items,
                selectedIndex: selectedIndex,
                presentation: settings.presentation,
                panelSize: settings.panelSize,
                theme: settings.theme,
                opacity: settings.opacity,
                displayID: sessionPointerDisplayID
            )
            endAppearanceSignpost()
            scheduleThumbnailRefresh()
        } else {
            immediateItems = nil
        }

        renderingTask = Task { [weak self] in
            guard let self else { return }
            if let immediateItems {
                await self.progressivelyHydrateDisplayItems(
                    windows,
                    initialItems: immediateItems,
                    selectedIndex: selectedIndex,
                    presentation: settings.presentation,
                    generation: generation
                )
                return
            }
            let displayItems = await self.makeDisplayItems(
                windows,
                presentation: settings.presentation
            )
            guard !Task.isCancelled,
                  generation == self.sessionGeneration,
                  self.state.phase == .visible
            else {
                return
            }

            self.panelController.update(
                items: displayItems,
                selectedIndex: self.state.selectedIndex ?? selectedIndex
            )
        }
    }

    private func progressivelyHydrateDisplayItems(
        _ windows: [WindowRecord],
        initialItems: [SwitcherDisplayItem],
        selectedIndex: Int,
        presentation: PresentationMode,
        generation: UInt64
    ) async {
        guard windows.count == initialItems.count else { return }
        let thumbnails = presentation == .thumbnails
            && thumbnailCaptureIsAuthorized
            ? thumbnailProvider()
            : nil
        var displayItems = initialItems
        let order = hydrationOrder(
            itemCount: windows.count,
            selectedIndex: selectedIndex
        )

        for (offset, index) in order.enumerated() {
            guard !Task.isCancelled,
                  generation == sessionGeneration,
                  state.phase == .visible else {
                return
            }
            let window = windows[index]
            let icon = await iconCache.icon(
                for: window.bundleIdentifier,
                bundleURL: window.bundleURL,
                targetSize: presentation == .titles ? 32 : 128
            )
            let thumbnail = await thumbnails?.cachedThumbnail(for: window)
            displayItems[index] = SwitcherDisplayItem(
                window: window,
                icon: icon,
                thumbnail: thumbnail
            )

            if offset % 6 == 5 || offset == order.count - 1 {
                guard !Task.isCancelled,
                      generation == sessionGeneration,
                      state.phase == .visible else {
                    return
                }
                panelController.update(
                    items: displayItems,
                    selectedIndex: state.selectedIndex ?? selectedIndex
                )
                await Task.yield()
            }
        }
    }

    private func hydrationOrder(
        itemCount: Int,
        selectedIndex: Int
    ) -> [Int] {
        guard itemCount > 0 else { return [] }
        let selected = min(max(0, selectedIndex), itemCount - 1)
        var result = [selected]
        if itemCount > 1 {
            let previous = (selected - 1 + itemCount) % itemCount
            let next = (selected + 1) % itemCount
            result.append(previous)
            if next != previous {
                result.append(next)
            }
        }
        let prioritized = Set(result)
        result.append(
            contentsOf: (0..<itemCount).filter {
                !prioritized.contains($0)
            }
        )
        return result
    }

    private func makeImmediateDisplayItems(
        _ windows: [WindowRecord],
        presentation: PresentationMode
    ) -> [SwitcherDisplayItem] {
        let targetSize: CGFloat = presentation == .titles ? 32 : 128
        let placeholder = iconCache.placeholderIcon(
            targetSize: targetSize
        )
        return windows.map { window in
            SwitcherDisplayItem(
                window: window,
                icon: iconCache.cachedIcon(
                    for: window.bundleIdentifier,
                    bundleURL: window.bundleURL,
                    targetSize: targetSize
                ) ?? placeholder,
                thumbnail: nil
            )
        }
    }

    private func makeDisplayItems(
        _ windows: [WindowRecord],
        presentation: PresentationMode
    ) async -> [SwitcherDisplayItem] {
        let thumbnails = presentation == .thumbnails
            && thumbnailCaptureIsAuthorized
            ? thumbnailProvider()
            : nil
        var displayItems: [SwitcherDisplayItem] = []
        displayItems.reserveCapacity(windows.count)

        for window in windows {
            guard !Task.isCancelled else { return [] }
            let icon = await iconCache.icon(
                for: window.bundleIdentifier,
                bundleURL: window.bundleURL,
                targetSize: presentation == .titles ? 32 : 128
            )
            let thumbnail = await thumbnails?.cachedThumbnail(for: window)
            displayItems.append(
                SwitcherDisplayItem(
                    window: window,
                    icon: icon,
                    thumbnail: thumbnail
                )
            )
        }
        return displayItems
    }

    private func scheduleThumbnailRefresh() {
        let settings = settingsProvider()
        guard thumbnailCaptureIsAuthorized,
              settings.presentation == .thumbnails,
              state.phase == .visible,
              !state.items.isEmpty
        else {
            return
        }

        captureTask?.cancel()
        let generation = sessionGeneration
        let service = thumbnailProvider()
        let windows = state.items
        let keys = windows.map(\.id)
        let priority = thumbnailPriority()
        let plan = ThumbnailCapturePlan(
            allKeys: keys,
            priorityKeys: priority.isEmpty
                ? Array(keys.prefix(3))
                : priority,
            visibleKeys: panelController.visibleWindowKeys
        )
        let targetSize = Self.thumbnailTargetSize(
            for: settings.panelSize,
            backingScaleFactor: panelController.backingScaleFactor
        )

        captureTask = Task { [weak self] in
            await service.cancelPending()
            _ = await service.refresh(
                Self.windows(
                    matching: plan.immediate,
                    in: windows
                ),
                priority: plan.immediate,
                targetSize: targetSize
            )
            guard let self,
                  !Task.isCancelled,
                  generation == self.sessionGeneration,
                  self.state.phase == .visible
            else {
                return
            }
            self.scheduleRendering(present: false)

            if !plan.visible.isEmpty {
                _ = await service.refresh(
                    Self.windows(
                        matching: plan.visible,
                        in: windows
                    ),
                    priority: plan.visible,
                    targetSize: targetSize
                )
                guard !Task.isCancelled,
                      generation == self.sessionGeneration,
                      self.state.phase == .visible
                else {
                    return
                }
                self.scheduleRendering(present: false)
            }

            guard !plan.remaining.isEmpty else { return }
            _ = await service.refresh(
                Self.windows(
                    matching: plan.remaining,
                    in: windows
                ),
                priority: [],
                targetSize: targetSize
            )
            guard !Task.isCancelled,
                  generation == self.sessionGeneration,
                  self.state.phase == .visible
            else {
                return
            }
            self.scheduleRendering(present: false)
        }
    }

    private static func windows(
        matching keys: [WindowKey],
        in windows: [WindowRecord]
    ) -> [WindowRecord] {
        let windowsByKey = windows.reduce(
            into: [WindowKey: WindowRecord]()
        ) { result, window in
            result[window.id] = window
        }
        return keys.compactMap { windowsByKey[$0] }
    }

    private func startRegistryPolling() {
        registryPollingTask?.cancel()
        let generation = sessionGeneration
        registryPollingTask = Task { [weak self, snapshotProvider] in
            while !Task.isCancelled {
                do {
                    try await ContinuousClock().sleep(
                        for: .milliseconds(250)
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
                guard
                      snapshot.generation >
                        (self.state.snapshotGeneration ?? 0)
                else {
                    continue
                }
                let candidates = WindowSelectionPipeline.candidates(
                    from: snapshot,
                    settings: self.settingsProvider(),
                    pointerDisplayID: self.sessionPointerDisplayID
                )
                self.apply(
                    .registryUpdated(
                        snapshotGeneration: snapshot.generation,
                        orderedItems: candidates
                    )
                )
            }
        }
    }

    private func performActivation(_ key: WindowKey) {
        let generation = sessionGeneration
        endAppearanceSignpost()
        let interval = Self.signposter.beginInterval("Window Activation")
        Task { [weak self, windowActions] in
            let result = await windowActions.activate(key)
            Self.signposter.endInterval("Window Activation", interval)
            guard let self,
                  generation == self.sessionGeneration
            else {
                return
            }
            self.onCompatibilityStatusChanged?()
            self.apply(.activationCompleted(result))
        }
    }

    private func performClose(_ key: WindowKey) {
        let generation = sessionGeneration
        Task { [weak self, windowActions] in
            let result = await windowActions.close(key)
            guard let self,
                  generation == self.sessionGeneration
            else {
                return
            }
            self.apply(.closeCompleted(key: key, result: result))
        }
    }

    private func thumbnailProvider() -> any ThumbnailProviding {
        if let thumbnailService {
            return thumbnailService
        }
        let service = thumbnailFactory()
        thumbnailService = service
        return service
    }

    private func thumbnailPriority() -> [WindowKey] {
        guard let selectedIndex = state.selectedIndex,
              state.items.indices.contains(selectedIndex)
        else {
            return []
        }

        var result = [state.items[selectedIndex].id]
        if state.items.count > 1 {
            let previous = (selectedIndex - 1 + state.items.count)
                % state.items.count
            let next = (selectedIndex + 1) % state.items.count
            result.append(state.items[previous].id)
            if next != previous {
                result.append(state.items[next].id)
            }
        }
        return result
    }

    private func stopSessionWork() {
        preparationTask?.cancel()
        preparationTask = nil
        renderingTask?.cancel()
        renderingTask = nil
        captureTask?.cancel()
        captureTask = nil
        registryPollingTask?.cancel()
        registryPollingTask = nil
        if let thumbnailService {
            Task { await thumbnailService.cancelPending() }
        }
    }

    private func endAppearanceSignpost() {
        guard let appearanceSignpost else { return }
        Self.signposter.endInterval(
            "Switcher Appearance",
            appearanceSignpost
        )
        self.appearanceSignpost = nil
    }

    private static func pointerDisplayID() -> CGDirectDisplayID? {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(
            where: { NSMouseInRect(pointer, $0.frame, false) }
        ) else {
            return nil
        }
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[screenNumberKey] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }

    private static func thumbnailTargetSize(
        for size: PanelSize,
        backingScaleFactor: CGFloat = 2
    ) -> CGSize {
        let scale = max(1, backingScaleFactor)
        switch size {
        case .small:
            return CGSize(width: 240 * scale, height: 160 * scale)
        case .medium, .auto:
            return CGSize(width: 300 * scale, height: 200 * scale)
        case .large:
            return CGSize(width: 360 * scale, height: 240 * scale)
        }
    }
}
