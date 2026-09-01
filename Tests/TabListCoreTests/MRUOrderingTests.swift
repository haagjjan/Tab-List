import Testing
@testable import TabListCore

@Suite
struct MRUOrderingTests {
    @Test
    func testOrderingUsesDescendingFocusSequenceAndStableTies() {
        let firstTie = TestFixtures.window(1, focusSequence: 5)
        let newest = TestFixtures.window(2, focusSequence: 9)
        let secondTie = TestFixtures.window(3, focusSequence: 5)

        XCTAssertEqual(
            MRUOrdering.sorted([firstTie, newest, secondTie]),
            [newest, firstTie, secondTie]
        )
    }

    @Test
    func testStartupSeedPreservesFrontToBackOrder() {
        let front = TestFixtures.key(1)
        let middle = TestFixtures.key(2)
        let back = TestFixtures.key(3)
        var tracker = WindowMRUTracker()

        tracker.seed(frontToBack: [front, middle, back])

        XCTAssertGreaterThan(
            tracker.sequence(for: front),
            tracker.sequence(for: middle)
        )
        XCTAssertGreaterThan(
            tracker.sequence(for: middle),
            tracker.sequence(for: back)
        )
    }

    @Test
    func testStartupSeedPreservesDiscoveredStackingOrder() {
        let front = TestFixtures.key(1)
        let middle = TestFixtures.key(2)
        let back = TestFixtures.key(3)
        var tracker = WindowMRUTracker()

        tracker.seed(frontToBack: [front, middle, back])

        XCTAssertGreaterThan(
            tracker.sequence(for: front),
            tracker.sequence(for: middle)
        )
        XCTAssertGreaterThan(
            tracker.sequence(for: middle),
            tracker.sequence(for: back)
        )
    }

    @Test
    func testOnlyConfirmedFocusedWindowAdvances() {
        let first = TestFixtures.key(1, pid: 100)
        let sibling = TestFixtures.key(2, pid: 100)
        var tracker = WindowMRUTracker()
        tracker.seed(frontToBack: [first, sibling])
        let siblingSequence = tracker.sequence(for: sibling)

        tracker.recordFocus(first)
        tracker.recordFocus(first)

        XCTAssertEqual(tracker.sequence(for: sibling), siblingSequence)
        XCTAssertGreaterThan(
            tracker.sequence(for: first),
            tracker.sequence(for: sibling)
        )
    }

    @Test
    func testReconciliationDoesNotReverseExistingSiblingOrder() {
        let first = TestFixtures.key(1)
        let second = TestFixtures.key(2)
        let newlyDiscovered = TestFixtures.key(3)
        var tracker = WindowMRUTracker()
        tracker.seed(frontToBack: [first, second])

        tracker.seed(frontToBack: [second, first, newlyDiscovered])

        XCTAssertGreaterThan(
            tracker.sequence(for: first),
            tracker.sequence(for: second)
        )
        XCTAssertEqual(tracker.sequence(for: newlyDiscovered), 0)
    }

    @Test
    func testApplyingSequencesAndRetention() {
        let first = TestFixtures.window(1)
        let second = TestFixtures.window(2)
        var tracker = WindowMRUTracker()
        tracker.recordFocus(second.id)

        let updated = tracker.applyingSequences(to: [first, second])
        XCTAssertEqual(updated[0].lastFocusSequence, 0)
        XCTAssertGreaterThan(updated[1].lastFocusSequence, 0)

        tracker.retainOnly([first.id])
        XCTAssertEqual(tracker.sequence(for: second.id), 0)
    }

    @Test
    func testSequenceOverflowRebasesWithoutLosingOrder() {
        let older = TestFixtures.key(1)
        let newer = TestFixtures.key(2)
        let focused = TestFixtures.key(3)
        var tracker = WindowMRUTracker(
            currentSequence: .max,
            sequences: [older: 10, newer: 20]
        )

        tracker.recordFocus(focused)

        XCTAssertGreaterThan(
            tracker.sequence(for: newer),
            tracker.sequence(for: older)
        )
        XCTAssertGreaterThan(
            tracker.sequence(for: focused),
            tracker.sequence(for: newer)
        )
        XCTAssertEqual(tracker.currentSequence, 3)
    }
}
