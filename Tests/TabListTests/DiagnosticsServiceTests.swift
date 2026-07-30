import Foundation
import TabListCore
import XCTest
@testable import TabList

final class DiagnosticsServiceTests: XCTestCase {
    func testExportOmitsTitlesAndUsesPerExportBundlePseudonyms() throws {
        let sensitiveTitle = "Acquisition — confidential"
        let snapshot = WindowSnapshot(
            generation: 7,
            windows: [
                AppTestFixtures.window(
                    42,
                    bundleIdentifier: "com.example.SensitiveApp",
                    title: sensitiveTitle
                ),
            ],
            visibleSpaceIDs: [1]
        )
        let permissions = SystemPermissionSnapshot(
            accessibility: .authorized,
            screenRecording: .denied
        )
        let capabilities = WindowServerCapabilityReport(
            detected: [],
            operational: [],
            frameworkPath: nil
        )

        let first = DiagnosticsService.makeReport(
            permissions: permissions,
            capabilities: capabilities,
            snapshot: snapshot
        )
        let second = DiagnosticsService.makeReport(
            permissions: permissions,
            capabilities: capabilities,
            snapshot: snapshot
        )
        let encoded = try DiagnosticsService.encoded(first)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertFalse(json.contains(sensitiveTitle))
        XCTAssertFalse(json.contains("com.example.SensitiveApp"))
        XCTAssertTrue(first.windows[0].hasTitle)
        XCTAssertNotEqual(
            first.windows[0].bundleIdentifierHash,
            second.windows[0].bundleIdentifierHash
        )
    }
}
