import CoreGraphics
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
}
