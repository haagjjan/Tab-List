import XCTest
@testable import TabListCore

final class SwitcherSessionReducerTests: XCTestCase {
    private let original = TestFixtures.window(1, focusSequence: 30)
    private let previous = TestFixtures.window(2, focusSequence: 20)
    private let older = TestFixtures.window(3, focusSequence: 10)

    func testBeginRequestsFreshSnapshotAndEntersPreparing() {
        var state = SwitcherSessionState()
        let focus = FocusSnapshot(
            applicationPID: original.id.pid,
            windowKey: original.id
        )

        let effects = reduce(&state, .begin(originalFocus: focus))

        XCTAssertEqual(state.phase, .preparing)
        XCTAssertEqual(state.originalFocus, focus)
        XCTAssertEqual(
            effects,
            [.requestSnapshot(forceRefreshIfStale: true)]
        )
    }

    func testPreparationSelectsFirstAlternativeWhichIsNormallySecondMRU() {
        var state = beginningState()

        let effects = reduce(
            &state,
            .prepared(
                snapshotGeneration: 4,
                orderedItems: [original, previous, older]
            )
        )

        XCTAssertEqual(state.phase, .visible)
        XCTAssertTrue(state.isPanelVisible)
        XCTAssertEqual(state.snapshotGeneration, 4)
        XCTAssertEqual(state.selectedIndex, 1)
        XCTAssertEqual(state.selectedWindow, previous)
        XCTAssertEqual(
            effects,
            [.presentPanel, .selectionChanged(index: 1)]
        )
    }

    func testPreparationSelectsFirstItemWhenOriginalIsNotEligible() {
        var state = beginningState()

        reduce(
            &state,
            .prepared(
                snapshotGeneration: 1,
                orderedItems: [previous, older]
            )
        )

        XCTAssertEqual(state.selectedIndex, 0)
        XCTAssertEqual(state.selectedWindow, previous)
    }

    func testReverseOpeningSelectsItemBeforeOriginalInWrappedMRUOrder() {
        var state = SwitcherSessionState()
        reduce(
            &state,
            .begin(
                originalFocus: FocusSnapshot(
                    applicationPID: original.id.pid,
                    windowKey: original.id
                ),
                initialDirection: .backward
            )
        )

        let effects = reduce(
            &state,
            .prepared(
                snapshotGeneration: 1,
                orderedItems: [original, previous, older]
            )
        )

        XCTAssertEqual(state.selectedIndex, 2)
        XCTAssertEqual(state.selectedWindow, older)
        XCTAssertEqual(
            effects,
            [.presentPanel, .selectionChanged(index: 2)]
        )
    }

    func testReverseOpeningUsesLastItemWhenOriginalIsNotEligible() {
        var state = SwitcherSessionState()
        reduce(
            &state,
            .begin(
                originalFocus: FocusSnapshot(
                    applicationPID: original.id.pid,
                    windowKey: original.id
                ),
                initialDirection: .backward
            )
        )

        reduce(
            &state,
            .prepared(
                snapshotGeneration: 1,
                orderedItems: [previous, older]
            )
        )

        XCTAssertEqual(state.selectedWindow, older)
    }

    func testOpeningDirectionIsRelativeToOriginalWhenItIsNotFirst() {
        let newestOther = TestFixtures.window(9, focusSequence: 40)
        let ordered = [newestOther, original, previous, older]
        let focus = FocusSnapshot(
            applicationPID: original.id.pid,
            windowKey: original.id
        )

        var forward = SwitcherSessionState()
        reduce(
            &forward,
            .begin(originalFocus: focus, initialDirection: .forward)
        )
        reduce(
            &forward,
            .prepared(snapshotGeneration: 1, orderedItems: ordered)
        )

        var backward = SwitcherSessionState()
        reduce(
            &backward,
            .begin(originalFocus: focus, initialDirection: .backward)
        )
        reduce(
            &backward,
            .prepared(snapshotGeneration: 1, orderedItems: ordered)
        )

        XCTAssertEqual(forward.selectedWindow, previous)
        XCTAssertEqual(backward.selectedWindow, newestOther)
    }

