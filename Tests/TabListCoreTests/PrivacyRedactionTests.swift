import XCTest
@testable import TabListCore

final class PrivacyRedactionTests: XCTestCase {
    func testWindowTitlesAreNeverReturnedInDiagnostics() {
        let sensitive = "Secret customer contract"

        let redacted = PrivacyRedaction.windowTitle(sensitive)

        XCTAssertEqual(redacted, "<redacted>")
        XCTAssertFalse(redacted.contains(sensitive))
        XCTAssertEqual(PrivacyRedaction.windowTitle(""), "<empty>")
    }

    func testBundleIdentifierHashIsDeterministicOnlyForSameExportSalt() {
        let identifier = "com.example.SensitiveApp"
        let first = PrivacyRedaction.bundleIdentifier(
            identifier,
            exportSalt: "first export"
        )
        let repeated = PrivacyRedaction.bundleIdentifier(
            identifier,
            exportSalt: "first export"
        )
        let otherExport = PrivacyRedaction.bundleIdentifier(
            identifier,
            exportSalt: "second export"
        )

        XCTAssertEqual(first, repeated)
        XCTAssertNotEqual(first, otherExport)
        XCTAssertFalse(first.contains(identifier))
        XCTAssertEqual(first.count, 24)
    }

    func testMissingBundleIdentifierUsesNonSensitivePlaceholder() {
        XCTAssertEqual(
            PrivacyRedaction.bundleIdentifier(
                nil,
                exportSalt: "export"
            ),
            "<unknown>"
        )
    }
}
