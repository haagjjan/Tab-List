@preconcurrency import AppKit
import CoreGraphics
import Foundation
import TabListCore

private struct RegistryRefreshPayload: Sendable {
    let inventory: WindowInventoryResult
    let focusedKey: WindowKey?
}

enum GlobalFocusObservationGate {
    static func accepts(
        observedPID: pid_t,
        frontmostPID: pid_t?
    ) -> Bool {
        observedPID > 0 && observedPID == frontmostPID
    }

    static func confirms(
        target: WindowKey,
        frontmostPID: pid_t?,
        accessibilityFocusedKey: WindowKey?
    ) -> Bool {
        accepts(
            observedPID: target.pid,
            frontmostPID: frontmostPID
        ) && accessibilityFocusedKey == target
    }
}

/// The single source of truth for immutable window snapshots.
public actor WindowRegistry:
    WindowSnapshotProviding,
    WindowFocusHistoryProviding
{
    private let inventory: any WindowInventoryProviding
    private let clock = ContinuousClock()
    private let staleAfter: Duration

    private var records: [WindowKey: WindowRecord] = [:]
    private var incarnations: [WindowKey: UInt64] = [:]
    private var nextWindowIncarnation: UInt64 = 0
    private var sourceOrder: [WindowKey] = []
    private var visibleSpaceIDs: Set<UInt64> = []
    private var mru = WindowMRUTracker()
    private var generation: UInt64 = 0
    private var lastRefresh: ContinuousClock.Instant?
    private var lastConfirmedFocusedKey: WindowKey?
    private var latestObservedFocusedKey: WindowKey?
    private var focusObservationRevision: UInt64 = 0
    private var invalidationGeneration: UInt64 = 0
    private var nextRefreshIdentifier: UInt64 = 0
    private var lastAppliedRefreshIdentifier: UInt64 = 0
    private var inFlightRefresh: (
        identifier: UInt64,
        invalidationGeneration: UInt64,
        focusObservationRevision: UInt64,
        task: Task<RegistryRefreshPayload, Never>
    )?

    public init(
        inventory: any WindowInventoryProviding,
        staleAfter: Duration = .milliseconds(750)
    ) {
        self.inventory = inventory
        self.staleAfter = staleAfter
    }

    public func snapshot(
        forceRefreshIfStale: Bool
    ) async -> WindowSnapshot {
        let now = clock.now
        let isStale = lastRefresh.map {
            $0.duration(to: now) >= staleAfter
        } ?? true

        if lastRefresh == nil || (forceRefreshIfStale && isStale) {
            await refresh()
        }

        return makeSnapshot()
    }

    public func refreshSnapshot() async -> WindowSnapshot {
        await refresh()
    }

    @discardableResult
    public func refresh() async -> WindowSnapshot {
        let flight: (
            identifier: UInt64,
            invalidationGeneration: UInt64,
            focusObservationRevision: UInt64,
            task: Task<RegistryRefreshPayload, Never>
        )
        if let existing = inFlightRefresh,
           existing.invalidationGeneration == invalidationGeneration {
            flight = existing
        } else {
            nextRefreshIdentifier &+= 1
            let identifier = nextRefreshIdentifier
            let startingInvalidationGeneration = invalidationGeneration
            let startingFocusObservationRevision =
                focusObservationRevision
            let inventory = inventory
            let task = Task {
                let discovered = await inventory.discover()
                let focusedKey = await inventory.currentFocusedWindowKey()
                return RegistryRefreshPayload(
                    inventory: discovered,
                    focusedKey: focusedKey
                )
            }
            flight = (
                identifier,
                startingInvalidationGeneration,
                startingFocusObservationRevision,
                task
            )
            inFlightRefresh = flight
        }

        let payload = await flight.task.value
        if inFlightRefresh?.identifier == flight.identifier {
            inFlightRefresh = nil
        }
        guard flight.identifier > lastAppliedRefreshIdentifier,
              flight.invalidationGeneration == invalidationGeneration else {
            return makeSnapshot()
        }
        lastAppliedRefreshIdentifier = flight.identifier

        let discovered = payload.inventory
        let focusedKey: WindowKey?
        if flight.focusObservationRevision == focusObservationRevision {
            focusedKey = payload.focusedKey
            if let focusedKey {
                latestObservedFocusedKey = focusedKey
            }
        } else {
            focusedKey = latestObservedFocusedKey
        }
        let newKeys = Set(discovered.windows.map(\.id))
        incarnations = incarnations.filter { newKeys.contains($0.key) }
        let incarnatedWindows = discovered.windows.map { window in
            var window = window
            if let incarnation = incarnations[window.id] {
                window.incarnation = incarnation
            } else {
                nextWindowIncarnation &+= 1
                incarnations[window.id] = nextWindowIncarnation
                window.incarnation = nextWindowIncarnation
            }
            return window
        }

        mru.seed(
            frontToBack: incarnatedWindows.map(\.id),
            knownVisibleKeys: discovered.visibleWindowKeys
        )
        mru.retainOnly(newKeys)

        let sequenced = mru.applyingSequences(to: incarnatedWindows)
        records = sequenced.reduce(
            into: [WindowKey: WindowRecord]()
        ) { result, window in
            result[window.id] = window
        }
        sourceOrder = sequenced.map(\.id)
        if let focusedKey,
           focusedKey != lastConfirmedFocusedKey,
           records[focusedKey] != nil {
            let sequence = mru.recordFocus(focusedKey)
            records[focusedKey]?.lastFocusSequence = sequence
            lastConfirmedFocusedKey = focusedKey
        } else if let focusedKey, records[focusedKey] != nil {
            lastConfirmedFocusedKey = focusedKey
        } else if focusedKey == nil,
                  let previousFocusedKey = lastConfirmedFocusedKey,
                  records[previousFocusedKey] == nil {
            self.lastConfirmedFocusedKey = nil
        }
        visibleSpaceIDs = discovered.visibleSpaceIDs
        generation &+= 1
        lastRefresh = clock.now
        return makeSnapshot()
    }

    public func noteFocused(_ key: WindowKey) {
        focusObservationRevision &+= 1
        latestObservedFocusedKey = key
        guard records[key] != nil else { return }
        guard key != lastConfirmedFocusedKey else { return }
        let sequence = mru.recordFocus(key)
        records[key]?.lastFocusSequence = sequence
        lastConfirmedFocusedKey = key
        generation &+= 1
    }

    public func remove(_ key: WindowKey) {
        guard records.removeValue(forKey: key) != nil else { return }
        invalidationGeneration &+= 1
        lastRefresh = nil
        incarnations.removeValue(forKey: key)
        sourceOrder.removeAll { $0 == key }
        mru.remove(key)
        if lastConfirmedFocusedKey == key {
            lastConfirmedFocusedKey = nil
        }
        if latestObservedFocusedKey == key {
            latestObservedFocusedKey = nil
        }
        generation &+= 1
    }

    public func record(for key: WindowKey) -> WindowRecord? {
        records[key]
    }

    public func contains(_ key: WindowKey) -> Bool {
        records[key] != nil
    }

    public func lastFocusedWindowKey() -> WindowKey? {
        lastConfirmedFocusedKey
    }

    public func invalidate() {
        invalidationGeneration &+= 1
        lastRefresh = nil
    }

    private func makeSnapshot() -> WindowSnapshot {
        let orderedRecords = sourceOrder.compactMap { records[$0] }
        return WindowSnapshot(
            generation: generation,
            windows: orderedRecords,
            visibleSpaceIDs: visibleSpaceIDs,
            createdAt: clock.now
        )
    }
}