    func testRepeatedCycleInputDuringPreparationIsAppliedOnPresentation() {
        var state = beginningState()

        XCTAssertTrue(reduce(&state, .cycle(.forward)).isEmpty)
        XCTAssertEqual(state.queuedCycleOffset, 1)
        reduce(
            &state,
            .prepared(
                snapshotGeneration: 1,
                orderedItems: [original, previous, older]
            )
        )

        XCTAssertEqual(state.selectedWindow, older)
        XCTAssertEqual(state.queuedCycleOffset, 0)
    }

    func testModifierReleaseDuringPreparationCommitsWithoutFlashingPanel() {
        var state = beginningState()

        XCTAssertTrue(reduce(&state, .modifierReleased).isEmpty)
        XCTAssertTrue(state.commitWhenPrepared)
        let effects = reduce(
            &state,
            .prepared(
                snapshotGeneration: 1,
                orderedItems: [original, previous, older]
            )
        )

        XCTAssertEqual(state.phase, .committing)
        XCTAssertFalse(state.isPanelVisible)
        XCTAssertEqual(state.selectedWindow, previous)
        XCTAssertEqual(effects, [.activate(previous.id)])
    }

    func testNoPanelAppearsWhenOnlyOriginalOrNoWindowExists() {
        for items in [[original], []] {
            var state = beginningState()

            let effects = reduce(
                &state,
                .prepared(snapshotGeneration: 1, orderedItems: items)
            )

            XCTAssertEqual(state.phase, .idle)
            XCTAssertTrue(effects.isEmpty)
        }
    }

    func testPreparationFailureResetsEveryOpeningField() {
        var state = beginningState()
        reduce(&state, .cycle(.forward))
        reduce(&state, .modifierReleased)

        XCTAssertTrue(reduce(&state, .preparationFailed).isEmpty)
        XCTAssertEqual(state, SwitcherSessionState())

        XCTAssertTrue(
            reduce(
                &state,
                .prepared(
                    snapshotGeneration: 2,
                    orderedItems: [original, previous]
                )
            ).isEmpty
        )
        XCTAssertEqual(state, SwitcherSessionState())
    }

    func testLargeQueuedReverseOffsetWrapsWhenPreparationFinishes() {
        var state = beginningState()
        for _ in 0 ..< 5 {
            reduce(&state, .cycle(.backward))
        }

        reduce(
            &state,
            .prepared(
                snapshotGeneration: 1,
                orderedItems: [original, previous, older]
            )
        )

        XCTAssertEqual(state.selectedWindow, older)
        XCTAssertEqual(state.queuedCycleOffset, 0)
    }

    func testForwardAndBackwardCyclingWrap() {
        var state = visibleState()

        XCTAssertEqual(
            reduce(&state, .cycle(.forward)),
            [.selectionChanged(index: 2)]
        )
        XCTAssertEqual(state.selectedWindow, older)
        XCTAssertEqual(
            reduce(&state, .cycle(.forward)),
            [.selectionChanged(index: 0)]
        )
        XCTAssertEqual(state.selectedWindow, original)
        XCTAssertEqual(
            reduce(&state, .cycle(.backward)),
            [.selectionChanged(index: 2)]
        )
        XCTAssertEqual(state.selectedWindow, older)
    }

    func testModifierReleaseDismissesThenActivatesSelection() {
        var state = visibleState()

        let effects = reduce(&state, .modifierReleased)

        XCTAssertEqual(state.phase, .committing)
        XCTAssertTrue(state.isPanelVisible)
        XCTAssertEqual(
            effects,
            [.dismissPanel, .activate(previous.id)]
        )

        XCTAssertTrue(
            reduce(&state, .activationCompleted(.success)).isEmpty
        )
        XCTAssertEqual(state, SwitcherSessionState())
    }

