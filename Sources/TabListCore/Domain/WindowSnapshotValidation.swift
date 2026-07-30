import CoreGraphics

public enum WindowSnapshotValidator {
    public static func isValid(_ snapshot: WindowSnapshot) -> Bool {
        var keys: Set<WindowKey> = []
        return snapshot.windows.allSatisfy { window in
            window.id.pid > 0
                && window.id.windowID != 0
                && keys.insert(window.id).inserted
                && isValid(window.bounds)
        }
    }

    private static func isValid(_ bounds: CGRect) -> Bool {
        bounds.origin.x.isFinite
            && bounds.origin.y.isFinite
            && bounds.width.isFinite
            && bounds.height.isFinite
            && bounds.width > 0
            && bounds.height > 0
    }
}
