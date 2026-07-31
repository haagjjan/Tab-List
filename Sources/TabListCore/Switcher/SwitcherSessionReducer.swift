import Darwin
import Foundation

public struct FocusSnapshot: Equatable, Sendable {
    public let applicationPID: pid_t?
    public let windowKey: WindowKey?

    public init(applicationPID: pid_t?, windowKey: WindowKey?) {
        self.applicationPID = applicationPID
        self.windowKey = windowKey
    }
}

public enum SwitcherDirection: Equatable, Sendable {
    case forward
    case backward
}

public enum SwitcherSessionPhase: Equatable, Sendable {
    case idle
    case preparing
    case visible
    case committing
    case cancelling
}

public struct SwitcherSessionState: Equatable, Sendable {
    public internal(set) var phase: SwitcherSessionPhase
    public internal(set) var originalFocus: FocusSnapshot?
    public internal(set) var snapshotGeneration: UInt64?
    public internal(set) var items: [WindowRecord]
    public internal(set) var selectedIndex: Int?
    public internal(set) var pendingClose: WindowKey?
    public internal(set) var commitWhenCloseCompletes: Bool
    public internal(set) var initialDirection: SwitcherDirection
    public internal(set) var queuedCycleOffset: Int
    public internal(set) var queuedCycleClampsAtBoundary: Bool
    public internal(set) var commitWhenPrepared: Bool
    public internal(set) var panelPresented: Bool

    public init(
        phase: SwitcherSessionPhase = .idle,
        originalFocus: FocusSnapshot? = nil,
        snapshotGeneration: UInt64? = nil,
        items: [WindowRecord] = [],
        selectedIndex: Int? = nil,
        pendingClose: WindowKey? = nil,
        commitWhenCloseCompletes: Bool = false,
        initialDirection: SwitcherDirection = .forward,
        queuedCycleOffset: Int = 0,
        queuedCycleClampsAtBoundary: Bool = false,
        commitWhenPrepared: Bool = false,
        panelPresented: Bool = false
    ) {
        self.phase = phase
        self.originalFocus = originalFocus
        self.snapshotGeneration = snapshotGeneration
        self.items = items
        self.selectedIndex = selectedIndex
        self.pendingClose = pendingClose
        self.commitWhenCloseCompletes = commitWhenCloseCompletes
        self.initialDirection = initialDirection
        self.queuedCycleOffset = queuedCycleOffset
        self.queuedCycleClampsAtBoundary = queuedCycleClampsAtBoundary
        self.commitWhenPrepared = commitWhenPrepared
        self.panelPresented = panelPresented
        repairSelectionInvariant()
    }

    public var selectedWindow: WindowRecord? {
        guard let selectedIndex, items.indices.contains(selectedIndex) else {
            return nil
        }
        return items[selectedIndex]
    }

    public var isPanelVisible: Bool {
        panelPresented
    }

    fileprivate mutating func reset() {
        self = SwitcherSessionState()
    }

    fileprivate mutating func repairSelectionInvariant() {
        guard !items.isEmpty else {
            selectedIndex = nil
            return
        }
        guard let selectedIndex else {
            return
        }
        self.selectedIndex = min(max(0, selectedIndex), items.count - 1)
    }
}

public enum SwitcherSessionAction: Equatable, Sendable {
    case begin(
        originalFocus: FocusSnapshot,
        initialDirection: SwitcherDirection = .forward
    )
    case prepared(snapshotGeneration: UInt64, orderedItems: [WindowRecord])
    case preparationFailed
    case cycle(SwitcherDirection)
    case repeatedCycle(SwitcherDirection)
    case mouseActivate(index: Int)
    case modifierReleased
    case cancel
    case closeSelected
    case close(index: Int)
    case closeCompleted(key: WindowKey, result: WindowActionResult)
    case activationCompleted(WindowActionResult)
    case registryUpdated(snapshotGeneration: UInt64, orderedItems: [WindowRecord])
    case panelDismissed
}

