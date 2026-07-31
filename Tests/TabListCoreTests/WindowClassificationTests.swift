import CoreGraphics
import Testing
@testable import TabListCore

@Suite
struct WindowClassificationTests {
    @Test
    func testStandardAndUntitledWindowFactsAreEligible() {
        let input = TestFixtures.classificationInput()

        XCTAssertEqual(WindowClassifier.classify(input), .standard)
    }

    @Test
    func testMissingAccessibilityMetadataFallsBackToWindowServerFacts() {
        let input = TestFixtures.classificationInput(role: nil, subrole: nil)

        XCTAssertEqual(WindowClassifier.classify(input), .standard)
    }

    @Test
    func testAccessoryAndProhibitedProcessesAreExcluded() {
        var accessory = TestFixtures.classificationInput()
        accessory.ownerActivationPolicy = .accessory
        var prohibited = TestFixtures.classificationInput()
        prohibited.ownerActivationPolicy = .prohibited

        XCTAssertEqual(
            WindowClassifier.classify(accessory),
            .excluded(.nonUserApplication(.accessory))
        )
        XCTAssertEqual(
            WindowClassifier.classify(prohibited),
            .excluded(.nonUserApplication(.prohibited))
        )
    }

    @Test
    func testUnknownActivationPolicyFailsOpenForPublicFallbacks() {
        var input = TestFixtures.classificationInput()
        input.ownerActivationPolicy = .unknown

        XCTAssertEqual(WindowClassifier.classify(input), .standard)
    }

    @Test
    func testOwnAndSystemWindowsAreExcluded() {
        var own = TestFixtures.classificationInput()
        own.isOwnedByTabList = true
        XCTAssertEqual(
            WindowClassifier.classify(own),
            .excluded(.ownApplication)
        )

        var dock = TestFixtures.classificationInput(
            titleIndependentOwnerName: "Dock"
        )
        dock.ownerBundleIdentifier = "com.apple.dock"
        XCTAssertEqual(
            WindowClassifier.classify(dock),
            .excluded(.systemSurface)
        )
    }

    @Test
    func testNonzeroLayersAndInvalidGeometryAreExcluded() {
        var layered = TestFixtures.classificationInput()
        layered.layer = 20
        XCTAssertEqual(
            WindowClassifier.classify(layered),
            .excluded(.nonzeroLayer)
        )

        var zeroSized = TestFixtures.classificationInput()
        zeroSized.bounds.size = .zero
        XCTAssertEqual(
            WindowClassifier.classify(zeroSized),
            .excluded(.invalidGeometry)
        )

        var nonFinite = TestFixtures.classificationInput()
        nonFinite.bounds.origin.x = .infinity
        XCTAssertEqual(
            WindowClassifier.classify(nonFinite),
            .excluded(.invalidGeometry)
        )

        var menuBarStrip = TestFixtures.classificationInput()
        menuBarStrip.bounds = CGRect(
            x: 0,
            y: 0,
            width: 1_512,
            height: 33
        )
        XCTAssertEqual(
            WindowClassifier.classify(menuBarStrip),
            .excluded(.invalidGeometry)
        )
    }

    @Test
    func testTransparentAndSpecialSurfacesAreExcluded() {
        var transparent = TestFixtures.classificationInput()
        transparent.alpha = 0
        XCTAssertEqual(
            WindowClassifier.classify(transparent),
            .excluded(.invisibleSurface)
        )

        var desktop = TestFixtures.classificationInput()
        desktop.isDesktopElement = true
        XCTAssertEqual(
            WindowClassifier.classify(desktop),
            .excluded(.desktopElement)
        )

        var notification = TestFixtures.classificationInput()
        notification.isNotification = true
        XCTAssertEqual(
            WindowClassifier.classify(notification),
            .excluded(.notification)
        )

        var inactiveTab = TestFixtures.classificationInput()
        inactiveTab.isTabGroupChild = true
        XCTAssertEqual(
            WindowClassifier.classify(inactiveTab),
            .excluded(.inactiveTab)
        )
    }

    @Test
    func testUtilityRolesAndSubrolesAreExcluded() {
        let menu = TestFixtures.classificationInput(
            role: "AXMenu",
            subrole: nil
        )
        XCTAssertEqual(
            WindowClassifier.classify(menu),
            .excluded(.unsupportedRole("AXMenu"))
        )

        let floating = TestFixtures.classificationInput(
            role: "AXWindow",
            subrole: "AXFloatingWindow"
        )
        XCTAssertEqual(
            WindowClassifier.classify(floating),
            .excluded(.unsupportedSubrole("AXFloatingWindow"))
        )
    }

    @Test
    func testDialogsAndSheetsAreEligible() {
        let dialog = TestFixtures.classificationInput(
            role: "AXDialog",
            subrole: "AXDialog"
        )
        let sheet = TestFixtures.classificationInput(
            role: "AXSheet",
            subrole: "AXSystemDialog"
        )

        XCTAssertEqual(WindowClassifier.classify(dialog), .standard)
        XCTAssertEqual(WindowClassifier.classify(sheet), .standard)
    }
}
