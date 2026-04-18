import XCTest
import UIKit
@testable import tic

final class CalendarDragCoordinatorTests: XCTestCase {
    func testDropOwnerStaysRootAfterLeavingDayScope() {
        XCTAssertEqual(
            DragDropOwner.nextOwner(
                afterShowing: .month,
                currentOwner: .localDayTimeline
            ),
            .rootCoordinator
        )
        XCTAssertEqual(
            DragDropOwner.nextOwner(
                afterShowing: .day,
                currentOwner: .rootCoordinator
            ),
            .rootCoordinator
        )
    }

    func testBeginDragCreatesPendingLocalPreviewWithoutDeadlock() {
        let coordinator = makeCoordinator()

        beginDrag(coordinator, item: makeItem())

        XCTAssertEqual(coordinator.handoffState.phase, .rootClaimPending)
        XCTAssertTrue(coordinator.handoffState.isLocalPreviewActive)
        XCTAssertTrue(coordinator.handoffState.isRootClaimPending)
        XCTAssertEqual(coordinator.currentHandoffOwner, .localPreview)
        XCTAssertNotNil(coordinator.currentHandoffToken)
        XCTAssertEqual(coordinator.dropOwner, .localDayTimeline)
        XCTAssertTrue(coordinator.shouldHandleDropLocally)
        XCTAssertFalse(coordinator.shouldHandleDragGlobally)
        XCTAssertNil(coordinator.sourcePlaceholderOpacity(for: "event-1"))
        XCTAssertEqual(coordinator.overlayPresentation.visualPhase, .lifted)
    }

    func testDragStartAndClaimSuccessRecordTraceEvents() {
        let recorder = DragHandoffTraceRecorder()
        let coordinator = makeCoordinator(traceRecorder: recorder)

        beginDrag(coordinator, item: makeItem())
        let token = currentToken(for: coordinator)

        claimSuccess(coordinator)

        XCTAssertEqual(
            recorder.events,
            [
                .dragStart(token: token),
                .rootClaimSuccess(token: token),
                .claimLatencyMs(16)
            ]
        )
    }

    func testClaimSuccessEnablesRootOwnerAndPlaceholderOnlyAfterSuccess() {
        let coordinator = makeCoordinator()
        let item = makeItem()

        beginDrag(coordinator, item: item)
        coordinator.updateActiveDrag(pointerGlobal: movedPointer)

        XCTAssertFalse(coordinator.isShowingPlaceholder(for: item.id))
        XCTAssertEqual(coordinator.currentHandoffOwner, .localPreview)

        let token = currentToken(for: coordinator)
        let result = coordinator.applyRootClaimSuccess(
            for: token,
            at: timestamp(frame: 11, uptimeMs: 116)
        )

        XCTAssertEqual(result, .applied)
        XCTAssertEqual(coordinator.handoffState.phase, .rootClaimAcquired)
        XCTAssertTrue(coordinator.handoffState.isRootClaimAcquired)
        XCTAssertEqual(coordinator.currentHandoffOwner, .root)
        XCTAssertEqual(coordinator.dropOwner, .rootCoordinator)
        XCTAssertTrue(coordinator.shouldHandleDragGlobally)
        XCTAssertFalse(coordinator.shouldHandleDropLocally)
        XCTAssertTrue(coordinator.isShowingPlaceholder(for: item.id))
        XCTAssertNotNil(coordinator.sourcePlaceholderOpacity(for: item.id))
    }

    func testRootOverlayStaysHiddenWhilePendingAndPromotesAfterClaimSuccess() {
        let coordinator = makeCoordinator()
        let item = makeItem()

        beginDrag(coordinator, item: item)
        coordinator.updateActiveDrag(pointerGlobal: movedPointer)

        XCTAssertFalse(coordinator.isRootOverlayVisible)
        XCTAssertNil(coordinator.rootOverlayItem)
        XCTAssertNil(coordinator.rootOverlayFrameLocal)
        XCTAssertNotNil(coordinator.localPreviewFrameGlobal(for: item.id))

        claimSuccess(coordinator)

        XCTAssertTrue(coordinator.isRootOverlayVisible)
        XCTAssertNotNil(coordinator.rootOverlayItem)
        XCTAssertNotNil(coordinator.rootOverlayFrameLocal)
        XCTAssertNil(coordinator.localPreviewFrameGlobal(for: item.id))
    }

    func testSameDayDropStillCommitsThroughLocalPreviewWhileClaimPending() {
        let coordinator = makeCoordinator()
        let item = makeItem()

        beginDrag(coordinator, item: item)
        coordinator.updateActiveDrag(pointerGlobal: movedPointer)

        let commit = coordinator.completeLocalDrag()

        XCTAssertEqual(commit?.itemId, item.id)
        XCTAssertEqual(commit?.start, movedStartDate)
        XCTAssertEqual(commit?.end, movedEndDate)
    }

    func testAttachedRelayKeepsSameDayDropLocalUntilScopeLeavesDay() {
        let coordinator = makeCoordinator()
        let item = makeItem()

        beginDrag(coordinator, item: item)
        let token = currentToken(for: coordinator)

        coordinator.attachTouchTrackingRelay(for: token)

        XCTAssertEqual(coordinator.currentHandoffOwner, .localPreview)
        XCTAssertFalse(coordinator.shouldHandleDragGlobally)
        XCTAssertTrue(coordinator.shouldHandleDropLocally)
        XCTAssertTrue(coordinator.hasPendingTouchRelay)
        XCTAssertFalse(coordinator.shouldPromoteRelayedTouchToRootClaim(for: token))

        coordinator.updateActiveDrag(pointerGlobal: movedPointer)

        let commit = coordinator.completeLocalDrag()

        XCTAssertEqual(commit?.itemId, item.id)
        XCTAssertEqual(commit?.start, movedStartDate)
        XCTAssertEqual(commit?.end, movedEndDate)
    }

