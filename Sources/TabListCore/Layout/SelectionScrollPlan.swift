import CoreGraphics
import Foundation

public enum SelectionMovement: Equatable, Sendable {
    case stationary
    case forward
    case backward
}

public enum SelectionScrollAlignment: Equatable, Sendable {
    case none
    case centered
}

/// Pure selection-following policy used by the AppKit panel.
///
/// A visible row is left alone until it crosses the directional comfort-zone
/// boundary. Offscreen and wrapped selections are centered immediately.
public enum SelectionScrollPlanner {
    public static let defaultComfortZoneRatio: CGFloat = 0.60

    public static func alignment(
        selectedFrame: CGRect,
        visibleRect: CGRect,
        movement: SelectionMovement,
        comfortZoneRatio: CGFloat = defaultComfortZoneRatio
    ) -> SelectionScrollAlignment {
        guard selectedFrame.isFiniteAndNonempty,
              visibleRect.isFiniteAndNonempty
        else {
            return .centered
        }

        guard visibleRect.contains(selectedFrame) else {
            return .centered
        }

        guard movement != .stationary else {
            return .none
        }

        let ratio = min(max(comfortZoneRatio, 0.10), 1.0)
        let verticalInset = visibleRect.height * (1 - ratio) / 2
        let comfortZone = visibleRect.insetBy(
            dx: 0,
            dy: verticalInset
        )

        switch movement {
        case .stationary:
            return .none
        case .forward:
            return selectedFrame.maxY > comfortZone.maxY
                ? .centered
                : .none
        case .backward:
            return selectedFrame.minY < comfortZone.minY
                ? .centered
                : .none
        }
    }
}

private extension CGRect {
    var isFiniteAndNonempty: Bool {
        origin.x.isFinite
            && origin.y.isFinite
            && width.isFinite
            && height.isFinite
            && width > 0
            && height > 0
    }
}