    func testPanelDismissalDuringCommitUpdatesVisibilityWithoutEndingSession() {
        var state = visibleState()
        reduce(&state, .modifierReleased)

        XCTAssertTrue(reduce(&state, .panelDismissed).isEmpty)
        XCTAssertEqual(state.phase, .committing)
        XCTAssertFalse(state.isPanelVisible)
    }

    func testMouseClickSelectsAndCommitsImmediately() {
        var state = visibleState()

        let effects = reduce(&state, .mouseActivate(index: 2))

        XCTAssertEqual(state.selectedWindow, older)
        XCTAssertEqual(state.phase, .committing)
        XCTAssertEqual(effects, [.dismissPanel, .activate(older.id)])
    }

    func testInvalidMouseSelectionDoesNotChangeOrCommit() {
        var state = visibleState()
        let selected = state.selectedWindow

        XCTAssertTrue(reduce(&state, .mouseActivate(index: -1)).isEmpty)
        XCTAssertTrue(reduce(&state, .mouseActivate(index: 99)).isEmpty)
        XCTAssertEqual(state.phase, .visible)
        XCTAssertEqual(state.selectedWindow, selected)
    }

    func testEscapeDismissesWithoutActivationAndReleaseCannotCommit() {
        var state = visibleState()

        XCTAssertEqual(reduce(&state, .cancel), [.dismissPanel])
        XCTAssertEqual(state.phase, .cancelling)
        XCTAssertTrue(reduce(&state, .modifierReleased).isEmpty)
        XCTAssertTrue(reduce(&state, .panelDismissed).isEmpty)
        XCTAssertEqual(state, SwitcherSessionState())
    }

    func testEscapeDuringPreparationReturnsToIdle() {
        var state = beginningState()

        XCTAssertTrue(reduce(&state, .cancel).isEmpty)
        XCTAssertEqual(state, SwitcherSessionState())
    }

    func testCloseOnUnclosableWindowBeepsWithoutCallingService() {
        let unclosable = TestFixtures.window(
            2,
            isClosable: false,
            focusSequence: 20
        )
        var state = visibleState(items: [original, unclosable])

        XCTAssertEqual(reduce(&state, .closeSelected), [.beep])
        XCTAssertNil(state.pendingClose)
    }

    func testHoverCloseSelectsAndClosesRequestedNonselectedItem() {
        var state = visibleState()
        XCTAssertEqual(state.selectedWindow, previous)

        let effects = reduce(&state, .close(index: 2))

        XCTAssertEqual(state.selectedWindow, older)
        XCTAssertEqual(state.pendingClose, older.id)
        XCTAssertEqual(
            effects,
            [.selectionChanged(index: 2), .close(older.id)]
        )
    }

    func testHoverCloseRejectsInvalidIndexAndConcurrentClose() {
        var state = visibleState()

        XCTAssertTrue(reduce(&state, .close(index: 99)).isEmpty)
        reduce(&state, .closeSelected)
        XCTAssertTrue(reduce(&state, .close(index: 2)).isEmpty)
        XCTAssertEqual(state.pendingClose, previous.id)
    }

    func testSuccessfulCloseKeepsSameIndexAndSelectsNextItem() {
        var state = visibleState()

        XCTAssertEqual(
            reduce(&state, .closeSelected),
            [.close(previous.id)]
        )
        XCTAssertEqual(state.pendingClose, previous.id)

        let effects = reduce(
            &state,
            .closeCompleted(key: previous.id, result: .success)
        )

        XCTAssertEqual(state.items, [original, older])
        XCTAssertEqual(state.selectedIndex, 1)
        XCTAssertEqual(state.selectedWindow, older)
        XCTAssertEqual(
            effects,
            [.reloadPanel, .selectionChanged(index: 1)]
        )
    }

