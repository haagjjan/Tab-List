import Foundation
import Testing
@testable import TabListCore

@Suite
struct AppIconFingerprintTests {
    @Test
    func testIdenticalBundleFactsProduceStableFingerprint() {
        let first = fingerprint()
        let second = fingerprint()

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 64)
    }

    @Test
    func testVersionAndModificationChangesInvalidateFingerprint() {
        XCTAssertNotEqual(
            fingerprint(version: "1"),
            fingerprint(version: "2")
        )
        XCTAssertNotEqual(
            fingerprint(modificationTime: 1),
            fingerprint(modificationTime: 2)
        )
    }

    @Test
    func testCanonicalPathAndTargetSizeArePartOfIdentity() {
        XCTAssertNotEqual(
            fingerprint(path: "/Applications/One.app"),
            fingerprint(path: "/Applications/Two.app")
        )
        XCTAssertNotEqual(
            fingerprint(targetSize: 64),
            fingerprint(targetSize: 128)
        )
    }

    private func fingerprint(
        path: String = "/Applications/Example.app",
        version: String = "1",
        modificationTime: TimeInterval = 10,
        targetSize: Double = 128
    ) -> String {
        AppIconFingerprint.make(
            bundleIdentifier: "com.example.App",
            canonicalBundlePath: path,
            bundleVersion: version,
            modificationTime: modificationTime,
            targetSize: targetSize
        )
    }
}
