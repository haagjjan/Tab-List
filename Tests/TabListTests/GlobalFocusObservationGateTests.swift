import Testing
@testable import TabList

@Suite
struct GlobalFocusObservationGateTests {
    @Test
    func testAcceptsOnlyTheFrontmostApplicationProcess() {
        XCTAssertTrue(
            GlobalFocusObservationGate.accepts(
                observedPID: 100,
                frontmostPID: 100
            )
        )
        XCTAssertFalse(
            GlobalFocusObservationGate.accepts(
                observedPID: 100,
                frontmostPID: 200
            )
        )
        XCTAssertFalse(
            GlobalFocusObservationGate.accepts(
                observedPID: 100,
                frontmostPID: nil
            )
        )
    }

    @Test
    func testActivationConfirmationRequiresGlobalAndExactWindowFocus() {
        let target = AppTestFixtures.key(1, pid: 100)

        XCTAssertTrue(
            GlobalFocusObservationGate.confirms(
                target: target,
                frontmostPID: 100,
                accessibilityFocusedKey: target
            )
        )
        XCTAssertFalse(
            GlobalFocusObservationGate.confirms(
                target: target,
                frontmostPID: 200,
                accessibilityFocusedKey: target
            )
        )
        XCTAssertFalse(
            GlobalFocusObservationGate.confirms(
                target: target,
                frontmostPID: 100,
                accessibilityFocusedKey: AppTestFixtures.key(
                    2,
                    pid: 100
                )
            )
        )
    }
}