    func testClosingLastItemSelectsPreviousItem() {
        var state = visibleState()
        reduce(&state, .cycle(.forward))
        XCTAssertEqual(state.selectedWindow, older)
        reduce(&state, .closeSelected)

        reduce(
            &state,
            .closeCompleted(key: older.id, result: .success)
        )

        XCTAssertEqual(state.selectedIndex, 1)
        XCTAssertEqual(state.selectedWindow, previous)
    }

    func testClosingOnlyItemDismissesPanel() {
        var state = visibleState(
            originalFocus: FocusSnapshot(applicationPID: 999, windowKey: nil),
            items: [previous]
        )
        reduce(&state, .closeSelected)

        let effects = reduce(
            &state,
            .closeCompleted(key: previous.id, result: .success)
        )

        XCTAssertEqual(state.phase, .cancelling)
        XCTAssertNil(state.selectedIndex)
        XCTAssertEqual(effects, [.reloadPanel, .dismissPanel])
    }

    func testMissingCloseTargetIsRemovedAsStale() {
        var state = visibleState()
        reduce(&state, .closeSelected)

        reduce(
            &state,
            .closeCompleted(key: previous.id, result: .targetMissing)
        )

        XCTAssertFalse(state.items.contains(previous))
    }

    func testCloseConfirmationDismissesAndActivatesOwningWindow() {
        var state = visibleState()
        reduce(&state, .closeSelected)

        let effects = reduce(
            &state,
            .closeCompleted(
                key: previous.id,
                result: .confirmationRequired
            )
        )

        XCTAssertEqual(state.phase, .committing)
        XCTAssertEqual(
            effects,
            [.dismissPanel, .activate(previous.id)]
        )
    }

    func testEveryNonterminalCloseFailureBeepsAndLeavesItemAvailable() {
        let failures: [WindowActionResult] = [
            .permissionDenied,
            .unsupported,
            .timedOut,
            .failed(reason: "AX element became invalid"),
        ]

        for failure in failures {
            var state = visibleState()
            reduce(&state, .closeSelected)

            let effects = reduce(
                &state,
                .closeCompleted(key: previous.id, result: failure)
            )

            XCTAssertEqual(
                effects,
                [.beep],
                "Expected \(failure) to fail closed"
            )
            XCTAssertEqual(state.selectedWindow, previous)
            XCTAssertNil(state.pendingClose)
        }
    }

    func testRegistryUpdatePreservesSelectedKeyAtItsNewIndex() {
        var state = visibleState()

        let effects = reduce(
            &state,
            .registryUpdated(
                snapshotGeneration: 2,
                orderedItems: [older, previous, original]
            )
        )

        XCTAssertEqual(state.selectedIndex, 1)
        XCTAssertEqual(state.selectedWindow, previous)
        XCTAssertEqual(
            effects,
            [.reloadPanel, .selectionChanged(index: 1)]
        )
    }

    func testRegistryUpdateSelectsSameIndexWhenSelectedWindowDisappears() {
        var state = visibleState()

        let effects = reduce(
            &state,
            .registryUpdated(
                snapshotGeneration: 2,
                orderedItems: [original, older]
            )
        )

        XCTAssertEqual(state.selectedIndex, 1)
        XCTAssertEqual(state.selectedWindow, older)
        XCTAssertEqual(
            effects,
            [.reloadPanel, .selectionChanged(index: 1)]
        )
    }

    func testRegistryUpdateDropsPendingCloseOnlyWhenTargetDisappears() {
        var retained = visibleState()
        reduce(&retained, .closeSelected)
        reduce(
            &retained,
            .registryUpdated(
                snapshotGeneration: 2,
                orderedItems: [older, previous, original]
            )
        )
        XCTAssertEqual(retained.pendingClose, previous.id)

        var removed = retained
        reduce(
            &removed,
            .registryUpdated(
                snapshotGeneration: 3,
                orderedItems: [older, original]
            )
        )
        XCTAssertNil(removed.pendingClose)
    }