public enum SwitcherSessionEffect: Equatable, Sendable {
    case requestSnapshot(forceRefreshIfStale: Bool)
    case presentPanel
    case reloadPanel
    case selectionChanged(index: Int)
    case dismissPanel
    case activate(WindowKey)
    case close(WindowKey)
    case showFeedback(SwitcherSessionFeedback)
    case beep
}

public enum SwitcherSessionFeedback: Equatable, Sendable {
    case activationFailed
    case closeFailed
}

/// A deterministic state machine. Side effects are returned to the main-actor
/// coordinator, keeping all transition behavior directly unit-testable.
public enum SwitcherSessionReducer {
    @discardableResult
    public static func reduce(
        state: inout SwitcherSessionState,
        action: SwitcherSessionAction
    ) -> [SwitcherSessionEffect] {
        switch action {
        case let .begin(originalFocus, initialDirection):
            guard state.phase == .idle else {
                return []
            }
            state.phase = .preparing
            state.originalFocus = originalFocus
            state.initialDirection = initialDirection
            state.queuedCycleOffset = 0
            state.queuedCycleClampsAtBoundary = false
            state.commitWhenPrepared = false
            return [.requestSnapshot(forceRefreshIfStale: true)]

        case let .prepared(snapshotGeneration, orderedItems):
            guard state.phase == .preparing else {
                return []
            }
            return finishPreparation(
                state: &state,
                snapshotGeneration: snapshotGeneration,
                orderedItems: orderedItems
            )

        case .preparationFailed:
            guard state.phase == .preparing else {
                return []
            }
            state.reset()
            return []

        case let .cycle(direction):
            if state.phase == .preparing {
                switch direction {
                case .forward where state.queuedCycleOffset < .max:
                    state.queuedCycleOffset += 1
                case .backward where state.queuedCycleOffset > .min:
                    state.queuedCycleOffset -= 1
                case .forward, .backward:
                    break
                }
                return []
            }
            guard state.phase == .visible,
                  !state.items.isEmpty,
                  let selectedIndex = state.selectedIndex
            else {
                return []
            }
            let delta = direction == .forward ? 1 : -1
            let nextIndex = wrappedIndex(
                selectedIndex + delta,
                count: state.items.count
            )
            state.selectedIndex = nextIndex
            return [.selectionChanged(index: nextIndex)]

        case let .repeatedCycle(direction):
            if state.phase == .preparing {
                switch direction {
                case .forward where state.queuedCycleOffset < .max:
                    state.queuedCycleOffset += 1
                case .backward where state.queuedCycleOffset > .min:
                    state.queuedCycleOffset -= 1
                case .forward, .backward:
                    break
                }
                state.queuedCycleClampsAtBoundary = true
                return []
            }
            guard state.phase == .visible,
                  !state.items.isEmpty,
                  let selectedIndex = state.selectedIndex
            else {
                return []
            }
            let delta = direction == .forward ? 1 : -1
            let nextIndex = min(
                max(0, selectedIndex + delta),
                state.items.count - 1
            )
            guard nextIndex != selectedIndex else { return [] }
            state.selectedIndex = nextIndex
            return [.selectionChanged(index: nextIndex)]

        case let .mouseActivate(index):
            guard state.phase == .visible,
                  state.items.indices.contains(index)
            else {
                return []
            }
            state.selectedIndex = index
            return beginCommit(state: &state)

        case .modifierReleased:
            if state.phase == .preparing {
                state.commitWhenPrepared = true
                return []
            }
            guard state.phase == .visible else {
                return []
            }
            if state.pendingClose != nil {
                state.commitWhenCloseCompletes = true
                return []
            }
            return beginCommit(state: &state)

        case .cancel:
            switch state.phase {
            case .preparing:
                state.reset()
                return []
            case .visible:
                state.phase = .cancelling
                state.pendingClose = nil
                state.commitWhenCloseCompletes = false
                return [.dismissPanel]
            case .idle, .committing, .cancelling:
                return []
            }

        case .closeSelected:
            guard state.phase == .visible,
                  state.pendingClose == nil,
                  let selectedIndex = state.selectedIndex
            else {
                return []
            }
            return beginClose(state: &state, index: selectedIndex)

        case let .close(index):
            guard state.phase == .visible,
                  state.pendingClose == nil,
                  state.items.indices.contains(index)
            else {
                return []
            }
            return beginClose(state: &state, index: index)

        case let .closeCompleted(key, result):
            guard state.phase == .visible,
                  state.pendingClose == key
            else {
                return []
            }
            let shouldCommitAfterClose = state.commitWhenCloseCompletes
            state.pendingClose = nil
            state.commitWhenCloseCompletes = false
            var effects = handleCloseResult(
                state: &state,
                key: key,
                result: result
            )
            if shouldCommitAfterClose,
               (result.succeeded || result == .targetMissing),
               state.phase == .visible,
               let selected = state.selectedWindow {
                state.phase = .committing
                effects.append(.activate(selected.id))
            }
            return effects

        case let .activationCompleted(result):
            guard state.phase == .committing else {
                return []
            }
            if result.succeeded {
                state.reset()
                return [.dismissPanel]
            }
            state.phase = .visible
            return [
                .showFeedback(.activationFailed),
                .beep,
            ]

        case let .registryUpdated(snapshotGeneration, orderedItems):
            guard state.phase == .visible,
                  state.pendingClose == nil,
                  snapshotGeneration > (state.snapshotGeneration ?? 0)
            else {
                return []
            }
            return applyRegistryUpdate(
                state: &state,
                snapshotGeneration: snapshotGeneration,
                orderedItems: orderedItems
            )

        case .panelDismissed:
            if state.phase == .committing {
                state.panelPresented = false
                return []
            }
            if state.phase == .cancelling {
                state.reset()
                return []
            }
            return []
        }
    }

