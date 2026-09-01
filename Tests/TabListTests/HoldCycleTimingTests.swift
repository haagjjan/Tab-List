import Testing
@testable import TabList

@Suite
struct HoldCycleTimingTests {
    @Test
    func testTheSystemIntervalIsUsedUnchangedAtNormalSpeed() {
        XCTAssertEqual(
            HoldCycleTiming.repeatInterval(systemInterval: 0.08, speed: 1),
            0.08,
            accuracy: 0.000_1
        )
    }

    @Test
    func testAFasterSpeedShortensTheInterval() {
        XCTAssertEqual(
            HoldCycleTiming.repeatInterval(systemInterval: 0.08, speed: 2),
            0.04,
            accuracy: 0.000_1
        )
    }

    @Test
    func testASlowerSpeedLengthensTheInterval() {
        XCTAssertEqual(
            HoldCycleTiming.repeatInterval(systemInterval: 0.08, speed: 0.5),
            0.16,
            accuracy: 0.000_1
        )
    }

    @Test
    func testSpeedIsClampedToTheSupportedRange() {
        XCTAssertEqual(
            HoldCycleTiming.repeatInterval(systemInterval: 0.08, speed: 40),
            HoldCycleTiming.repeatInterval(systemInterval: 0.08, speed: 2),
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            HoldCycleTiming.repeatInterval(systemInterval: 0.08, speed: 0.01),
            HoldCycleTiming.repeatInterval(systemInterval: 0.08, speed: 0.5),
            accuracy: 0.000_1
        )
    }

    @Test
    func testANonFiniteSpeedFallsBackToNormalSpeed() {
        XCTAssertEqual(
            HoldCycleTiming.repeatInterval(
                systemInterval: 0.08,
                speed: .nan
            ),
            0.08,
            accuracy: 0.000_1
        )
    }

    @Test
    func testAnImplausibleSystemIntervalIsFloored() {
        XCTAssertGreaterThanOrEqual(
            HoldCycleTiming.repeatInterval(systemInterval: 0, speed: 2),
            0.02
        )
        XCTAssertGreaterThanOrEqual(
            HoldCycleTiming.repeatInterval(systemInterval: -5, speed: 1),
            0.02
        )
    }
}
