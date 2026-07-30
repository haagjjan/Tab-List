import Foundation

public enum MRUOrdering {
    /// Orders newest focus first while preserving source order for equal or
    /// unknown focus sequences.
    public static func sorted(_ windows: [WindowRecord]) -> [WindowRecord] {
        windows
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.lastFocusSequence != rhs.element.lastFocusSequence {
                    return lhs.element.lastFocusSequence > rhs.element.lastFocusSequence
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}

/// Pure MRU bookkeeping used by the registry actor.
///
/// App activation alone must never call `recordFocus`; only a confirmed focused
/// window event advances the sequence.
public struct WindowMRUTracker: Sendable {
    public private(set) var currentSequence: UInt64
    private var sequences: [WindowKey: UInt64]

    public init(
        currentSequence: UInt64 = 0,
        sequences: [WindowKey: UInt64] = [:]
    ) {
        self.currentSequence = max(currentSequence, sequences.values.max() ?? 0)
        self.sequences = sequences
    }

    public func sequence(for key: WindowKey) -> UInt64 {
        sequences[key] ?? 0
    }

    /// Seeds startup z-order. `frontToBack` must be the WindowServer order.
    /// Existing focus evidence is retained, and later unknown windows sort last.
    public mutating func seed(
        frontToBack keys: [WindowKey],
        knownVisibleKeys: Set<WindowKey>? = nil
    ) {
        guard sequences.isEmpty else {
            for key in keys where sequences[key] == nil {
                sequences[key] = 0
            }
            return
        }

        let seedOrder: [WindowKey]
        if let knownVisibleKeys {
            seedOrder = keys.filter(knownVisibleKeys.contains)
                + keys.filter { !knownVisibleKeys.contains($0) }
        } else {
            seedOrder = keys
        }

        for key in seedOrder.reversed() {
            sequences[key] = nextSequence()
        }
    }

    @discardableResult
    public mutating func recordFocus(_ key: WindowKey) -> UInt64 {
        let sequence = nextSequence()
        sequences[key] = sequence
        return sequence
    }

    public mutating func remove(_ key: WindowKey) {
        sequences.removeValue(forKey: key)
    }

    public mutating func retainOnly(_ keys: Set<WindowKey>) {
        sequences = sequences.filter { keys.contains($0.key) }
    }

    public func applyingSequences(to windows: [WindowRecord]) -> [WindowRecord] {
        windows.map { window in
            var updated = window
            updated.lastFocusSequence = sequence(for: window.id)
            return updated
        }
    }

    private mutating func nextSequence() -> UInt64 {
        if currentSequence == .max {
            rebase()
        }
        currentSequence += 1
        return currentSequence
    }

    private mutating func rebase() {
        let ordered = sequences.sorted { lhs, rhs in
            if lhs.value != rhs.value {
                return lhs.value < rhs.value
            }
            if lhs.key.pid != rhs.key.pid {
                return lhs.key.pid < rhs.key.pid
            }
            return lhs.key.windowID < rhs.key.windowID
        }

        sequences.removeAll(keepingCapacity: true)
        for (offset, entry) in ordered.enumerated() {
            sequences[entry.key] = UInt64(offset + 1)
        }
        currentSequence = UInt64(ordered.count)
    }
}
