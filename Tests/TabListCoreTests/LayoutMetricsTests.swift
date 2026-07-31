import CoreGraphics
import Testing
@testable import TabListCore

@Suite
struct LayoutMetricsTests {
    private let display = CGRect(x: 0, y: 0, width: 1_440, height: 900)

    @Test
    func testThumbnailPresetsShrinkWrapSmallCandidateCounts() {
        XCTAssertEqual(
            LayoutCalculator.metrics(
                preset: .small,
                presentation: .thumbnails,
                displayVisibleFrame: display,
                itemCount: 1
            ).panelSize.width,
            272
        )
        XCTAssertEqual(
            LayoutCalculator.metrics(
                preset: .medium,
                presentation: .thumbnails,
                displayVisibleFrame: display,
                itemCount: 1
            ).panelSize.width,
            332
        )
        XCTAssertEqual(
            LayoutCalculator.metrics(
                preset: .large,
                presentation: .thumbnails,
                displayVisibleFrame: display,
                itemCount: 1
            ).panelSize.width,
            392
        )
    }

    @Test
    func testThumbnailAndTitleItemSizesMatchSpecification() {
        let thumbnail = LayoutCalculator.metrics(
            preset: .medium,
            presentation: .thumbnails,
            displayVisibleFrame: display,
            itemCount: 1
        )
        let title = LayoutCalculator.metrics(
            preset: .large,
            presentation: .titles,
            displayVisibleFrame: display,
            itemCount: 1
        )

        XCTAssertEqual(
            thumbnail.previewViewportSize,
            CGSize(width: 284, height: 177.5)
        )
        XCTAssertEqual(thumbnail.itemSize.height, 237.5)
        XCTAssertEqual(title.itemSize.height, 56)
        XCTAssertEqual(title.columns, 1)
    }

    @Test
    func testPanelHeightIsLimitedToSeventyTwoPercentAndScrolls() {
        let metrics = LayoutCalculator.metrics(
            preset: .small,
            presentation: .thumbnails,
            displayVisibleFrame: display,
            itemCount: 100
        )

        XCTAssertEqual(metrics.panelSize.height, 648)
        XCTAssertTrue(metrics.isScrollable)
        XCTAssertEqual(metrics.rows, 50)
    }

    @Test
    func testAutomaticThumbnailLayoutUsesTwoRowsForFourToEightItems() {
        let sixItems = LayoutCalculator.metrics(
            preset: .auto,
            presentation: .thumbnails,
            displayVisibleFrame: display,
            itemCount: 6
        )
        let sevenItems = LayoutCalculator.metrics(
            preset: .auto,
            presentation: .thumbnails,
            displayVisibleFrame: display,
            itemCount: 7
        )

        XCTAssertEqual(sixItems.resolvedPreset, .large)
        XCTAssertEqual(sixItems.columns, 3)
        XCTAssertEqual(sixItems.rows, 2)
        XCTAssertEqual(sevenItems.resolvedPreset, .large)
        XCTAssertEqual(sevenItems.columns, 4)
        XCTAssertEqual(sevenItems.rows, 2)
        XCTAssertTrue(sevenItems.centersIncompleteFinalRow)
    }

    @Test
    func testAutomaticTitleModeUsesCompactSmallRows() {
        let metrics = LayoutCalculator.metrics(
            preset: .auto,
            presentation: .titles,
            displayVisibleFrame: display,
            itemCount: 8
        )

        XCTAssertEqual(metrics.resolvedPreset, .small)
        XCTAssertEqual(metrics.itemSize.height, 40)
        XCTAssertEqual(metrics.rows, 8)
    }

    @Test
    func testTitleModeGrowsIntrinsicallyThenEnablesScrolling() {
        let one = LayoutCalculator.metrics(
            preset: .auto,
            presentation: .titles,
            displayVisibleFrame: display,
            itemCount: 1
        )
        let five = LayoutCalculator.metrics(
            preset: .auto,
            presentation: .titles,
            displayVisibleFrame: display,
            itemCount: 5
        )
        let twelve = LayoutCalculator.metrics(
            preset: .auto,
            presentation: .titles,
            displayVisibleFrame: display,
            itemCount: 12
        )
        let thirteen = LayoutCalculator.metrics(
            preset: .auto,
            presentation: .titles,
            displayVisibleFrame: display,
            itemCount: 13
        )

        XCTAssertEqual(one.panelSize.height, 72)
        XCTAssertEqual(five.panelSize.height, 280)
        XCTAssertEqual(twelve.panelSize.height, 644)
        XCTAssertFalse(twelve.isScrollable)
        XCTAssertEqual(thirteen.panelSize.height, 648)
        XCTAssertTrue(thirteen.isScrollable)
    }

    @Test
    func testNarrowDisplayAlwaysProducesAtLeastOneColumn() {
        let metrics = LayoutCalculator.metrics(
            preset: .large,
            presentation: .thumbnails,
            displayVisibleFrame: CGRect(x: 0, y: 0, width: 200, height: 300),
            itemCount: 2
        )

        XCTAssertEqual(metrics.panelSize.width, 180)
        XCTAssertEqual(metrics.columns, 1)
        XCTAssertLessThanOrEqual(
            metrics.itemSize.width,
            metrics.panelSize.width - (metrics.outerPadding * 2)
        )
    }

    @Test
    func testInvalidDisplayGeometryUsesDeterministicFallback() {
        let metrics = LayoutCalculator.metrics(
            preset: .small,
            presentation: .appIcons,
            displayVisibleFrame: CGRect(
                x: 0,
                y: 0,
                width: CGFloat.nan,
                height: CGFloat.infinity
            ),
            itemCount: 1
        )

        XCTAssertEqual(metrics.panelSize.width, 620)
        XCTAssertTrue(metrics.panelSize.height.isFinite)
    }

    @Test
    func testConstantsMeetAccessibilityAndVisualRequirements() {
        let metrics = LayoutCalculator.metrics(
            preset: .small,
            presentation: .titles,
            displayVisibleFrame: display,
            itemCount: 1
        )

        XCTAssertEqual(metrics.outerPadding, 16)
        XCTAssertEqual(metrics.itemGap, 12)
        XCTAssertEqual(metrics.panelCornerRadius, 16)
        XCTAssertEqual(metrics.selectionCornerRadius, 12)
        XCTAssertGreaterThanOrEqual(metrics.closeControlHitSize, 24)
    }
}