    private static func finishPreparation(
        state: inout SwitcherSessionState,
        snapshotGeneration: UInt64,
        orderedItems: [WindowRecord]
    ) -> [SwitcherSessionEffect] {
        let originalKey = state.originalFocus?.windowKey
        guard let firstAlternativeIndex = orderedItems.firstIndex(where: { $0.id != originalKey }) else {
            state.reset()
            return []
        }

        let initialIndex: Int
        switch state.initialDirection {
        case .forward:
            if let originalIndex = orderedItems.firstIndex(where: { $0.id == originalKey }) {
                initialIndex = firstIndex(
                    from: originalIndex,
                    step: 1,
                    excluding: originalKey,
                    items: orderedItems
                ) ?? firstAlternativeIndex
            } else {
                initialIndex = firstAlternativeIndex
            }
        case .backward:
            if let originalIndex = orderedItems.firstIndex(where: { $0.id == originalKey }) {
                initialIndex = firstIndex(
                    from: originalIndex,
                    step: -1,
                    excluding: originalKey,
                    items: orderedItems
                ) ?? firstAlternativeIndex
            } else {
                initialIndex = orderedItems.indices.last ?? firstAlternativeIndex
            }
        }
        let queuedIndex: Int
        if state.queuedCycleClampsAtBoundary {
            queuedIndex = min(
                max(0, initialIndex + state.queuedCycleOffset),
                orderedItems.count - 1
            )
        } else {
            let normalizedQueuedOffset =
                state.queuedCycleOffset % orderedItems.count
            queuedIndex = wrappedIndex(
                initialIndex + normalizedQueuedOffset,
                count: orderedItems.count
            )
        }

        state.snapshotGeneration = snapshotGeneration
        state.items = orderedItems
        state.selectedIndex = queuedIndex
        state.pendingClose = nil
        state.queuedCycleOffset = 0
        state.queuedCycleClampsAtBoundary = false

        if state.commitWhenPrepared {
            state.phase = .committing
            state.commitWhenPrepared = false
            state.panelPresented = false
            return [.activate(orderedItems[queuedIndex].id)]
        }

        state.phase = .visible
        state.panelPresented = true
        return [
            .presentPanel,
            .selectionChanged(index: queuedIndex),
        ]
    }

