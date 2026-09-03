import CoreGraphics
import Foundation
import TabListCore
import Testing
@testable import TabList

private enum Assembly {
    static let ownPID: pid_t = 999

    static func application(
        pid: pid_t = 500,
        bundleIdentifier: String? = "org.mozilla.firefox",
        name: String = "Firefox",
        isHidden: Bool = false,
        policy: WindowOwnerActivationPolicy = .regular
    ) -> RunningApplicationDescriptor {
        RunningApplicationDescriptor(
            pid: pid,
            bundleIdentifier: bundleIdentifier,
            name: name,
            bundleURL: URL(fileURLWithPath: "/Applications/\(name).app"),
            isHidden: isHidden,
            activationPolicy: policy
        )
    }

    static func descriptor(
        pid: pid_t = 500,
        windowID: CGWindowID = 1,
        role: String? = "AXWindow",
        subrole: String? = "AXStandardWindow",
        title: String = "Release notes — Mozilla",
        bounds: CGRect = CGRect(x: 0, y: 33, width: 1_512, height: 867),
        isMinimized: Bool = false,
        isFullscreen: Bool = false,
        isClosable: Bool = true,
        identitySource: WindowIdentitySource = .accessibilityOrdinal
    ) -> AccessibilityWindowDescriptor {
        AccessibilityWindowDescriptor(
            key: WindowKey(pid: pid, windowID: windowID),
            role: role,
            subrole: subrole,
            title: title,
            bounds: bounds,
            isMinimized: isMinimized,
            isFullscreen: isFullscreen,
            isClosable: isClosable,
            isMain: false,
            identitySource: identitySource
        )
    }

    static func assemble(
        descriptor: AccessibilityWindowDescriptor = descriptor(),
        application: RunningApplicationDescriptor = application(),
        spaceIDs: [UInt64] = [],
        displayID: CGDirectDisplayID? = 7
    ) -> WindowRecordAssembly.Outcome {
        WindowRecordAssembly.record(
            descriptor: descriptor,
            application: application,
            ownPID: ownPID,
            spaceIDs: spaceIDs,
            displayID: displayID
        )
    }
}

@Suite
struct WindowRecordAssemblyTests {
    /// Assembly only. This deliberately does not claim cross-desktop coverage:
    /// it feeds a synthetic descriptor and never touches macOS Accessibility,
    /// which is exactly why it stayed green while windows on other desktops
    /// were invisible. See `CrossSpaceWindowMergeTests` for the merge itself.
    @Test
    func testAWindowWithoutSpaceInformationStillBecomesARow() throws {
        let record = try XCTUnwrap(Assembly.assemble().record)

        XCTAssertEqual(record.applicationName, "Firefox")
        XCTAssertEqual(record.windowTitle, "Release notes — Mozilla")
        XCTAssertTrue(record.spaceIDs.isEmpty)
        XCTAssertEqual(record.displayID, 7)
    }

    @Test
    func testEveryWindowStateIsCarriedIntoTheRecord() throws {
        let record = try XCTUnwrap(
            Assembly.assemble(
                descriptor: Assembly.descriptor(
                    isMinimized: true,
                    isFullscreen: true,
                    isClosable: false,
                    identitySource: .windowServerID
                ),
                application: Assembly.application(isHidden: true),
                spaceIDs: [4, 9]
            ).record
        )

        XCTAssertTrue(record.isMinimized)
        XCTAssertTrue(record.isHidden)
        XCTAssertTrue(record.isFullscreen)
        XCTAssertFalse(record.isClosable)
        XCTAssertEqual(record.spaceIDs, [4, 9])
        XCTAssertEqual(record.identitySource, .windowServerID)
    }

    @Test
    func testTabListsOwnWindowsAreExcluded() {
        let outcome = Assembly.assemble(
            descriptor: Assembly.descriptor(pid: Assembly.ownPID),
            application: Assembly.application(
                pid: Assembly.ownPID,
                bundleIdentifier: "com.haagjjan.TabList",
                name: "Tab-List"
            )
        )

        XCTAssertEqual(outcome.exclusionReason, .ownApplication)
    }

    @Test
    func testMenuBarAgentsAreExcluded() {
        let outcome = Assembly.assemble(
            application: Assembly.application(
                bundleIdentifier: "com.example.Agent",
                name: "Agent",
                policy: .accessory
            )
        )

        XCTAssertEqual(
            outcome.exclusionReason,
            .nonUserApplication(.accessory)
        )
    }

    @Test
    func testFloatingPalettesAreExcluded() {
        let outcome = Assembly.assemble(
            descriptor: Assembly.descriptor(subrole: "AXFloatingWindow")
        )

        XCTAssertEqual(
            outcome.exclusionReason,
            .unsupportedSubrole("AXFloatingWindow")
        )
    }

    @Test
    func testDegenerateFramesAreExcluded() {
        let outcome = Assembly.assemble(
            descriptor: Assembly.descriptor(bounds: .null)
        )

        XCTAssertEqual(outcome.exclusionReason, .invalidGeometry)
    }

    @Test
    func testABrowserWindowWithoutASubroleIsStillIncluded() {
        XCTAssertNil(
            Assembly.assemble(
                descriptor: Assembly.descriptor(subrole: nil)
            ).exclusionReason
        )
    }

    @Test
    func testAnUntitledWindowKeepsAnEmptyTitleForThePresentationLayer() throws {
        let record = try XCTUnwrap(
            Assembly.assemble(
                descriptor: Assembly.descriptor(title: "")
            ).record
        )

        XCTAssertTrue(record.windowTitle.isEmpty)
    }

    @Test
    func testTheDescriptorKeyBecomesTheRecordIdentity() throws {
        let key = WindowKey(pid: 500, windowID: 0x8000_0003)
        let record = try XCTUnwrap(
            Assembly.assemble(
                descriptor: Assembly.descriptor(windowID: key.windowID)
            ).record
        )

        XCTAssertEqual(record.id, key)
    }
}
