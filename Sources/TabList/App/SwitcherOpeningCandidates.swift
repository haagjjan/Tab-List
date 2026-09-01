import CoreGraphics
import Foundation
import TabListCore

/// Pure preparation output for the first switcher presentation.
///
/// Keeping this conversion separate makes the cached-first contract explicit:
/// a prefetched registry snapshot can be filtered and presented synchronously,
/// while the coordinator schedules a fresh reconciliation afterward.
struct SwitcherOpeningCandidates: Equatable, Sendable {
    let snapshotGeneration: UInt64
    let orderedItems: [WindowRecord]

    func containsAlternative(to currentWindowKey: WindowKey?) -> Bool {
        orderedItems.contains { $0.id != currentWindowKey }
    }

    static func cached(
        from snapshot: WindowSnapshot?,
        settings: TabListSettings,
        pointerDisplayID: CGDirectDisplayID?,
        currentWindowKey: WindowKey? = nil
    ) -> Self? {
        guard let snapshot,
              WindowSnapshotValidator.isValid(snapshot) else {
            return nil
        }
        return make(
            from: snapshot,
            settings: settings,
            pointerDisplayID: pointerDisplayID,
            currentWindowKey: currentWindowKey
        )
    }

    static func make(
        from snapshot: WindowSnapshot,
        settings: TabListSettings,
        pointerDisplayID: CGDirectDisplayID?,
        currentWindowKey: WindowKey? = nil
    ) -> Self {
        var orderedItems = WindowSelectionPipeline.candidates(
            from: snapshot,
            settings: settings,
            pointerDisplayID: pointerDisplayID
        )
        if let currentWindowKey,
           let currentIndex = orderedItems.firstIndex(
               where: { $0.id == currentWindowKey }
           ),
           currentIndex != orderedItems.startIndex {
            let current = orderedItems.remove(at: currentIndex)
            orderedItems.insert(current, at: orderedItems.startIndex)
        }
        return Self(
            snapshotGeneration: snapshot.generation,
            orderedItems: orderedItems
        )
    }
}
