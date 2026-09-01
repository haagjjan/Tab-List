import CoreGraphics
import Testing
@testable import TabListCore

@Suite
struct PanelLayoutTests {
    private let display = CGRect(x: 0, y: 0, width: 1_512, height: 944)

    @Test
    func testPanelHeightGrowsWithTheRowCountUntilItIsCapped() {
        let padding = PanelLayoutCalculator.outerPadding * 2
        let rowHeight = PanelLayoutCalculator.rowHeight

        let three = PanelLayoutCalculator.layout(
            displayVisibleFrame: display,
            itemCount: 3
        )
        XCTAssertEqual(three.panelSize.height, (rowHeight * 3) + padding)
        XCTAssertFalse(three.isScrollable)
        XCTAssertEqual(three.visibleRowCount, 3)

        let many = PanelLayoutCalculator.layout(
            displayVisibleFrame: display,
            itemCount: 100
        )
        XCTAssertTrue(many.isScrollable)
        XCTAssertTrue(many.visibleRowCount < 100)
        XCTAssertTrue(
            many.panelSize.height
                <= (display.height * PanelLayoutCalculator.maximumHeightRatio)
                    .rounded(.up)
        )
    }

    @Test
    func testPanelWidthStaysBetweenTheMinimumAndMaximum() {
        let wide = PanelLayoutCalculator.layout(
            displayVisibleFrame: CGRect(x: 0, y: 0, width: 5_120, height: 2_880),
            itemCount: 8
        )
        XCTAssertEqual(wide.panelSize.width, PanelLayoutCalculator.maximumWidth)

        let narrow = PanelLayoutCalculator.layout(
            displayVisibleFrame: CGRect(x: 0, y: 0, width: 500, height: 600),
            itemCount: 8
        )
        XCTAssertEqual(
            narrow.panelSize.width,
            PanelLayoutCalculator.minimumWidth
        )
    }

    @Test
    func testPanelNeverExceedsATinyDisplay() {
        let tiny = CGRect(x: 0, y: 0, width: 300, height: 240)
        let layout = PanelLayoutCalculator.layout(
            displayVisibleFrame: tiny,
            itemCount: 20
        )

        XCTAssertTrue(layout.panelSize.width <= tiny.width)
        XCTAssertTrue(layout.panelSize.height <= tiny.height)
        XCTAssertTrue(layout.visibleRowCount >= 1)
    }

    @Test
    func testNonFiniteDisplayFallsBackToADefaultSize() {
        let layout = PanelLayoutCalculator.layout(
            displayVisibleFrame: CGRect(
                x: 0,
                y: 0,
                width: CGFloat.nan,
                height: CGFloat.infinity
            ),
            itemCount: 5
        )

        XCTAssertTrue(layout.panelSize.width.isFinite)
        XCTAssertTrue(layout.panelSize.height.isFinite)
        XCTAssertTrue(layout.panelSize.width > 0)
        XCTAssertTrue(layout.panelSize.height > 0)
    }

    @Test
    func testEmptyListStillProducesAUsablePanel() {
        let layout = PanelLayoutCalculator.layout(
            displayVisibleFrame: display,
            itemCount: 0
        )

        XCTAssertEqual(layout.rowCount, 0)
        XCTAssertEqual(layout.visibleRowCount, 0)
        XCTAssertFalse(layout.isScrollable)
        XCTAssertTrue(layout.panelSize.width > 0)
    }
}