/// Bridges event-style workspace changes into the registry actor. Notifications
/// only invalidate/schedule reconciliation; they never perform WindowServer or
/// AX work on the main actor.
@MainActor
public final class WindowRegistryLifecycleObserver {
    private let registry: WindowRegistry
    private let accessibility: AccessibilityBridge
    private var workspaceTokens: [any NSObjectProtocol] = []
    private var applicationTokens: [any NSObjectProtocol] = []
    private var refreshTask: Task<Void, Never>?

    public init(
        registry: WindowRegistry,
        accessibility: AccessibilityBridge
    ) {
        self.registry = registry
        self.accessibility = accessibility
    }

    isolated deinit {
        stop()
    }

    public func start() {
        guard workspaceTokens.isEmpty, applicationTokens.isEmpty else { return }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let reconciliationNotifications: [NSNotification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didWakeNotification,
        ]

        workspaceTokens = reconciliationNotifications.map { name in
            workspaceCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let terminatedPID: pid_t?
                if notification.name
                    == NSWorkspace.didTerminateApplicationNotification {
                    terminatedPID = (
                        notification.userInfo?[
                            NSWorkspace.applicationUserInfoKey
                        ] as? NSRunningApplication
                    )?.processIdentifier
                } else {
                    terminatedPID = nil
                }
                MainActor.assumeIsolated {
                    self?.handleWorkspaceNotification(
                        terminatedPID: terminatedPID
                    )
                }
            }
        }

        workspaceTokens.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let activatedPID = (
                    notification.userInfo?[
                        NSWorkspace.applicationUserInfoKey
                    ] as? NSRunningApplication
                )?.processIdentifier
                MainActor.assumeIsolated {
                    self?.handleActivation(pid: activatedPID)
                }
            }
        )

        applicationTokens = [
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.scheduleRefresh() }
            },
        ]
    }

    public func stop() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceTokens.forEach(workspaceCenter.removeObserver)
        applicationTokens.forEach(NotificationCenter.default.removeObserver)
        workspaceTokens.removeAll()
        applicationTokens.removeAll()
        refreshTask?.cancel()
        refreshTask = nil
    }

    public func refreshNow() {
        refreshTask?.cancel()
        refreshTask = Task { [registry] in
            await registry.invalidate()
            _ = await registry.refresh()
        }
    }

    private func handleWorkspaceNotification(terminatedPID: pid_t?) {
        if let terminatedPID {
            accessibility.invalidate(pid: terminatedPID)
        }
        scheduleRefresh()
    }

    private func handleActivation(pid: pid_t?) {
        guard let pid else {
            scheduleRefresh()
            return
        }

        refreshTask?.cancel()
        refreshTask = Task { [registry, accessibility] in
            await registry.invalidate()
            if let focused = await accessibility.focusedWindowKey(
                for: pid
            ), GlobalFocusObservationGate.accepts(
                observedPID: pid,
                frontmostPID: NSWorkspace.shared
                    .frontmostApplication?.processIdentifier
            ) {
                await registry.noteFocused(focused)
            }
            _ = await registry.refresh()
        }
    }

    public func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [registry] in
            do {
                try await ContinuousClock().sleep(for: .milliseconds(120))
            } catch {
                return
            }
            await registry.invalidate()
            _ = await registry.refresh()
        }
    }
}
