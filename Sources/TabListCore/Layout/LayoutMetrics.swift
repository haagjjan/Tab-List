import CoreGraphics
import Foundation

public struct PanelLayoutMetrics: Equatable, Sendable {
    public let requestedPreset: PanelSize
    public let resolvedPreset: PanelSize
    public let presentation: PresentationMode
    public let panelSize: CGSize
    public let itemSize: CGSize
    public let previewSize: CGSize?
    public let previewViewportSize: CGSize?
    public let columns: Int
    public let rows: Int
    public let lastRowItemCount: Int
    public let centersIncompleteFinalRow: Bool
    public let isScrollable: Bool
    public let outerPadding: CGFloat
    public let itemGap: CGFloat
    public let panelCornerRadius: CGFloat
    public let selectionCornerRadius: CGFloat
    public let closeControlHitSize: CGFloat

    public init(
        requestedPreset: PanelSize,
        resolvedPreset: PanelSize,
        presentation: PresentationMode,
        panelSize: CGSize,
        itemSize: CGSize,
        previewSize: CGSize?,
        previewViewportSize: CGSize?,
        columns: Int,
        rows: Int,
        lastRowItemCount: Int,
        centersIncompleteFinalRow: Bool,
        isScrollable: Bool,
        outerPadding: CGFloat,
        itemGap: CGFloat,
        panelCornerRadius: CGFloat,
        selectionCornerRadius: CGFloat,
        closeControlHitSize: CGFloat
    ) {
        self.requestedPreset = requestedPreset
        self.resolvedPreset = resolvedPreset
        self.presentation = presentation
        self.panelSize = panelSize
        self.itemSize = itemSize
        self.previewSize = previewSize
        self.previewViewportSize = previewViewportSize
        self.columns = columns
        self.rows = rows
        self.lastRowItemCount = lastRowItemCount
        self.centersIncompleteFinalRow = centersIncompleteFinalRow
        self.isScrollable = isScrollable
        self.outerPadding = outerPadding
        self.itemGap = itemGap
        self.panelCornerRadius = panelCornerRadius
        self.selectionCornerRadius = selectionCornerRadius
        self.closeControlHitSize = closeControlHitSize
    }
}

public enum LayoutCalculator {
    public static let outerPadding: CGFloat = 16
    public static let itemGap: CGFloat = 12
    public static let panelCornerRadius: CGFloat = 16
    public static let selectionCornerRadius: CGFloat = 12
    public static let closeControlHitSize: CGFloat = 24
    public static let maximumDisplayHeightRatio: CGFloat = 0.72

    public static func metrics(
        preset: PanelSize,
        presentation: PresentationMode,
        displayVisibleFrame: CGRect,
        itemCount: Int
    ) -> PanelLayoutMetrics {
        let count = max(itemCount, 0)
        let displaySize = sanitizedDisplaySize(displayVisibleFrame.size)
        let resolved = preset == .auto
            ? automaticPreset(
                presentation: presentation,
                displaySize: displaySize,
                itemCount: count
            )
            : preset

        return fixedMetrics(
            requestedPreset: preset,
            resolvedPreset: resolved,
            presentation: presentation,
            displaySize: displaySize,
            itemCount: count
        )
    }

    private static func automaticPreset(
        presentation: PresentationMode,
        displaySize: CGSize,
        itemCount: Int
    ) -> PanelSize {
        guard presentation != .titles else {
            return .small
        }

        if presentation == .thumbnails {
            return itemCount <= 3 ? .medium : .large
        }

        for preset in [PanelSize.small, .medium, .large] {
            let candidate = fixedMetrics(
                requestedPreset: .auto,
                resolvedPreset: preset,
                presentation: presentation,
                displaySize: displaySize,
                itemCount: itemCount
            )
            if candidate.rows <= 3 {
                return preset
            }
        }
        return .large
    }

