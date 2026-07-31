import CoreGraphics
import TabListCore
import Testing
@testable import TabList

@Suite
struct AccessibilityGeometryMatcherTests {
    @Test
    func testIdenticalTitleAndGeometryFailsClosedAsAmbiguous() {
        let descriptor = AccessibilityWindowMatchDescriptor(
            title: "Document",
            bounds: CGRect(x: 20, y: 40, width: 800, height: 600)
        )

        XCTAssertNil(
            AccessibilityGeometryMatcher.uniqueMatchIndex(
                target: descriptor,
                candidates: [descriptor, descriptor]
            )
        )
    }

    @Test
    func testTitleDisambiguatesWindowsWithTheSameGeometry() {
        let bounds = CGRect(x: 20, y: 40, width: 800, height: 600)
        let target = AccessibilityWindowMatchDescriptor(
            title: "Project A",
            bounds: bounds
        )

        XCTAssertEqual(
            AccessibilityGeometryMatcher.uniqueMatchIndex(
                target: target,
                candidates: [
                    .init(title: "Project B", bounds: bounds),
                    .init(title: "Project A", bounds: bounds),
                ]
            ),
            1
        )
    }

    @Test
    func testMissingGeometryCannotProduceAnActionableMatch() {
        XCTAssertNil(
            AccessibilityGeometryMatcher.uniqueMatchIndex(
                target: .init(title: "Document", bounds: nil),
                candidates: [
                    .init(
                        title: "Document",
                        bounds: CGRect(
                            x: 20,
                            y: 40,
                            width: 800,
                            height: 600
                        )
                    ),
                ]
            )
        )
    }

    @Test
    func testBlankWindowServerTitlesWithIdenticalGeometryFailClosed() {
        let bounds = CGRect(x: 20, y: 40, width: 800, height: 600)

        XCTAssertEqual(
            AccessibilityGeometryMatcher.assignments(
                candidates: [
                    .init(title: "", bounds: bounds),
                    .init(title: "", bounds: bounds),
                ],
                windows: [
                    .init(
                        title: "Active tab",
                        bounds: bounds,
                        isPreferred: true
                    ),
                    .init(title: "Inactive tab", bounds: bounds),
                ]
            ),
            [:]
        )
    }

    @Test
    func testAmbiguousGroupWithDifferentCountsStillFailsClosed() {
        let bounds = CGRect(x: 20, y: 40, width: 800, height: 600)

        XCTAssertEqual(
            AccessibilityGeometryMatcher.assignments(
                candidates: [
                    .init(title: "", bounds: bounds),
                    .init(title: "", bounds: bounds),
                    .init(title: "", bounds: bounds),
                ],
                windows: [
                    .init(title: "Only AX window", bounds: bounds),
                ]
            ),
            [:]
        )
    }

    @Test
    func testSingleAXNativeTabContainerMapsToFrontmostCandidate() {
        let bounds = CGRect(x: 20, y: 40, width: 800, height: 600)

        XCTAssertEqual(
            AccessibilityGeometryMatcher.assignments(
                candidates: [
                    .init(title: "", bounds: bounds),
                    .init(title: "", bounds: bounds),
                ],
                windows: [
                    .init(
                        title: "Selected tab",
                        bounds: bounds,
                        nativeTabCount: 2
                    ),
                ]
            ),
            [0: 0]
        )
    }

    @Test
    func testCanonicalResolverDropsBackingSurfacesForInspectedProcess() {
        let real = candidate(pid: 100, windowID: 1)
        let backing = candidate(pid: 100, windowID: 2)
        let otherProcess = candidate(pid: 200, windowID: 3)
        let inventory = AccessibilityWindowInventory(
            metadata: [real.key: metadata()],
            identitySources: [real.key: .uniqueGeometry],
            inspectedPIDs: [100],
            unresolvedStandardWindowCounts: [100: 1],
            isTrusted: true
        )

        XCTAssertEqual(
            WindowIdentityResolver.canonicalCandidates(
                [real, backing, otherProcess],
                accessibilityInventory: inventory
            ),
            [real, otherProcess]
        )
    }

    @Test
    func testCanonicalResolverPreservesPublicInventoryWhenAXUnavailable() {
        let first = candidate(pid: 100, windowID: 1)
        let second = candidate(pid: 100, windowID: 2)
        let inventory = AccessibilityWindowInventory(
            metadata: [:],
            identitySources: [:],
            inspectedPIDs: [100],
            unresolvedStandardWindowCounts: [:],
            isTrusted: false
        )

        XCTAssertEqual(
            WindowIdentityResolver.canonicalCandidates(
                [first, second],
                accessibilityInventory: inventory
            ),
            [first, second]
        )
    }

    @Test
    func testUnvalidatedOffSpaceWindowIsNotActionable() {
        XCTAssertFalse(
            WindowIdentityResolver.isActionable(
                hasAccessibilityWindow: true,
                isOnScreen: false,
                isMinimized: false,
                isHiddenApplication: false,
                hasExactActivation: false
            )
        )
        XCTAssertTrue(
            WindowIdentityResolver.isActionable(
                hasAccessibilityWindow: true,
                isOnScreen: false,
                isMinimized: false,
                isHiddenApplication: false,
                hasExactActivation: true
            )
        )
    }

    @Test
    func testPubliclyRestorableWindowStatesRemainActionable() {
        XCTAssertTrue(
            WindowIdentityResolver.isActionable(
                hasAccessibilityWindow: true,
                isOnScreen: false,
                isMinimized: true,
                isHiddenApplication: false,
                hasExactActivation: false
            )
        )
        XCTAssertTrue(
            WindowIdentityResolver.isActionable(
                hasAccessibilityWindow: true,
                isOnScreen: false,
                isMinimized: false,
                isHiddenApplication: true,
                hasExactActivation: false
            )
        )
    }

    private func candidate(
        pid: pid_t,
        windowID: CGWindowID
    ) -> PublicWindowCandidate {
        PublicWindowCandidate(
            key: WindowKey(pid: pid, windowID: windowID),
            ownerName: "Fixture",
            title: "",
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            layer: 0,
            alpha: 1,
            isOnScreen: true
        )
    }

    private func metadata() -> AccessibilityWindowMetadata {
        AccessibilityWindowMetadata(
            role: "AXWindow",
            subrole: "AXStandardWindow",
            title: "Fixture",
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
            isMinimized: false,
            isFullscreen: false,
            isStandardWindow: true,
            isClosable: true
        )
    }
}
