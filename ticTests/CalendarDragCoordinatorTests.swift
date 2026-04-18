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
        let startDate = Calendar.current.date(
            from: DateComponents(year: 2026, month: 4, day: 16, hour: 2, minute: 0)
        )!
        let endDate = Calendar.current.date(
            from: DateComponents(year: 2026, month: 4, day: 16, hour: 3, minute: 0)
        )!

        return TicItem(
            id: "event-1",
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
