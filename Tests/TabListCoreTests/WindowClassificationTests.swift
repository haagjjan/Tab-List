import CoreGraphics
import XCTest
@testable import TabListCore

final class WindowClassificationTests: XCTestCase {
    func testStandardAndUntitledWindowFactsAreEligible() {
        let input = TestFixtures.classificationInput()

        XCTAssertEqual(WindowClassifier.classify(input), .standard)
    }

    func testMissingAccessibilityMetadataFallsBackToWindowServerFacts() {
        let input = TestFixtures.classificationInput(role: nil, subrole: nil)

        XCTAssertEqual(WindowClassifier.classify(input), .standard)
    }

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
    }

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
