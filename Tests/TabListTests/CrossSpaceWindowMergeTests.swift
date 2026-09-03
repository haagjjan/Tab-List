import CoreGraphics
import Foundation
import TabListCore
import Testing
@testable import TabList

/// Accessibility returns nothing at all for an application whose windows all
/// live on another Space, so the WindowServer supplies those windows instead.
/// These cover the merge between the two sources.
private enum Merge {
    static let ownPID: pid_t = 999

    static func windowServerWindow(
        pid: pid_t = 500,
        windowID: CGWindowID = 42,
        bounds: CGRect = CGRect(x: 0, y: 33, width: 1_512, height: 867),
        title: String = "Release notes — Mozilla",
        spaceIDs: [UInt64] = [1_397]
    ) -> WindowServerWindow {
        WindowServerWindow(
            windowID: windowID,
            pid: pid,
            bounds: bounds,
            title: title,
            spaceIDs: spaceIDs
        )
    }

    static func accessibilityWindow(
        pid: pid_t = 500,
        windowID: CGWindowID = 42,
        identitySource: WindowIdentitySource = .windowServerID
    ) -> AccessibilityWindowDescriptor {
        AccessibilityWindowDescriptor(
            key: WindowKey(pid: pid, windowID: windowID),
            role: "AXWindow",
            subrole: "AXStandardWindow",
            title: "Release notes — Mozilla",
            bounds: CGRect(x: 0, y: 33, width: 1_512, height: 867),
            isMinimized: false,
            isFullscreen: false,
            isClosable: true,
            isMain: true,
            identitySource: identitySource
        )
    }

    static func application(
        pid: pid_t = 500
    ) -> RunningApplicationDescriptor {
        RunningApplicationDescriptor(
            pid: pid,
            bundleIdentifier: "org.mozilla.firefox",
            name: "Firefox",
            bundleURL: URL(fileURLWithPath: "/Applications/Firefox.app"),
            isHidden: false,
            activationPolicy: .regular
        )
    }
}

@Suite
struct CrossSpaceWindowMergeTests {
    @Test
    func testAWindowOnAnotherDesktopIsAddedWhenAccessibilitySeesNothing() {
        let merged = WindowInventory.windowsOnlyTheWindowServerSees(
            [Merge.windowServerWindow()],
            alreadyReportedBy: []
        )

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.windowID, 42)
    }

    @Test
    func testAccessibilityWinsForAWindowBothSourcesReport() {
        let merged = WindowInventory.windowsOnlyTheWindowServerSees(
            [
                Merge.windowServerWindow(windowID: 42),
                Merge.windowServerWindow(windowID: 43),
            ],
            alreadyReportedBy: [Merge.accessibilityWindow(windowID: 42)]
        )

        XCTAssertEqual(merged.map(\.windowID), [43])
    }

    /// Without WindowServer identifiers the two sources share no common key, so
    /// merging would duplicate every window the application owns.
    @Test
    func testOrdinalIdentitiesSuppressTheMergeEntirely() {
        let merged = WindowInventory.windowsOnlyTheWindowServerSees(
            [Merge.windowServerWindow(windowID: 43)],
            alreadyReportedBy: [
                Merge.accessibilityWindow(
                    windowID: 1,
                    identitySource: .accessibilityOrdinal
                )
            ]
        )

        XCTAssertTrue(merged.isEmpty)
    }

    @Test
    func testAnApplicationTheWindowServerKnowsNothingAboutAddsNothing() {
        let merged = WindowInventory.windowsOnlyTheWindowServerSees(
            [],
            alreadyReportedBy: [Merge.accessibilityWindow()]
        )

        XCTAssertTrue(merged.isEmpty)
    }

    @Test
    func testAWindowServerWindowBecomesAnOrdinaryRow() throws {
        let window = Merge.windowServerWindow()
        let record = try XCTUnwrap(
            WindowRecordAssembly.record(
                descriptor: WindowInventory.descriptor(for: window),
                application: Merge.application(),
                ownPID: Merge.ownPID,
                spaceIDs: window.spaceIDs,
                displayID: 7
            ).record
        )

        XCTAssertEqual(record.id, WindowKey(pid: 500, windowID: 42))
        XCTAssertEqual(record.windowTitle, "Release notes — Mozilla")
        XCTAssertEqual(record.spaceIDs, [1_397])
        XCTAssertEqual(record.applicationName, "Firefox")
        XCTAssertEqual(record.identitySource, .windowServerID)
    }

    /// The classifier accepts a missing role, which is what lets these windows
    /// through at all. Geometry still has to disqualify leftover chrome.
    @Test
    func testChromeSizedWindowServerWindowsAreStillRejected() {
        let outcome = WindowRecordAssembly.record(
            descriptor: WindowInventory.descriptor(
                for: Merge.windowServerWindow(
                    bounds: CGRect(x: 0, y: 0, width: 1_512, height: 16)
                )
            ),
            application: Merge.application(),
            ownPID: Merge.ownPID,
            spaceIDs: [1_397],
            displayID: 7
        )

        XCTAssertEqual(
            outcome.exclusionReason?.diagnosticCode,
            "invalid-geometry"
        )
    }
}
