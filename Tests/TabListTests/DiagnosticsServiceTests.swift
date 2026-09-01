import Foundation
import TabListCore
import Testing
@testable import TabList

@Suite
struct DiagnosticsServiceTests {
    @Test
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
            accessibility: .authorized
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
        XCTAssertEqual(
            first.windows[0].identitySource,
            .accessibilityOrdinal
        )
        XCTAssertNotEqual(
            first.windows[0].bundleIdentifierHash,
            second.windows[0].bundleIdentifierHash
        )
    }
}

@Suite
struct DiagnosticsReportContentTests {
    private func report(
        windows: [WindowRecord],
        capabilities: WindowServerCapabilities = [.mainConnection]
    ) -> DiagnosticsReport {
        DiagnosticsService.makeReport(
            permissions: SystemPermissionSnapshot(accessibility: .authorized),
            capabilities: WindowServerCapabilityReport(
                detected: [.mainConnection, .accessibilityWindowID],
                operational: capabilities,
                frameworkPath: "/System/Library/PrivateFrameworks/Example"
            ),
            snapshot: WindowSnapshot(
                generation: 12,
                windows: windows,
                visibleSpaceIDs: [3, 4]
            )
        )
    }

    @Test
    func testTheReportCarriesRegistryAndCapabilityContext() {
        let value = report(windows: [AppTestFixtures.window(1)])

        XCTAssertEqual(value.registryGeneration, 12)
        XCTAssertEqual(value.visibleSpaceCount, 2)
        XCTAssertEqual(value.windows.count, 1)
        XCTAssertEqual(
            value.windowServerCapabilities.operational,
            [.mainConnection]
        )
    }

    @Test
    func testEveryWindowStateIsPreservedForTriage() throws {
        let value = report(
            windows: [
                AppTestFixtures.window(
                    5,
                    title: "",
                    isMinimized: true,
                    isHidden: true,
                    isFullscreen: true,
                    isClosable: false
                ),
            ]
        )
        let window = try XCTUnwrap(value.windows.first)

        XCTAssertFalse(window.hasTitle)
        XCTAssertTrue(window.isMinimized)
        XCTAssertTrue(window.isHidden)
        XCTAssertTrue(window.isFullscreen)
        XCTAssertFalse(window.isClosable)
    }

    @Test
    func testAnEmptyRegistryStillProducesAValidExport() throws {
        let encoded = try DiagnosticsService.encoded(report(windows: []))

        XCTAssertTrue(encoded.count > 0)
        XCTAssertTrue(report(windows: []).windows.isEmpty)
    }

    @Test
    func testTheExportIsDeterministicallyOrdered() throws {
        let value = report(windows: [AppTestFixtures.window(1)])

        let first = try DiagnosticsService.encoded(value)
        let second = try DiagnosticsService.encoded(value)

        XCTAssertEqual(first, second)
    }
}
