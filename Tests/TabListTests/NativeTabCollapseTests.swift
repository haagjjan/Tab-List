import CoreGraphics
import Testing
@testable import TabList

private func frame(
    _ x: Int,
    _ y: Int,
    _ width: Int = 900,
    _ height: Int = 600
) -> NativeTabCollapse.Frame {
    NativeTabCollapse.Frame(
        CGRect(x: x, y: y, width: width, height: height)
    )
}

private func candidate(
    _ frameValue: NativeTabCollapse.Frame,
    isMain: Bool = false
) -> NativeTabCollapse.Candidate {
    NativeTabCollapse.Candidate(frame: frameValue, isMain: isMain)
}

@Suite
struct NativeTabCollapseTests {
    @Test
    func testASingleWindowIsAlwaysRetained() {
        let retained = NativeTabCollapse.retainedIndices(
            of: [candidate(frame(0, 0))],
            tabCount: { _ in 0 }
        )

        XCTAssertEqual(retained, [0])
    }

    @Test
    func testWindowsWithDistinctFramesAreNeverCollapsed() {
        let candidates = [
            candidate(frame(0, 0)),
            candidate(frame(40, 40)),
            candidate(frame(80, 80)),
        ]

        XCTAssertEqual(
            NativeTabCollapse.retainedIndices(
                of: candidates,
                tabCount: { _ in 3 }
            ),
            [0, 1, 2]
        )
    }

    @Test
    func testTabCountIsNotReadWhenNoFramesMatch() {
        nonisolated(unsafe) var reads = 0
        _ = NativeTabCollapse.retainedIndices(
            of: [candidate(frame(0, 0)), candidate(frame(10, 10))],
            tabCount: { _ in
                reads += 1
                return 2
            }
        )

        XCTAssertEqual(reads, 0)
    }

    @Test
    func testAMatchingTabGroupCollapsesToItsMainMember() {
        let shared = frame(0, 33)
        let candidates = [
            candidate(shared),
            candidate(shared, isMain: true),
            candidate(shared),
        ]

        XCTAssertEqual(
            NativeTabCollapse.retainedIndices(
                of: candidates,
                tabCount: { _ in 3 }
            ),
            [1]
        )
    }

    @Test
    func testAMatchingTabGroupWithoutAMainMemberKeepsTheFirst() {
        let shared = frame(0, 33)

        XCTAssertEqual(
            NativeTabCollapse.retainedIndices(
                of: [candidate(shared), candidate(shared)],
                tabCount: { _ in 2 }
            ),
            [0]
        )
    }

    @Test
    func testSameFrameWindowsWithoutTabEvidenceAreAllKept() {
        let shared = frame(120, 120)

        XCTAssertEqual(
            NativeTabCollapse.retainedIndices(
                of: [candidate(shared), candidate(shared)],
                tabCount: { _ in 0 }
            ),
            [0, 1]
        )
    }

    @Test
    func testAMismatchedTabCountIsNotTreatedAsATabGroup() {
        let shared = frame(0, 0)

        XCTAssertEqual(
            NativeTabCollapse.retainedIndices(
                of: [candidate(shared), candidate(shared)],
                tabCount: { _ in 5 }
            ),
            [0, 1]
        )
    }

    @Test
    func testOnlyTheMatchingGroupCollapsesAndOrderIsPreserved() {
        let tabbed = frame(0, 33)
        let solo = frame(400, 200)
        let candidates = [
            candidate(solo),
            candidate(tabbed),
            candidate(tabbed, isMain: true),
            candidate(frame(700, 400)),
        ]

        XCTAssertEqual(
            NativeTabCollapse.retainedIndices(
                of: candidates,
                tabCount: { index in index == 1 || index == 2 ? 2 : 0 }
            ),
            [0, 2, 3]
        )
    }

    @Test
    func testSubPixelFramesAreTreatedAsTheSameFrame() {
        let candidates = [
            candidate(
                NativeTabCollapse.Frame(
                    CGRect(x: 0.4, y: 33.2, width: 900.1, height: 600.4)
                ),
                isMain: true
            ),
            candidate(
                NativeTabCollapse.Frame(
                    CGRect(x: 0.1, y: 32.9, width: 899.7, height: 600.0)
                )
            ),
        ]

        XCTAssertEqual(
            NativeTabCollapse.retainedIndices(
                of: candidates,
                tabCount: { _ in 2 }
            ),
            [0]
        )
    }
}
