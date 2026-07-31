import CoreGraphics
import Testing
@testable import TabListCore

@Suite
struct SelectionScrollPlanTests {
    private let visible = CGRect(x: 0, y: 100, width: 600, height: 500)

    @Test
    func stationaryVisibleSelectionDoesNotScroll() {
        let selected = CGRect(x: 16, y: 110, width: 568, height: 40)

        XCTAssertEqual(
            SelectionScrollPlanner.alignment(
                selectedFrame: selected,
                visibleRect: visible,
                movement: .stationary
            ),
            .none
        )
    }

    @Test
    func offscreenOrPartiallyClippedSelectionCenters() {
        for selected in [
            CGRect(x: 16, y: 50, width: 568, height: 40),
            CGRect(x: 16, y: 580, width: 568, height: 40),
        ] {
            XCTAssertEqual(
                SelectionScrollPlanner.alignment(
                    selectedFrame: selected,
                    visibleRect: visible,
                    movement: .stationary
                ),
                .centered
            )
        }
    }

    @Test
    func forwardMovementScrollsOnlyPastLowerComfortBoundary() {
        XCTAssertEqual(
            SelectionScrollPlanner.alignment(
                selectedFrame: CGRect(
                    x: 16,
                    y: 430,
                    width: 568,
                    height: 40
                ),
                visibleRect: visible,
                movement: .forward
            ),
            .none
        )
        XCTAssertEqual(
            SelectionScrollPlanner.alignment(
                selectedFrame: CGRect(
                    x: 16,
                    y: 470,
                    width: 568,
                    height: 40
                ),
                visibleRect: visible,
                movement: .forward
            ),
            .centered
        )
    }

    @Test
    func backwardMovementScrollsOnlyPastUpperComfortBoundary() {
        XCTAssertEqual(
            SelectionScrollPlanner.alignment(
                selectedFrame: CGRect(
                    x: 16,
                    y: 230,
                    width: 568,
                    height: 40
                ),
                visibleRect: visible,
                movement: .backward
            ),
            .none
        )
        XCTAssertEqual(
            SelectionScrollPlanner.alignment(
                selectedFrame: CGRect(
                    x: 16,
                    y: 170,
                    width: 568,
                    height: 40
                ),
                visibleRect: visible,
                movement: .backward
            ),
            .centered
        )
    }

    @Test
    func invalidGeometryFailsSafeByRequestingCentering() {
        XCTAssertEqual(
            SelectionScrollPlanner.alignment(
                selectedFrame: CGRect(
                    x: 0,
                    y: 0,
                    width: CGFloat.nan,
                    height: 40
                ),
                visibleRect: visible,
                movement: .forward
            ),
            .centered
        )
    }
}
