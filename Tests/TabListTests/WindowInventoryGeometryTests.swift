import CoreGraphics
import Testing
@testable import TabList

private func surface(
    _ pid: pid_t,
    layer: Int = 0
) -> ProcessStackingOrder.Surface {
    ProcessStackingOrder.Surface(pid: pid, layer: layer)
}

@Suite
struct ProcessStackingOrderTests {
    @Test
    func testAProcessIsRankedByItsFrontmostSurface() {
        let order = ProcessStackingOrder.order(
            frontToBack: [
                surface(10),
                surface(20),
                surface(10),
                surface(30),
            ]
        )

        XCTAssertEqual(order[10], 0)
        XCTAssertEqual(order[20], 1)
        XCTAssertEqual(order[30], 2)
    }

    @Test
    func testSurfacesAboveTheNormalLayerAreIgnored() {
        let order = ProcessStackingOrder.order(
            frontToBack: [
                surface(10, layer: 25),
                surface(20, layer: 0),
                surface(10, layer: 0),
            ]
        )

        XCTAssertEqual(order[20], 0)
        XCTAssertEqual(order[10], 1)
    }

    @Test
    func testAProcessWithOnlyElevatedSurfacesIsUnranked() {
        let order = ProcessStackingOrder.order(
            frontToBack: [surface(10, layer: 3), surface(11, layer: 1_000)]
        )

        XCTAssertTrue(order.isEmpty)
    }

    @Test
    func testInvalidProcessIdentifiersAreIgnored() {
        let order = ProcessStackingOrder.order(
            frontToBack: [surface(0), surface(-1), surface(42)]
        )

        XCTAssertEqual(order, [42: 0])
    }

    @Test
    func testAnEmptyWindowListProducesNoOrder() {
        XCTAssertTrue(
            ProcessStackingOrder.order(frontToBack: []).isEmpty
        )
    }
}

@Suite
struct DisplayGeometryTests {
    private let geometry = DisplayGeometry(
        displays: [
            (id: 1, bounds: CGRect(x: 0, y: 0, width: 1_512, height: 982)),
            (id: 2, bounds: CGRect(x: 1_512, y: 0, width: 2_560, height: 1_440)),
        ]
    )

    @Test
    func testAWindowIsAssignedToTheDisplayItMostlyCovers() {
        XCTAssertEqual(
            geometry.displayID(
                containing: CGRect(x: 100, y: 100, width: 800, height: 600)
            ),
            1
        )
        XCTAssertEqual(
            geometry.displayID(
                containing: CGRect(x: 2_000, y: 200, width: 800, height: 600)
            ),
            2
        )
    }

    @Test
    func testASpanningWindowPicksTheLargerOverlap() {
        XCTAssertEqual(
            geometry.displayID(
                containing: CGRect(x: 1_400, y: 0, width: 800, height: 600)
            ),
            2
        )
        XCTAssertEqual(
            geometry.displayID(
                containing: CGRect(x: 1_000, y: 0, width: 800, height: 600)
            ),
            1
        )
    }

    @Test
    func testAWindowOutsideEveryDisplayHasNoDisplay() {
        XCTAssertNil(
            geometry.displayID(
                containing: CGRect(x: -4_000, y: -4_000, width: 100, height: 100)
            )
        )
    }

    @Test
    func testAZeroAreaIntersectionDoesNotClaimADisplay() {
        XCTAssertNil(
            geometry.displayID(
                containing: CGRect(x: 0, y: 0, width: 0, height: 0)
            )
        )
    }

    @Test
    func testNoDisplaysMeansNoAnswerRatherThanACrash() {
        XCTAssertNil(
            DisplayGeometry(displays: []).displayID(
                containing: CGRect(x: 0, y: 0, width: 10, height: 10)
            )
        )
    }
}
