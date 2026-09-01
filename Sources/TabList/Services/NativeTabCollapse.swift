import CoreGraphics
import Foundation

/// Collapses an AppKit native tab group to the single member the user can
/// actually reach.
///
/// Tab members of one tabbed window share a frame, and only the selected member
/// is reachable, so a same-frame group whose members report a matching
/// `AXTabs` count becomes one row. The tab count is supplied lazily because
/// reading it is an Accessibility round trip that must not happen for the
/// common case of windows that merely overlap.
enum NativeTabCollapse {
    struct Frame: Hashable {
        let x: Int
        let y: Int
        let width: Int
        let height: Int

        init(_ bounds: CGRect) {
            x = Int(bounds.origin.x.rounded())
            y = Int(bounds.origin.y.rounded())
            width = Int(bounds.width.rounded())
            height = Int(bounds.height.rounded())
        }
    }

    struct Candidate {
        let frame: Frame
        let isMain: Bool

        init(frame: Frame, isMain: Bool) {
            self.frame = frame
            self.isMain = isMain
        }
    }

    /// Indices to keep, in their original order.
    static func retainedIndices(
        of candidates: [Candidate],
        tabCount: (Int) -> Int
    ) -> [Int] {
        guard candidates.count > 1 else {
            return Array(candidates.indices)
        }

        let groups = Dictionary(
            grouping: candidates.indices,
            by: { candidates[$0].frame }
        )
        var dropped: Set<Int> = []
        for indices in groups.values where indices.count > 1 {
            let sorted = indices.sorted()
            guard sorted.contains(where: { tabCount($0) == sorted.count })
            else {
                continue
            }
            let retained = sorted.first { candidates[$0].isMain } ?? sorted[0]
            dropped.formUnion(sorted.filter { $0 != retained })
        }
        return candidates.indices.filter { !dropped.contains($0) }
    }
}