    private static func beginCommit(
        state: inout SwitcherSessionState
    ) -> [SwitcherSessionEffect] {
        guard let selected = state.selectedWindow else {
            state.phase = .cancelling
            return [.dismissPanel]
        }
        state.phase = .committing
        state.pendingClose = nil
        return [.activate(selected.id)]
    }

    private static func handleCloseResult(
        state: inout SwitcherSessionState,
        key: WindowKey,
        result: WindowActionResult
    ) -> [SwitcherSessionEffect] {
        switch result {
        case .success, .windowClosed, .applicationQuit, .targetMissing:
            return removeClosedItem(state: &state, key: key)
        case .confirmationRequired:
            state.phase = .committing
            return [
                .dismissPanel,
                .activate(key),
            ]
        case .permissionDenied, .unsupported, .timedOut, .failed:
            return [
                .showFeedback(.closeFailed),
                .beep,
            ]
        }
    }

    private static func beginClose(
        state: inout SwitcherSessionState,
        index: Int
    ) -> [SwitcherSessionEffect] {
        guard state.items.indices.contains(index) else {
            return []
        }

        var effects: [SwitcherSessionEffect] = []
        if state.selectedIndex != index {
            state.selectedIndex = index
            effects.append(.selectionChanged(index: index))
        }

        let selected = state.items[index]
        guard selected.isClosable else {
            effects.append(.beep)
            return effects
        }
        state.pendingClose = selected.id
        state.commitWhenCloseCompletes = false
        effects.append(.close(selected.id))
        return effects
    }

    private static func removeClosedItem(
        state: inout SwitcherSessionState,
        key: WindowKey
    ) -> [SwitcherSessionEffect] {
        guard let removedIndex = state.items.firstIndex(where: { $0.id == key }) else {
            return []
        }
        state.items.remove(at: removedIndex)

        guard !state.items.isEmpty else {
            state.selectedIndex = nil
            state.phase = .cancelling
            return [
                .reloadPanel,
                .dismissPanel,
            ]
        }

        let nextIndex = min(removedIndex, state.items.count - 1)
        state.selectedIndex = nextIndex
        return [
            .reloadPanel,
            .selectionChanged(index: nextIndex),
        ]
    }

    private static func applyRegistryUpdate(
        state: inout SwitcherSessionState,
        snapshotGeneration: UInt64,
        orderedItems: [WindowRecord]
    ) -> [SwitcherSessionEffect] {
        let previousIndex = state.selectedIndex ?? 0
        let selectedKey = state.selectedWindow?.id
        state.snapshotGeneration = snapshotGeneration
        state.items = orderedItems
        state.pendingClose = state.pendingClose.flatMap { pending in
            orderedItems.contains(where: { $0.id == pending }) ? pending : nil
        }

        guard !orderedItems.isEmpty else {
            state.selectedIndex = nil
            state.phase = .cancelling
            return [
                .reloadPanel,
                .dismissPanel,
            ]
        }

        let nextIndex: Int
        if let selectedKey,
           let preservedIndex = orderedItems.firstIndex(where: { $0.id == selectedKey }) {
            nextIndex = preservedIndex
        } else {
            nextIndex = min(previousIndex, orderedItems.count - 1)
        }
        state.selectedIndex = nextIndex

        return [
            .reloadPanel,
            .selectionChanged(index: nextIndex),
        ]
    }

    private static func wrappedIndex(_ index: Int, count: Int) -> Int {
        precondition(count > 0)
        let remainder = index % count
        return remainder >= 0 ? remainder : remainder + count
    }

    private static func firstIndex(
        from index: Int,
        step: Int,
        excluding key: WindowKey?,
        items: [WindowRecord]
    ) -> Int? {
        precondition(step == 1 || step == -1)
        guard items.count > 1 else {
            return nil
        }
        for distance in 1 ..< items.count {
            let candidate = wrappedIndex(
                index + (distance * step),
                count: items.count
            )
            if items[candidate].id != key {
                return candidate
            }
        }
        return nil
    }
}
