import XCTest
@testable import TabList

final class WindowServerCapabilityReportTests: XCTestCase {
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