    private static func fixedMetrics(
        requestedPreset: PanelSize,
        resolvedPreset: PanelSize,
        presentation: PresentationMode,
        displaySize: CGSize,
        itemCount: Int
    ) -> PanelLayoutMetrics {
        precondition(resolvedPreset != .auto)

        if presentation == .thumbnails {
            return thumbnailMetrics(
                requestedPreset: requestedPreset,
                resolvedPreset: resolvedPreset,
                displaySize: displaySize,
                itemCount: itemCount
            )
        }

        let panelWidth = width(
            for: resolvedPreset,
            displayWidth: displaySize.width
        )
        let itemAndPreview = itemSizes(
            for: resolvedPreset,
            presentation: presentation,
            panelWidth: panelWidth
        )
        let columns = columnCount(
            presentation: presentation,
            panelWidth: panelWidth,
            itemWidth: itemAndPreview.item.width
        )
        let rows = itemCount == 0
            ? 0
            : Int(ceil(Double(itemCount) / Double(columns)))
        let intrinsicHeight = intrinsicPanelHeight(
            rows: rows,
            itemHeight: itemAndPreview.item.height
        )
        let maximumHeight = displaySize.height * maximumDisplayHeightRatio
        let panelHeight = min(intrinsicHeight, maximumHeight)

        return PanelLayoutMetrics(
            requestedPreset: requestedPreset,
            resolvedPreset: resolvedPreset,
            presentation: presentation,
            panelSize: CGSize(width: panelWidth, height: panelHeight),
            itemSize: itemAndPreview.item,
            previewSize: itemAndPreview.preview,
            previewViewportSize: itemAndPreview.preview,
            columns: columns,
            rows: rows,
            lastRowItemCount: rows == 0
                ? 0
                : itemCount - ((rows - 1) * columns),
            centersIncompleteFinalRow: presentation != .titles,
            isScrollable: intrinsicHeight > maximumHeight,
            outerPadding: outerPadding,
            itemGap: itemGap,
            panelCornerRadius: panelCornerRadius,
            selectionCornerRadius: selectionCornerRadius,
            closeControlHitSize: closeControlHitSize
        )
    }

    private static func thumbnailMetrics(
        requestedPreset: PanelSize,
        resolvedPreset: PanelSize,
        displaySize: CGSize,
        itemCount: Int
    ) -> PanelLayoutMetrics {
        let maximumPanelWidth = width(
            for: resolvedPreset,
            displayWidth: displaySize.width
        )
        let targetCardWidth: CGFloat = switch resolvedPreset {
        case .small: 240
        case .medium: 300
        case .large: 360
        case .auto: 300
        }
        let minimumReadableCardWidth = min(
            220,
            max(1, maximumPanelWidth - (outerPadding * 2))
        )
        let maximumFittingColumns = max(
            1,
            Int(floor(
                (maximumPanelWidth - (outerPadding * 2) + itemGap)
                    / (minimumReadableCardWidth + itemGap)
            ))
        )

        let desiredColumns: Int
        switch itemCount {
        case ...0:
            desiredColumns = 1
        case 1 ... 3:
            desiredColumns = itemCount
        case 4 ... 8:
            desiredColumns = Int(ceil(Double(itemCount) / 2.0))
        default:
            desiredColumns = maximumFittingColumns
        }
        let columns = max(
            1,
            min(
                min(maximumFittingColumns, desiredColumns),
                max(itemCount, 1)
            )
        )
        let availableCardWidth = (
            maximumPanelWidth
                - (outerPadding * 2)
                - (CGFloat(columns - 1) * itemGap)
        ) / CGFloat(columns)
        let cardWidth = min(targetCardWidth, max(1, availableCardWidth))
        let previewViewport = CGSize(
            width: max(1, cardWidth - 16),
            height: max(1, (cardWidth - 16) * 0.625)
        )
        let cardSize = CGSize(
            width: cardWidth,
            height: previewViewport.height + 60
        )
        let panelWidth = min(
            maximumPanelWidth,
            (outerPadding * 2)
                + (CGFloat(columns) * cardWidth)
                + (CGFloat(columns - 1) * itemGap)
        )
        let rows = itemCount == 0
            ? 0
            : Int(ceil(Double(itemCount) / Double(columns)))
        let intrinsicHeight = intrinsicPanelHeight(
            rows: rows,
            itemHeight: cardSize.height
        )
        let maximumHeight = displaySize.height * maximumDisplayHeightRatio
        let lastRowItemCount = rows == 0
            ? 0
            : itemCount - ((rows - 1) * columns)

        return PanelLayoutMetrics(
            requestedPreset: requestedPreset,
            resolvedPreset: resolvedPreset,
            presentation: .thumbnails,
            panelSize: CGSize(
                width: panelWidth,
                height: min(intrinsicHeight, maximumHeight)
            ),
            itemSize: cardSize,
            previewSize: previewViewport,
            previewViewportSize: previewViewport,
            columns: columns,
            rows: rows,
            lastRowItemCount: lastRowItemCount,
            centersIncompleteFinalRow: lastRowItemCount > 0
                && lastRowItemCount < columns,
            isScrollable: intrinsicHeight > maximumHeight,
            outerPadding: outerPadding,
            itemGap: itemGap,
            panelCornerRadius: panelCornerRadius,
            selectionCornerRadius: selectionCornerRadius,
            closeControlHitSize: closeControlHitSize
        )
    }

