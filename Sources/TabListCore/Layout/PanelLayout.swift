import CoreGraphics
import Foundation

public struct PanelLayout: Equatable, Sendable {
    public let panelSize: CGSize
    public let rowHeight: CGFloat
    public let rowCount: Int
    public let visibleRowCount: Int
    public let isScrollable: Bool
    public let outerPadding: CGFloat
    public let cornerRadius: CGFloat

    public init(
        panelSize: CGSize,
        rowHeight: CGFloat,
        rowCount: Int,
        visibleRowCount: Int,
        isScrollable: Bool,
        outerPadding: CGFloat,
        cornerRadius: CGFloat
    ) {
        self.panelSize = panelSize
        self.rowHeight = rowHeight
        self.rowCount = rowCount
        self.visibleRowCount = visibleRowCount
        self.isScrollable = isScrollable
        self.outerPadding = outerPadding
        self.cornerRadius = cornerRadius
    }
}

/// Geometry for the single-column switcher list.
///
/// The panel grows with the number of rows until it reaches a fraction of the
/// display's visible frame, after which the list scrolls.
public enum PanelLayoutCalculator {
    public static let rowHeight: CGFloat = 44
    public static let outerPadding: CGFloat = 10
    public static let cornerRadius: CGFloat = 16
    public static let rowCornerRadius: CGFloat = 8
    public static let maximumHeightRatio: CGFloat = 0.72
    public static let maximumWidth: CGFloat = 760
    public static let minimumWidth: CGFloat = 360

    public static func layout(
        displayVisibleFrame: CGRect,
        itemCount: Int
    ) -> PanelLayout {
        let display = sanitized(displayVisibleFrame.size)
        let rowCount = max(0, itemCount)

        let width = min(
            max(min(maximumWidth, display.width * 0.52), minimumWidth),
            display.width
        )
        let contentHeight = CGFloat(rowCount) * rowHeight
        let intrinsicHeight = contentHeight + (outerPadding * 2)
        let maximumHeight = max(
            rowHeight + (outerPadding * 2),
            display.height * maximumHeightRatio
        )
        let height = min(intrinsicHeight, maximumHeight)
        let visibleRowCount = rowCount == 0
            ? 0
            : min(
                rowCount,
                max(1, Int(((height - (outerPadding * 2)) / rowHeight).rounded(.down)))
            )

        return PanelLayout(
            panelSize: CGSize(width: width.rounded(), height: height.rounded()),
            rowHeight: rowHeight,
            rowCount: rowCount,
            visibleRowCount: visibleRowCount,
            isScrollable: intrinsicHeight > maximumHeight,
            outerPadding: outerPadding,
            cornerRadius: cornerRadius
        )
    }

    private static func sanitized(_ size: CGSize) -> CGSize {
        CGSize(
            width: size.width.isFinite && size.width > 0 ? size.width : 1_440,
            height: size.height.isFinite && size.height > 0 ? size.height : 900
        )
    }
}