    func testCloseCompletionForDifferentWindowIsIgnored() {
        var state = visibleState()
        reduce(&state, .closeSelected)
        let before = state

        XCTAssertTrue(
            reduce(
                &state,
                .closeCompleted(key: older.id, result: .success)
            ).isEmpty
        )
        XCTAssertEqual(state, before)
    }

    func testStaleRegistryUpdateIsIgnored() {
        var state = visibleState(snapshotGeneration: 2)
        let originalItems = state.items

        XCTAssertTrue(
            reduce(
                &state,
                .registryUpdated(
                    snapshotGeneration: 2,
                    orderedItems: []
                )
            ).isEmpty
        )
        XCTAssertEqual(state.items, originalItems)
    }

    func testEmptyRegistryUpdateFailsClosed() {
        var state = visibleState()

        let effects = reduce(
            &state,
            .registryUpdated(
                snapshotGeneration: 2,
                orderedItems: []
            )
        )

        XCTAssertEqual(state.phase, .cancelling)
        XCTAssertEqual(effects, [.reloadPanel, .dismissPanel])
    }

    func testActivationFailureResetsAndBeeps() {
        var state = visibleState()
        reduce(&state, .modifierReleased)

        let effects = reduce(
            &state,
            .activationCompleted(.failed(reason: "not verified"))
        )

        XCTAssertEqual(state, SwitcherSessionState())
        XCTAssertEqual(effects, [.beep])
    }

    func testEveryTypedActivationFailureResetsAndBeeps() {
        let failures: [WindowActionResult] = [
            .targetMissing,
            .permissionDenied,
            .unsupported,
            .timedOut,
            .confirmationRequired,
            .failed(reason: "not verified"),
        ]

        for failure in failures {
            var state = visibleState()
            reduce(&state, .modifierReleased)

            XCTAssertEqual(
                reduce(&state, .activationCompleted(failure)),
                [.beep],
                "Expected \(failure) to fail closed"
            )
            XCTAssertEqual(state, SwitcherSessionState())
        }
    }

    func testStateInitializerRepairsOutOfRangeSelection() {
        let negative = SwitcherSessionState(
            phase: .visible,
            items: [original, previous],
            selectedIndex: -10,
            panelPresented: true
        )
        let beyondEnd = SwitcherSessionState(
            phase: .visible,
            items: [original, previous],
            selectedIndex: 99,
            panelPresented: true
        )
        let empty = SwitcherSessionState(
            phase: .visible,
            items: [],
            selectedIndex: 0,
            panelPresented: true
        )

        XCTAssertEqual(negative.selectedIndex, 0)
        XCTAssertEqual(beyondEnd.selectedIndex, 1)
        XCTAssertNil(empty.selectedIndex)
    }

    private func beginningState(
        focus: FocusSnapshot? = nil
    ) -> SwitcherSessionState {
        var state = SwitcherSessionState()
        reduce(
            &state,
            .begin(
                originalFocus: focus ?? FocusSnapshot(
                    applicationPID: original.id.pid,
                    windowKey: original.id
                )
            )
        )
        return state
    }

    private func visibleState(
        snapshotGeneration: UInt64 = 1,
        originalFocus: FocusSnapshot? = nil,
        items: [WindowRecord]? = nil
    ) -> SwitcherSessionState {
        var state = beginningState(
            focus: originalFocus ?? FocusSnapshot(
                applicationPID: original.id.pid,
                windowKey: original.id
            )
        )
        reduce(
            &state,
            .prepared(
                snapshotGeneration: snapshotGeneration,
                orderedItems: items ?? [original, previous, older]
            )
        )
        return state
    }

    @discardableResult
    private func reduce(
        _ state: inout SwitcherSessionState,
        _ action: SwitcherSessionAction
    ) -> [SwitcherSessionEffect] {
        SwitcherSessionReducer.reduce(state: &state, action: action)
    }
}
