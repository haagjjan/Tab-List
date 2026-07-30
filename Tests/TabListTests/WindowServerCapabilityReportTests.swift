import Testing
@testable import TabList

@Suite
struct WindowServerCapabilityReportTests {
    @Test
    func testMissingSpaceInventorySurfacesFallbackWarning() {
        let report = WindowServerCapabilityReport(
            detected: [
                .spaceInventory,
                .windowSpaceQuery,
                .exactActivation,
                .accessibilityWindowID,
            ],
            operational: [
                .windowSpaceQuery,
                .exactActivation,
                .accessibilityWindowID,
            ],
            frameworkPath: nil
        )

        XCTAssertTrue(report.usesPublicFallbacks)
    }

    @Test
    func testAllRequiredWindowCapabilitiesAvoidFallbackWarning() {
        let required: WindowServerCapabilities = [
            .spaceInventory,
            .windowSpaceQuery,
            .exactActivation,
            .accessibilityWindowID,
        ]
        let report = WindowServerCapabilityReport(
            detected: required,
            operational: required,
            frameworkPath: nil
        )

        XCTAssertFalse(report.usesPublicFallbacks)
    }
}