    private static func width(
        for preset: PanelSize,
        displayWidth: CGFloat
    ) -> CGFloat {
        let desired: CGFloat
        switch preset {
        case .small:
            desired = min(620, displayWidth * 0.60)
        case .medium:
            desired = min(900, displayWidth * 0.75)
        case .large:
            desired = min(1_200, displayWidth * 0.90)
        case .auto:
            preconditionFailure("Auto must be resolved before calculating width")
        }
        return min(max(desired, 1), displayWidth)
    }

    private static func itemSizes(
        for preset: PanelSize,
        presentation: PresentationMode,
        panelWidth: CGFloat
    ) -> (item: CGSize, preview: CGSize?) {
        let availableWidth = max(1, panelWidth - (outerPadding * 2))
        switch (preset, presentation) {
        case (.small, .thumbnails):
            return thumbnailSizes(
                targetPreview: CGSize(width: 240, height: 160),
                availableWidth: availableWidth
            )
        case (.medium, .thumbnails):
            return thumbnailSizes(
                targetPreview: CGSize(width: 300, height: 200),
                availableWidth: availableWidth
            )
        case (.large, .thumbnails):
            return thumbnailSizes(
                targetPreview: CGSize(width: 360, height: 240),
                availableWidth: availableWidth
            )
        case (.small, .appIcons):
            return iconSizes(targetWidth: 120, availableWidth: availableWidth)
        case (.medium, .appIcons):
            return iconSizes(targetWidth: 148, availableWidth: availableWidth)
        case (.large, .appIcons):
            return iconSizes(targetWidth: 176, availableWidth: availableWidth)
        case (.small, .titles):
            return (CGSize(width: availableWidth, height: 40), nil)
        case (.medium, .titles):
            return (CGSize(width: availableWidth, height: 48), nil)
        case (.large, .titles):
            return (CGSize(width: availableWidth, height: 56), nil)
        case (.auto, _):
            preconditionFailure("Auto must be resolved before calculating item size")
        }
    }

    private static func thumbnailSizes(
        targetPreview: CGSize,
        availableWidth: CGFloat
    ) -> (item: CGSize, preview: CGSize?) {
        let width = min(targetPreview.width, availableWidth)
        let scale = width / targetPreview.width
        let preview = CGSize(
            width: width,
            height: targetPreview.height * scale
        )
        return (
            CGSize(width: width, height: preview.height + 44),
            preview
        )
    }

    private static func iconSizes(
        targetWidth: CGFloat,
        availableWidth: CGFloat
    ) -> (item: CGSize, preview: CGSize?) {
        let width = min(targetWidth, availableWidth)
        return (CGSize(width: width, height: width + 32), nil)
    }

    private static func columnCount(
        presentation: PresentationMode,
        panelWidth: CGFloat,
        itemWidth: CGFloat
    ) -> Int {
        guard presentation != .titles else {
            return 1
        }
        let usableWidth = max(0, panelWidth - (outerPadding * 2))
        return max(1, Int(floor((usableWidth + itemGap) / (itemWidth + itemGap))))
    }

    private static func intrinsicPanelHeight(
        rows: Int,
        itemHeight: CGFloat
    ) -> CGFloat {
        guard rows > 0 else {
            return outerPadding * 2
        }
        return (outerPadding * 2)
            + (CGFloat(rows) * itemHeight)
            + (CGFloat(rows - 1) * itemGap)
    }

    private static func sanitizedDisplaySize(_ size: CGSize) -> CGSize {
        let width = size.width.isFinite && size.width > 0 ? size.width : 1_440
        let height = size.height.isFinite && size.height > 0 ? size.height : 900
        return CGSize(width: width, height: height)
    }
}
