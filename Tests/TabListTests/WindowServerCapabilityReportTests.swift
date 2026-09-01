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
                .accessibilityWindowID,
            ],
            operational: [
                .windowSpaceQuery,
                .accessibilityWindowID,
            ],
            frameworkPath: nil
        )

        XCTAssertTrue(report.usesPublicFallbacks)
    }

    @Test
    func testSpaceQueriesAvoidFallbackWarning() {
        let operational: WindowServerCapabilities = [
            .mainConnection,
            .spaceInventory,
            .windowSpaceQuery,
        ]
        let report = WindowServerCapabilityReport(
            detected: operational,
            operational: operational,
            frameworkPath: nil
        )

        XCTAssertFalse(report.usesPublicFallbacks)
    }

    @Test
    func testMissingWindowIdentifierMappingIsNotAFallbackWarning() {
        let report = WindowServerCapabilityReport(
            detected: [
                .mainConnection,
                .spaceInventory,
                .windowSpaceQuery,
                .accessibilityWindowID,
            ],
            operational: [
                .mainConnection,
                .spaceInventory,
                .windowSpaceQuery,
            ],
            frameworkPath: nil
        )

        XCTAssertFalse(report.usesPublicFallbacks)
    }
}
