import CoreGraphics
import Testing
@testable import TabListCore

@Suite
struct WindowClassificationTests {
    @Test
    func testStandardWindowFactsAreEligible() {
        XCTAssertEqual(
            WindowClassifier.classify(TestFixtures.classificationInput()),
            .standard
        )
    }

    @Test
    func testMissingRoleAndSubroleFailOpen() {
        let input = TestFixtures.classificationInput(role: nil, subrole: nil)

        XCTAssertEqual(WindowClassifier.classify(input), .standard)
    }

    @Test
    func testUnfamiliarSubroleIsAcceptedRatherThanDropped() {
        let input = TestFixtures.classificationInput(
            subrole: "AXSomethingNewInAFutureMacOS"
        )

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
    func testUnknownActivationPolicyFailsOpen() {
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

        var dock = TestFixtures.classificationInput(ownerName: "Dock")
        dock.ownerBundleIdentifier = "com.apple.dock"
        XCTAssertEqual(
            WindowClassifier.classify(dock),
            .excluded(.systemSurface)
        )

        var windowManager = TestFixtures.classificationInput(
            ownerName: "WindowManager"
        )
        windowManager.ownerBundleIdentifier = "com.apple.WindowManager"
        XCTAssertEqual(
            WindowClassifier.classify(windowManager),
            .excluded(.systemSurface)
        )
    }

    @Test
    func testDegenerateGeometryIsExcluded() {
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

        var sliver = TestFixtures.classificationInput()
        sliver.bounds = CGRect(x: 0, y: 0, width: 1_512, height: 8)
        XCTAssertEqual(
            WindowClassifier.classify(sliver),
            .excluded(.invalidGeometry)
        )
    }

    @Test
    func testPalettesAndUtilityRolesAreExcluded() {
        let menu = TestFixtures.classificationInput(
            role: "AXMenu",
            subrole: nil
        )
        XCTAssertEqual(
            WindowClassifier.classify(menu),
            .excluded(.unsupportedRole("AXMenu"))
        )

        let floating = TestFixtures.classificationInput(
            subrole: "AXFloatingWindow"
        )
        XCTAssertEqual(
            WindowClassifier.classify(floating),
            .excluded(.unsupportedSubrole("AXFloatingWindow"))
        )

        let unknown = TestFixtures.classificationInput(subrole: "AXUnknown")
        XCTAssertEqual(
            WindowClassifier.classify(unknown),
            .excluded(.unsupportedSubrole("AXUnknown"))
        )
    }

    @Test
    func testDialogsAreEligible() {
        let dialog = TestFixtures.classificationInput(
            role: "AXDialog",
            subrole: "AXDialog"
        )
        let systemDialog = TestFixtures.classificationInput(
            subrole: "AXSystemDialog"
        )

        XCTAssertEqual(WindowClassifier.classify(dialog), .standard)
        XCTAssertEqual(WindowClassifier.classify(systemDialog), .standard)
    }

    @Test
    func testBrowserWindowWithoutSubroleIsEligible() {
        let firefox = WindowClassificationInput(
            ownerBundleIdentifier: "org.mozilla.firefox",
            ownerName: "Firefox",
            ownerActivationPolicy: .regular,
            bounds: CGRect(x: 0, y: 33, width: 1_512, height: 867),
            accessibilityRole: "AXWindow",
            accessibilitySubrole: nil
        )

        XCTAssertEqual(WindowClassifier.classify(firefox), .standard)
    }
}