    func testReturningToDayAfterRootOwnershipDoesNotCommitLocally() {
        let coordinator = makeCoordinator()
        let item = makeItem()

        beginDrag(coordinator, item: item)
        coordinator.updateActiveDrag(pointerGlobal: movedPointer)
        claimSuccess(coordinator)

        coordinator.updateVisibleScope(.month)
        coordinator.updateVisibleScope(.day)

        XCTAssertEqual(coordinator.dropOwner, .rootCoordinator)
        XCTAssertFalse(coordinator.shouldHandleDropLocally)
        XCTAssertTrue(coordinator.shouldHandleDragGlobally)
        XCTAssertNil(coordinator.completeLocalDrag())

        let commit = coordinator.completeGlobalDrag()

        XCTAssertEqual(commit?.itemId, item.id)
        XCTAssertEqual(commit?.start, movedStartDate)
        XCTAssertEqual(commit?.end, movedEndDate)
    }

    func testMonthHoverStaysDisabledUntilClaimSuccess() {
        let coordinator = makeCoordinator(
            overlayTimings: DragOverlayAnimationTimings(
                liftDurationMs: 1,
                scopeHoldDurationMs: 1,
                pillTransitionDurationMs: 1,
                landingDurationMs: 1
            )
        )
        let item = makeItem()
        let dropDate = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 20))!
        let dropPoint = CGPoint(x: 260, y: 100)
        let monthFrames = [
            DateCellFrame(date: dropDate, frameGlobal: CGRect(x: 240, y: 80, width: 60, height: 60))
        ]

        beginDrag(coordinator, item: item)
        coordinator.updateActiveDrag(pointerGlobal: movedPointer)
        coordinator.updateCalendarFrames(monthFrames, scope: .month)
        coordinator.updateVisibleScope(.month)
        coordinator.updateActiveDrag(pointerGlobal: dropPoint)

        XCTAssertNil(coordinator.snapshot.activeDate)
        XCTAssertFalse(coordinator.handoffState.allowsCalendarHover)
        XCTAssertFalse(coordinator.shouldHandleDragGlobally)
        XCTAssertTrue(coordinator.isRootOverlayVisible)
        XCTAssertNotNil(coordinator.rootOverlayItem)
        XCTAssertNotNil(coordinator.rootOverlayFrameLocal)
        XCTAssertNil(coordinator.localPreviewFrameGlobal(for: item.id))
        XCTAssertEqual(coordinator.overlayPresentation.visualPhase, .holding)
        XCTAssertEqual(coordinator.overlayPresentation.style, .timelineCard)

        claimSuccess(coordinator, frame: 11, uptimeMs: 116)
        waitForCleanup()

        XCTAssertEqual(coordinator.snapshot.activeDate, dropDate.startOfDay)
        XCTAssertTrue(coordinator.handoffState.allowsCalendarHover)
        XCTAssertTrue(coordinator.shouldHandleDragGlobally)
        XCTAssertEqual(coordinator.overlayPresentation.visualPhase, .floating)
        XCTAssertEqual(coordinator.overlayPresentation.style, .calendarPill)
    }

    func testPendingMonthTransitionSuppressesInlineSourceAndRestoresThroughContinuityOverlay() {
        let coordinator = makeCoordinator(
            restoreAnimationMs: 1,
            overlayTimings: DragOverlayAnimationTimings(
                liftDurationMs: 1,
                scopeHoldDurationMs: 1,
                pillTransitionDurationMs: 1,
                landingDurationMs: 1
            )
        )
        let item = makeItem()

        beginDrag(coordinator, item: item)
        coordinator.updateActiveDrag(pointerGlobal: movedPointer)
        coordinator.updateVisibleScope(.month)

        XCTAssertTrue(coordinator.isRootOverlayVisible)
        XCTAssertTrue(coordinator.shouldSuppressInlineSourceBlock(for: item.id))
        XCTAssertNil(coordinator.localPreviewFrameGlobal(for: item.id))
        XCTAssertFalse(coordinator.shouldHandleDragGlobally)
        XCTAssertNil(coordinator.snapshot.activeDate)

        coordinator.cancelDrag()

        XCTAssertEqual(coordinator.handoffState.phase, .restoring)
        XCTAssertTrue(coordinator.isRootOverlayVisible)
        XCTAssertTrue(coordinator.shouldSuppressInlineSourceBlock(for: item.id))
        XCTAssertNil(coordinator.localPreviewFrameGlobal(for: item.id))

        waitForRestoreCleanup()

        XCTAssertEqual(coordinator.handoffState.phase, .idle)
        XCTAssertFalse(coordinator.hasActiveSession)
        XCTAssertFalse(coordinator.isRootOverlayVisible)
    }

    func testPendingTouchRelayKeepsHoldingCardMovingWithoutOpeningOwnership() {
        let coordinator = makeCoordinator(
            overlayTimings: DragOverlayAnimationTimings(
                liftDurationMs: 1,
                scopeHoldDurationMs: 1,
                pillTransitionDurationMs: 1,
                landingDurationMs: 1
            )
        )
        let item = makeItem()
        let dropDate = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 20))!
        let dropPoint = CGPoint(x: 260, y: 100)
        let monthFrames = [
            DateCellFrame(date: dropDate, frameGlobal: CGRect(x: 240, y: 80, width: 60, height: 60))
        ]

        beginDrag(coordinator, item: item)
        coordinator.updateActiveDrag(pointerGlobal: movedPointer)
        coordinator.updateCalendarFrames(monthFrames, scope: .month)
        coordinator.updateVisibleScope(.month)
        let token = currentToken(for: coordinator)
        let beforeFrame = coordinator.rootOverlayFrameLocal

        coordinator.attachTouchTrackingRelay(for: token)
        coordinator.updateRelayedTouchMove(for: token, pointerGlobal: dropPoint)

        XCTAssertTrue(coordinator.hasPendingTouchRelay)
        XCTAssertNotEqual(coordinator.rootOverlayFrameLocal?.origin.x, beforeFrame?.origin.x)
        XCTAssertNotEqual(coordinator.rootOverlayFrameLocal?.origin.y, beforeFrame?.origin.y)
        XCTAssertFalse(coordinator.shouldHandleDragGlobally)
        XCTAssertFalse(coordinator.handoffState.allowsCalendarHover)
        XCTAssertNil(coordinator.snapshot.activeDate)
        XCTAssertEqual(coordinator.overlayPresentation.visualPhase, .holding)
        XCTAssertEqual(coordinator.overlayPresentation.style, .timelineCard)
        XCTAssertTrue(coordinator.shouldPromoteRelayedTouchToRootClaim(for: token))
    }

    func testPendingTouchRelayPromotesToRootClaimAndStartsCalendarPillPath() {
        let coordinator = makeCoordinator(
            overlayTimings: DragOverlayAnimationTimings(
                liftDurationMs: 1,
                scopeHoldDurationMs: 1,
                pillTransitionDurationMs: 1,
                landingDurationMs: 1
            )
        )
        let item = makeItem()
        let dropDate = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 20))!
        let dropPoint = CGPoint(x: 260, y: 100)
        let monthFrames = [
            DateCellFrame(date: dropDate, frameGlobal: CGRect(x: 240, y: 80, width: 60, height: 60))
        ]

        beginDrag(coordinator, item: item)
        coordinator.updateActiveDrag(pointerGlobal: movedPointer)
        coordinator.updateCalendarFrames(monthFrames, scope: .month)
        coordinator.updateVisibleScope(.month)
        let token = currentToken(for: coordinator)

        coordinator.attachTouchTrackingRelay(for: token)
        coordinator.updateRelayedTouchMove(for: token, pointerGlobal: dropPoint)
        XCTAssertTrue(coordinator.shouldPromoteRelayedTouchToRootClaim(for: token))

        let result = coordinator.applyRootClaimSuccess(
            for: token,
            at: timestamp(frame: 11, uptimeMs: 116)
        )
        XCTAssertEqual(result, .applied)
        waitForCleanup()

        XCTAssertFalse(coordinator.hasPendingTouchRelay)
        XCTAssertTrue(coordinator.shouldHandleDragGlobally)
        XCTAssertTrue(coordinator.handoffState.allowsCalendarHover)
        XCTAssertEqual(coordinator.snapshot.activeDate, dropDate.startOfDay)
        XCTAssertEqual(coordinator.overlayPresentation.visualPhase, .floating)
        XCTAssertEqual(coordinator.overlayPresentation.style, .calendarPill)
    }

    func testAttachedRelayPreventsPendingTimeoutRestore() {
        let coordinator = makeCoordinator(
            overlayTimings: DragOverlayAnimationTimings(
                liftDurationMs: 1,
                scopeHoldDurationMs: 1,
                pillTransitionDurationMs: 1,
                landingDurationMs: 1
            )
        )
        let item = makeItem()

        beginDrag(coordinator, item: item)
        coordinator.updateActiveDrag(pointerGlobal: movedPointer)
        let token = currentToken(for: coordinator)

        coordinator.attachTouchTrackingRelay(for: token)

        let result = coordinator.expirePendingRootClaimIfNeeded(
            at: timestamp(frame: 13, uptimeMs: 150)
        )

        XCTAssertEqual(result, .ignored)
        XCTAssertEqual(coordinator.handoffState.phase, .rootClaimPending)
        XCTAssertTrue(coordinator.hasPendingTouchRelay)
        XCTAssertTrue(coordinator.hasActiveSession)
    }

    func testMonthScopeChangePromotesAttachedRelayWithoutAdditionalMove() {
        let coordinator = makeCoordinator(
            overlayTimings: DragOverlayAnimationTimings(
                liftDurationMs: 1,
                scopeHoldDurationMs: 1,
                pillTransitionDurationMs: 1,
                landingDurationMs: 1
            )
        )
        let item = makeItem()
        let dropDate = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 20))!
        let monthFrames = [
            DateCellFrame(date: dropDate, frameGlobal: CGRect(x: 240, y: 80, width: 60, height: 60))
        ]

        beginDrag(coordinator, item: item)
        coordinator.updateActiveDrag(pointerGlobal: movedPointer)
        coordinator.updateCalendarFrames(monthFrames, scope: .month)
        let token = currentToken(for: coordinator)

        coordinator.attachTouchTrackingRelay(for: token)
        coordinator.updateVisibleScope(.month)

        waitForCleanup()

        XCTAssertEqual(coordinator.handoffState.phase, .rootClaimAcquired)
        XCTAssertFalse(coordinator.hasPendingTouchRelay)
        XCTAssertTrue(coordinator.shouldHandleDragGlobally)
        XCTAssertTrue(coordinator.handoffState.allowsCalendarHover)
        XCTAssertNil(coordinator.snapshot.activeDate)
        XCTAssertEqual(coordinator.overlayPresentation.visualPhase, .floating)
        XCTAssertEqual(coordinator.overlayPresentation.style, .calendarPill)
        XCTAssertTrue(coordinator.isRootOverlayVisible)
    }

    func testClaimTimeoutRestoresSessionThroughRestorePath() {
        let recorder = DragHandoffTraceRecorder()
        let coordinator = makeCoordinator(
            restoreAnimationMs: 1,
            overlayTimings: DragOverlayAnimationTimings(
                liftDurationMs: 1,
                scopeHoldDurationMs: 1,
                pillTransitionDurationMs: 1,
                landingDurationMs: 1
            ),
            traceRecorder: recorder
        )

        beginDrag(coordinator, item: makeItem())
        coordinator.updateActiveDrag(pointerGlobal: movedPointer)
        let token = currentToken(for: coordinator)

        let result = coordinator.expirePendingRootClaimIfNeeded(
            at: timestamp(frame: 13, uptimeMs: 150)
        )

        XCTAssertEqual(result, .applied)
        XCTAssertEqual(coordinator.handoffState.phase, .restoring)
        XCTAssertEqual(coordinator.handoffState.restoreReason, .timeout)
        XCTAssertEqual(coordinator.currentHandoffOwner, .localPreview)
        XCTAssertFalse(coordinator.isRootOverlayVisible)
        XCTAssertNotNil(coordinator.localPreviewFrameGlobal(for: "event-1"))
        XCTAssertFalse(coordinator.isShowingPlaceholder(for: "event-1"))
        XCTAssertEqual(coordinator.overlayPresentation.visualPhase, .restoring)
        XCTAssertEqual(
            recorder.events,
            [
                .dragStart(token: token),
                .rootClaimTimeout(token: token),
                .restoreReason(.timeout)
            ]
        )

        waitForRestoreCleanup()

        XCTAssertEqual(coordinator.snapshot.state, .idle)
        XCTAssertEqual(coordinator.handoffState.phase, .idle)
        XCTAssertEqual(coordinator.lastSessionTermination, .cancelled)
        XCTAssertFalse(coordinator.isSessionVisible)
        XCTAssertNil(coordinator.rootOverlayItem)
    }

    func testStaleTokenSuccessDoesNotContaminateCurrentSession() {
        let coordinator = makeCoordinator()
        let item = makeItem()

        beginDrag(coordinator, item: item)
        let staleToken = currentToken(for: coordinator)

        beginDrag(coordinator, item: item)
        let currentToken = currentToken(for: coordinator)

        let result = coordinator.applyRootClaimSuccess(
            for: staleToken,
            at: timestamp(frame: 12, uptimeMs: 132)
        )

        XCTAssertEqual(result, .staleIgnored)
        XCTAssertEqual(coordinator.currentHandoffToken, currentToken)
        XCTAssertEqual(coordinator.handoffState.phase, .rootClaimPending)
        XCTAssertEqual(coordinator.currentHandoffOwner, .localPreview)
        XCTAssertFalse(coordinator.shouldHandleDragGlobally)
    }

    func testStaleTokenEndDoesNotContaminateCurrentSession() {
        let coordinator = makeCoordinator()
        let item = makeItem()

        beginDrag(coordinator, item: item)
        let staleToken = currentToken(for: coordinator)

        beginDrag(coordinator, item: item)
        let currentToken = currentToken(for: coordinator)

        let result = coordinator.applyRootClaimEnd(for: staleToken)

        XCTAssertEqual(result, .staleIgnored)
        XCTAssertEqual(coordinator.currentHandoffToken, currentToken)
        XCTAssertEqual(coordinator.handoffState.phase, .rootClaimPending)
        XCTAssertEqual(coordinator.currentHandoffOwner, .localPreview)
        XCTAssertFalse(coordinator.shouldHandleDragGlobally)
    }

    func testPlaceholderClearsAfterGlobalSessionEnds() {
        let coordinator = makeCoordinator(
            overlayTimings: DragOverlayAnimationTimings(
                liftDurationMs: 1,
                scopeHoldDurationMs: 1,
                pillTransitionDurationMs: 1,
                landingDurationMs: 1
            )
        )
        let item = makeItem()

        beginDrag(coordinator, item: item)
        coordinator.updateActiveDrag(pointerGlobal: movedPointer)
        claimSuccess(coordinator)
        coordinator.updateVisibleScope(.month)
        coordinator.updateVisibleScope(.day)

        XCTAssertTrue(coordinator.isShowingPlaceholder(for: item.id))
        XCTAssertTrue(coordinator.isSessionVisible)

        _ = coordinator.completeGlobalDrag()
        waitForCleanup()

        XCTAssertFalse(coordinator.isShowingPlaceholder(for: item.id))
        XCTAssertEqual(coordinator.handoffState.phase, .idle)
        XCTAssertFalse(coordinator.isSessionVisible)
        XCTAssertNil(coordinator.sessionItem)
    }

    func testMonthTransitionKeepsHoldingCardUntilRootClaimSuccessThenBecomesCalendarPill() {
        let coordinator = makeCoordinator(
            overlayTimings: DragOverlayAnimationTimings(
                liftDurationMs: 1,
                scopeHoldDurationMs: 1,
                pillTransitionDurationMs: 1,
                landingDurationMs: 1
            )
        )
        let item = makeItem()
        let dropDate = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 20))!
        let monthFrames = [
            DateCellFrame(date: dropDate, frameGlobal: CGRect(x: 240, y: 80, width: 60, height: 60))
        ]

        beginDrag(coordinator, item: item)
        coordinator.updateActiveDrag(pointerGlobal: movedPointer)
        coordinator.updateCalendarFrames(monthFrames, scope: .month)
        coordinator.updateVisibleScope(.month)

        XCTAssertEqual(coordinator.overlayPresentation.visualPhase, .holding)
        XCTAssertEqual(coordinator.overlayPresentation.style, .timelineCard)

        claimSuccess(coordinator)
        waitForCleanup()

        XCTAssertEqual(coordinator.overlayPresentation.visualPhase, .floating)
        XCTAssertEqual(coordinator.overlayPresentation.style, .calendarPill)
    }

    func testScopeRoundTripGlobalDropReturnsCommittedDayState() {
        let coordinator = makeCoordinator(
            overlayTimings: DragOverlayAnimationTimings(
                liftDurationMs: 1,
                scopeHoldDurationMs: 1,
                pillTransitionDurationMs: 1,
                landingDurationMs: 1
            )
        )
        let item = makeItem()
        let dropDate = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 20))!
        let dropPoint = CGPoint(x: 260, y: 100)
        let monthFrames = [
            DateCellFrame(date: dropDate, frameGlobal: CGRect(x: 240, y: 80, width: 60, height: 60))
        ]
        let yearFrames = [
            DateCellFrame(date: dropDate, frameGlobal: CGRect(x: 240, y: 80, width: 60, height: 60))
        ]

        beginDrag(coordinator, item: item)
        coordinator.updateActiveDrag(pointerGlobal: movedPointer)
        claimSuccess(coordinator)
        coordinator.updateCalendarFrames(monthFrames, scope: .month)
        coordinator.updateCalendarFrames(yearFrames, scope: .year)

        coordinator.updateVisibleScope(.month)
        coordinator.updateGlobalDrag(pointerGlobal: dropPoint)
        coordinator.updateVisibleScope(.year)
        coordinator.updateGlobalDrag(pointerGlobal: dropPoint)
        coordinator.updateVisibleScope(.month)
        coordinator.updateGlobalDrag(pointerGlobal: dropPoint)

        let commit = coordinator.completeGlobalDrag()
        let state = commit.map { CalendarScopeTransition.stateAfterGlobalDrop(commit: $0) }

        XCTAssertEqual(commit?.itemId, item.id)
        XCTAssertEqual(commit?.start, expectedStartDate(on: dropDate, hour: 3, minute: 30))
        XCTAssertEqual(commit?.end, expectedStartDate(on: dropDate, hour: 4, minute: 30))
        XCTAssertEqual(state?.scope, .day)
        XCTAssertEqual(state?.selectedDate, dropDate.startOfDay)
        XCTAssertEqual(state?.displayedMonth, dropDate.startOfMonth)
        XCTAssertEqual(state?.displayedYear, dropDate.year)
    }

    func testRoundTripTouchUpTerminatesOnlyOnce() {
        let coordinator = makeCoordinator(
            overlayTimings: DragOverlayAnimationTimings(
                liftDurationMs: 1,
                scopeHoldDurationMs: 1,
                pillTransitionDurationMs: 1,
                landingDurationMs: 1
            )
        )
        let item = makeItem()
        let dropDate = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 20))!
        let dropPoint = CGPoint(x: 260, y: 100)
        let monthFrames = [
            DateCellFrame(date: dropDate, frameGlobal: CGRect(x: 240, y: 80, width: 60, height: 60))
        ]
        let yearFrames = [
            DateCellFrame(date: dropDate, frameGlobal: CGRect(x: 240, y: 80, width: 60, height: 60))
        ]

        beginDrag(coordinator, item: item)
        coordinator.updateActiveDrag(pointerGlobal: movedPointer)
        claimSuccess(coordinator)
        coordinator.updateCalendarFrames(monthFrames, scope: .month)
        coordinator.updateCalendarFrames(yearFrames, scope: .year)
        coordinator.updateVisibleScope(.month)
        coordinator.updateGlobalDrag(pointerGlobal: dropPoint)
        coordinator.updateVisibleScope(.year)
        coordinator.updateGlobalDrag(pointerGlobal: dropPoint)
        coordinator.updateVisibleScope(.month)
        coordinator.updateGlobalDrag(pointerGlobal: dropPoint)

        let token = currentToken(for: coordinator)
        let commit = coordinator.completeGlobalDrag()
        let nextState = commit.map { CalendarScopeTransition.stateAfterGlobalDrop(commit: $0) }

        XCTAssertNotNil(commit)
        if let nextState {
            coordinator.updateVisibleDay(nextState.selectedDate)
            coordinator.updateVisibleScope(nextState.scope)
        }

        waitForCleanup()

        XCTAssertEqual(coordinator.lastSessionTermination, .committed)
        XCTAssertEqual(coordinator.sessionTerminationCount, 1)
        XCTAssertFalse(coordinator.hasActiveSession)
        XCTAssertEqual(coordinator.applyRootClaimEnd(for: token), .ignored)
        XCTAssertEqual(coordinator.sessionTerminationCount, 1)
    }

    func testStaleClaimSuccessAfterCancellationDoesNotReviveSession() {
        let recorder = DragHandoffTraceRecorder()
        let coordinator = makeCoordinator(
            restoreAnimationMs: 1,
            overlayTimings: DragOverlayAnimationTimings(
                liftDurationMs: 1,
                scopeHoldDurationMs: 1,
                pillTransitionDurationMs: 1,
                landingDurationMs: 1
            ),
            traceRecorder: recorder
        )

        beginDrag(coordinator, item: makeItem())
        let token = currentToken(for: coordinator)

        XCTAssertEqual(
            coordinator.applyRootClaimCancellation(
                for: token,
                at: timestamp(frame: 11, uptimeMs: 116)
            ),
            .applied
        )
        XCTAssertEqual(coordinator.handoffState.phase, .restoring)

        waitForRestoreCleanup()

        XCTAssertEqual(
            coordinator.applyRootClaimSuccess(
                for: token,
                at: timestamp(frame: 12, uptimeMs: 132)
            ),
            .ignored
        )
        XCTAssertEqual(
            recorder.events,
            [
                .dragStart(token: token),
                .restoreReason(.cancelled)
            ]
        )
        XCTAssertEqual(coordinator.handoffState.phase, .idle)
        XCTAssertFalse(coordinator.hasActiveSession)
        XCTAssertFalse(coordinator.isSessionVisible)
        XCTAssertNil(coordinator.rootOverlayItem)
    }

    func testMonthPointerFollowKeepsPresentationStableWithinSameActiveDate() {
        let coordinator = makeCoordinator(
            overlayTimings: DragOverlayAnimationTimings(
                liftDurationMs: 1,
                scopeHoldDurationMs: 1,
                pillTransitionDurationMs: 1,
                landingDurationMs: 1
            )
        )
        let item = makeItem()
        let dropDate = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 20))!
        let monthFrames = [
            DateCellFrame(date: dropDate, frameGlobal: CGRect(x: 240, y: 80, width: 60, height: 60))
        ]
        let firstPoint = CGPoint(x: 260, y: 100)
        let secondPoint = CGPoint(x: 268, y: 108)

        beginDrag(coordinator, item: item)
        coordinator.updateActiveDrag(pointerGlobal: movedPointer)
        claimSuccess(coordinator)
        coordinator.updateCalendarFrames(monthFrames, scope: .month)
        coordinator.updateVisibleScope(.month)

        waitForCleanup()

        coordinator.updateGlobalDrag(pointerGlobal: firstPoint)
        let firstPresentation = coordinator.overlayPresentation
        let firstFrame = coordinator.rootOverlayFrameLocal

        coordinator.updateGlobalDrag(pointerGlobal: secondPoint)

        XCTAssertEqual(coordinator.snapshot.activeDate, dropDate.startOfDay)
        XCTAssertEqual(coordinator.overlayPresentation, firstPresentation)
        XCTAssertEqual(coordinator.rootOverlayFrameLocal, firstFrame)
    }

    func testCapturedCancellationInCalendarScopeCanStillCommitGlobalDrop() {
        let coordinator = makeCoordinator(
            overlayTimings: DragOverlayAnimationTimings(
                liftDurationMs: 1,
                scopeHoldDurationMs: 1,
                pillTransitionDurationMs: 1,
                landingDurationMs: 1
            )
        )
        let item = makeItem()
        let dropDate = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 20))!
        let dropPoint = CGPoint(x: 260, y: 100)
        let monthFrames = [
            DateCellFrame(date: dropDate, frameGlobal: CGRect(x: 240, y: 80, width: 60, height: 60))
        ]

        beginDrag(coordinator, item: item)
        coordinator.updateActiveDrag(pointerGlobal: movedPointer)
        claimSuccess(coordinator)
        coordinator.updateCalendarFrames(monthFrames, scope: .month)
        coordinator.updateVisibleScope(.month)
        coordinator.updateGlobalDrag(pointerGlobal: dropPoint)

        XCTAssertTrue(coordinator.snapshot.droppable)
        XCTAssertTrue(coordinator.shouldTreatCapturedTouchCancellationAsDrop(sceneIsActive: true))
        XCTAssertFalse(coordinator.shouldTreatCapturedTouchCancellationAsDrop(sceneIsActive: false))
    }

    func testCapturedCancellationInRootOwnedDayScopeCanStillCommitDrop() {
        let coordinator = makeCoordinator()

        beginDrag(coordinator, item: makeItem())
        coordinator.updateActiveDrag(pointerGlobal: movedPointer)
        claimSuccess(coordinator)

        XCTAssertEqual(coordinator.snapshot.currentScope, .day)
        XCTAssertTrue(coordinator.shouldTreatCapturedTouchCancellationAsDrop(sceneIsActive: true))
    }

    func testCapturedCancellationInLocalDayScopeNeverBecomesGlobalDrop() {
        let coordinator = makeCoordinator()

        beginDrag(coordinator, item: makeItem())
        coordinator.updateActiveDrag(pointerGlobal: movedPointer)

        XCTAssertEqual(coordinator.snapshot.currentScope, .day)
        XCTAssertFalse(coordinator.shouldTreatCapturedTouchCancellationAsDrop(sceneIsActive: true))
    }

    func testDayEdgeHoverResolverDetectsOnlyTimelineEdgeBands() {
        let frame = CGRect(x: 52, y: 120, width: 280, height: 1440)

        XCTAssertEqual(
            DragDayEdgeHoverResolver.direction(
                pointerGlobal: CGPoint(x: 60, y: 240),
                timelineFrameGlobal: frame,
                edgeInset: 24
            ),
            .previous
        )
        XCTAssertEqual(
            DragDayEdgeHoverResolver.direction(
                pointerGlobal: CGPoint(x: 324, y: 240),
                timelineFrameGlobal: frame,
                edgeInset: 24
            ),
            .next
        )
        XCTAssertNil(
            DragDayEdgeHoverResolver.direction(
                pointerGlobal: CGPoint(x: 180, y: 240),
                timelineFrameGlobal: frame,
                edgeInset: 24
            )
        )
        XCTAssertNil(
            DragDayEdgeHoverResolver.direction(
                pointerGlobal: CGPoint(x: 60, y: 80),
                timelineFrameGlobal: frame,
                edgeInset: 24
            )
        )
    }

    func testDayViewModelIgnoresStaleLoadResults() async {
        let service = StubEventKitService()
        let viewModel = DayViewModel()
        let firstDate = selectedDate.startOfDay
        let secondDate = selectedDate.adding(days: 1).startOfDay
        let firstItem = makeItem()
        let secondItem = makeItem(
            id: "event-2",
            startDate: Calendar.current.date(
                from: DateComponents(year: secondDate.year, month: secondDate.month, day: secondDate.day, hour: 9)
            )!,
            endDate: Calendar.current.date(
                from: DateComponents(year: secondDate.year, month: secondDate.month, day: secondDate.day, hour: 10)
            )!
        )

        service.stubbedItems[firstDate] = [firstItem]
        service.stubbedItems[secondDate] = [secondItem]
        service.stubbedDelayNs[firstDate] = 80_000_000
        service.stubbedDelayNs[secondDate] = 10_000_000

        async let firstLoad: Void = viewModel.loadItems(for: firstDate, service: service)
        try? await Task.sleep(nanoseconds: 5_000_000)
        async let secondLoad: Void = viewModel.loadItems(for: secondDate, service: service)

        _ = await (firstLoad, secondLoad)

        XCTAssertEqual(viewModel.loadedDate, secondDate)
        XCTAssertEqual(viewModel.items.map(\.id), [secondItem.id])
        XCTAssertEqual(viewModel.timedItems.map(\.id), [secondItem.id])
    }

    func testProjectedTimedItemsReplaceOriginalSlotForSameDayPendingMove() {
        let viewModel = DayViewModel()
        let item = makeItem()
        let movedStart = Calendar.current.date(
            from: DateComponents(year: 2026, month: 4, day: 16, hour: 11)
        )!
        let movedEnd = Calendar.current.date(
            from: DateComponents(year: 2026, month: 4, day: 16, hour: 12)
        )!

        viewModel.timedItems = [item]
        viewModel.registerPendingTimedItemMove(
            item: item,
            newStart: movedStart,
            newEnd: movedEnd
        )

        let projected = viewModel.projectedTimedItems(for: selectedDate)

        XCTAssertEqual(projected.count, 1)
        XCTAssertEqual(projected.first?.id, item.id)
        XCTAssertEqual(projected.first?.startDate, movedStart)
        XCTAssertEqual(projected.first?.endDate, movedEnd)
    }

    func testProjectedTimedItemsMoveAcrossDatesBeforeReload() {
        let viewModel = DayViewModel()
        let item = makeItem()
        let targetDate = Calendar.current.date(
            from: DateComponents(year: 2026, month: 4, day: 17, hour: 11)
        )!
        let targetEnd = Calendar.current.date(
            from: DateComponents(year: 2026, month: 4, day: 17, hour: 12)
        )!

        viewModel.timedItems = [item]
        viewModel.registerPendingTimedItemMove(
            item: item,
            newStart: targetDate,
            newEnd: targetEnd
        )

        XCTAssertTrue(viewModel.projectedTimedItems(for: selectedDate).isEmpty)

        let projectedTarget = viewModel.projectedTimedItems(for: targetDate)
        XCTAssertEqual(projectedTarget.count, 1)
        XCTAssertEqual(projectedTarget.first?.id, item.id)
        XCTAssertEqual(projectedTarget.first?.startDate, targetDate)
        XCTAssertEqual(projectedTarget.first?.endDate, targetEnd)
    }

    func testLoadingTargetDayClearsPendingTimedItemMoveWhenStoreCatchesUp() async {
        let service = StubEventKitService()
        let viewModel = DayViewModel()
        let item = makeItem()
        let targetDate = Calendar.current.date(
            from: DateComponents(year: 2026, month: 4, day: 17, hour: 11)
        )!
        let targetEnd = Calendar.current.date(
            from: DateComponents(year: 2026, month: 4, day: 17, hour: 12)
        )!
        let movedItem = makeItem(
            id: item.id,
            startDate: targetDate,
            endDate: targetEnd
        )

        viewModel.registerPendingTimedItemMove(
            item: item,
            newStart: targetDate,
            newEnd: targetEnd
        )
        service.stubbedItems[targetDate.startOfDay] = [movedItem]

        await viewModel.loadItems(for: targetDate, service: service)

        XCTAssertNil(viewModel.pendingTimedItemMove)
        XCTAssertEqual(viewModel.timedItems.map(\.id), [movedItem.id])
    }

    func testDayEdgeHoverResolverPerformance() {
        let frame = CGRect(x: 52, y: 120, width: 280, height: 1440)
        let points = [
            CGPoint(x: 60, y: 180),
            CGPoint(x: 178, y: 240),
            CGPoint(x: 324, y: 360),
            CGPoint(x: 178, y: 520)
        ]

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            var hitCount = 0
            for index in 0..<200_000 {
                let point = points[index % points.count]
                if DragDayEdgeHoverResolver.direction(
                    pointerGlobal: point,
                    timelineFrameGlobal: frame,
                    edgeInset: 24
                ) != nil {
                    hitCount += 1
                }
            }
            XCTAssertGreaterThan(hitCount, 0)
        }
    }

    func testLocalDayTerminationPolicyAcceptsOnlyActiveDaySessions() {
        XCTAssertTrue(
            DayDragTerminationPolicy.shouldAcceptLocalDayTermination(
                hasActiveSession: true,
                scope: .day
            )
        )
        XCTAssertFalse(
            DayDragTerminationPolicy.shouldAcceptLocalDayTermination(
                hasActiveSession: false,
                scope: .day
            )
        )
        XCTAssertFalse(
            DayDragTerminationPolicy.shouldAcceptLocalDayTermination(
                hasActiveSession: true,
                scope: .month
            )
        )
    }

    func testRootCancelledTerminationIsIgnoredOnlyInDayScope() {
        XCTAssertFalse(
            DayDragTerminationPolicy.shouldHandleTermination(
                source: .root,
                termination: .cancelled,
                scope: .day,
                isRootClaimAcquired: false
            )
        )
        XCTAssertTrue(
            DayDragTerminationPolicy.shouldHandleTermination(
                source: .root,
                termination: .ended,
                scope: .day,
                isRootClaimAcquired: false
            )
        )
        XCTAssertTrue(
            DayDragTerminationPolicy.shouldHandleTermination(
                source: .root,
                termination: .cancelled,
                scope: .month,
                isRootClaimAcquired: false
            )
        )
        XCTAssertTrue(
            DayDragTerminationPolicy.shouldHandleTermination(
                source: .root,
                termination: .cancelled,
                scope: .day,
                isRootClaimAcquired: true
            )
        )
        XCTAssertTrue(
            DayDragTerminationPolicy.shouldHandleTermination(
                source: .local,
                termination: .cancelled,
                scope: .day,
                isRootClaimAcquired: false
            )
        )
    }

    func testTouchCaptureInstallerAttachesRecognizerToWindowSurface() {
        let controller = DragSessionTouchCaptureController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let hostView = UIView(frame: window.bounds)
        let installerView = DragSessionTouchCaptureInstallerView(frame: hostView.bounds)
        installerView.controller = controller

        hostView.addSubview(installerView)
        window.addSubview(hostView)
        installerView.installRecognizerIfNeeded()
        drainMainQueue()

        let installedRecognizer = window.gestureRecognizers?.first {
            $0 is DragSessionTouchCaptureRecognizer
        }

        XCTAssertNotNil(installedRecognizer)
        XCTAssertFalse(hostView.gestureRecognizers?.contains(where: { $0 === installedRecognizer }) ?? false)
    }

    func testTouchCaptureControllerReusesSameRecognizerAcrossHostChanges() {
        let controller = DragSessionTouchCaptureController()
        let firstWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let secondWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))

        controller.installRecognizer(on: firstWindow)
        let initialRecognizer = firstWindow.gestureRecognizers?.first {
            $0 is DragSessionTouchCaptureRecognizer
        }

        controller.installRecognizer(on: secondWindow)
        let movedRecognizer = secondWindow.gestureRecognizers?.first {
            $0 is DragSessionTouchCaptureRecognizer
        }

        XCTAssertNotNil(initialRecognizer)
        XCTAssertTrue(initialRecognizer === movedRecognizer)
        XCTAssertFalse(firstWindow.gestureRecognizers?.contains(where: { $0 === initialRecognizer }) ?? false)
    }

    func testTouchCaptureRecognizerDoesNotCancelSourceTouches() {
        let recognizer = DragSessionTouchCaptureRecognizer()

        XCTAssertFalse(recognizer.cancelsTouchesInView)
    }

    private var selectedDate: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 16))!
    }

    private var sourceFrame: CGRect {
        CGRect(x: 100, y: 200, width: 180, height: 60)
    }

    private var startPointer: CGPoint {
        CGPoint(x: 120, y: 210)
    }

    private var movedPointer: CGPoint {
        CGPoint(x: 180, y: 330)
    }

    private var movedStartDate: Date {
        Calendar.current.date(
            from: DateComponents(year: 2026, month: 4, day: 16, hour: 3, minute: 30)
        )!
    }

    private var movedEndDate: Date {
        Calendar.current.date(
            from: DateComponents(year: 2026, month: 4, day: 16, hour: 4, minute: 30)
        )!
    }

    private func makeCoordinator(
        restoreAnimationMs: Int = 220,
        overlayTimings: DragOverlayAnimationTimings = .baseline,
        traceRecorder: DragHandoffTraceRecorder? = nil
    ) -> CalendarDragCoordinator {
        var params = DragSessionParams.baseline
        params.restoreAnimationMs = restoreAnimationMs

        let coordinator = CalendarDragCoordinator(
            params: params,
            overlayTimings: overlayTimings,
            traceSink: traceRecorder?.sink ?? .disabled
        )
        coordinator.updateVisibleDay(selectedDate)
        coordinator.updateTimelineLayout(
            frameGlobal: CGRect(x: 52, y: 120, width: 280, height: 1440),
            scrollOffsetY: 0
        )
        return coordinator
    }

    private func beginDrag(
        _ coordinator: CalendarDragCoordinator,
        item: TicItem
    ) {
        coordinator.beginDayDrag(
            item: item,
            sourceFrameGlobal: sourceFrame,
            pointerGlobal: startPointer,
            claimTimestamp: timestamp(frame: 10, uptimeMs: 100)
        )
    }

    private func claimSuccess(
        _ coordinator: CalendarDragCoordinator,
        frame: Int = 11,
        uptimeMs: Int = 116
    ) {
        let token = currentToken(for: coordinator)
        XCTAssertEqual(
            coordinator.applyRootClaimSuccess(
                for: token,
                at: timestamp(frame: frame, uptimeMs: uptimeMs)
            ),
            .applied
        )
    }

    private func currentToken(for coordinator: CalendarDragCoordinator) -> DragTouchClaimToken {
        guard let token = coordinator.currentHandoffToken else {
            XCTFail("Missing current touch claim token")
            return DragTouchClaimToken(rawValue: .max)
        }
        return token
    }

    private func timestamp(frame: Int, uptimeMs: Int) -> DragTouchClaimTimestamp {
        DragTouchClaimTimestamp(frameIndex: frame, uptimeMs: uptimeMs)
    }

    private func waitForRestoreCleanup() {
        waitForCleanup()
    }

    private func waitForCleanup() {
        wait(forSeconds: 0.05)
    }

    private func wait(forSeconds seconds: TimeInterval) {
        let expectation = expectation(description: "delayed work")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: max(seconds * 4, 0.2))
    }

    private func drainMainQueue() {
        let expectation = expectation(description: "drain main queue")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    private func expectedStartDate(
        on date: Date,
        hour: Int,
        minute: Int
    ) -> Date {
        Calendar.current.date(
            from: DateComponents(
                year: date.year,
                month: date.month,
                day: date.day,
                hour: hour,
                minute: minute
            )
        )!
    }

    private func makeItem() -> TicItem {
        makeItem(
            id: "event-1",
            startDate: Calendar.current.date(
                from: DateComponents(year: 2026, month: 4, day: 16, hour: 2, minute: 0)
            )!,
            endDate: Calendar.current.date(
                from: DateComponents(year: 2026, month: 4, day: 16, hour: 3, minute: 0)
            )!
        )
    }

    private func makeItem(
        id: String,
        startDate: Date,
        endDate: Date
    ) -> TicItem {
        return TicItem(
            id: id,
            title: "Drag session",
            notes: nil,
            startDate: startDate,
            endDate: endDate,
            isAllDay: false,
            isCompleted: false,
            isReminder: false,
            hasTime: true,
            calendarTitle: "Work",
            calendarColor: UIColor.orange.cgColor,
            recurrenceRule: nil,
            ekEvent: nil,
            ekReminder: nil
        )
    }
}

private final class StubEventKitService: EventKitService {
    var stubbedItems: [Date: [TicItem]] = [:]
    var stubbedDelayNs: [Date: UInt64] = [:]

    override func fetchAllItems(for date: Date) async -> [TicItem] {
        let targetDate = date.startOfDay
        if let delay = stubbedDelayNs[targetDate] {
            try? await Task.sleep(nanoseconds: delay)
        }
        return stubbedItems[targetDate] ?? []
    }
}
