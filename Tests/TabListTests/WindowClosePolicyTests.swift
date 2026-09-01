import Foundation
import TabListCore
import Testing
@testable import TabList

@Suite
struct WindowClosePolicyTests {
    private let tabListBundleIdentifier = "com.haagjjan.TabList"

    private func disposition(
        bundleIdentifier: String? = "com.example.Editor",
        pid: pid_t = 4_242,
        windowCount: Int
    ) -> WindowCloseDisposition {
        WindowClosePolicy.disposition(
            for: AppTestFixtures.window(
                1,
                pid: pid,
                bundleIdentifier: bundleIdentifier
            ),
            canonicalWindowCount: windowCount,
            tabListBundleIdentifier: tabListBundleIdentifier
        )
    }

    @Test
    func testClosingOneOfSeveralWindowsOnlyClosesThatWindow() {
        XCTAssertEqual(disposition(windowCount: 2), .closeWindow)
        XCTAssertEqual(disposition(windowCount: 9), .closeWindow)
    }

    @Test
    func testClosingTheLastWindowQuitsAnOrdinaryApplication() {
        XCTAssertEqual(disposition(windowCount: 1), .quitApplication)
    }

    @Test
    func testAnUnknownWindowCountNeverQuitsAnApplication() {
        XCTAssertEqual(disposition(windowCount: 0), .closeWindow)
    }

    @Test
    func testProtectedSystemApplicationsAreNeverQuit() {
        for identifier in [
            "com.apple.finder",
            "com.apple.dock",
            "com.apple.systemuiserver",
            "com.apple.controlcenter",
            "com.apple.loginwindow",
            "com.apple.WindowManager",
        ] {
            XCTAssertEqual(
                disposition(bundleIdentifier: identifier, windowCount: 1),
                .closeWindow
            )
            XCTAssertEqual(
                disposition(
                    bundleIdentifier: identifier.uppercased(),
                    windowCount: 1
                ),
                .closeWindow
            )
        }
    }

    @Test
    func testTabListNeverQuitsItself() {
        XCTAssertEqual(
            disposition(
                bundleIdentifier: tabListBundleIdentifier,
                windowCount: 1
            ),
            .closeWindow
        )
        XCTAssertEqual(
            disposition(
                bundleIdentifier: tabListBundleIdentifier.uppercased(),
                windowCount: 1
            ),
            .closeWindow
        )
        XCTAssertEqual(
            disposition(
                pid: ProcessInfo.processInfo.processIdentifier,
                windowCount: 1
            ),
            .closeWindow
        )
    }

    @Test
    func testAnApplicationWithoutABundleIdentifierIsStillQuitOnItsLastWindow() {
        XCTAssertEqual(
            disposition(bundleIdentifier: nil, windowCount: 1),
            .quitApplication
        )
    }
}
