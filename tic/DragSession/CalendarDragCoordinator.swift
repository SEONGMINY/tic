import Foundation
import CoreGraphics
import Observation
import SwiftUI

struct DragSessionCommit {
    let itemId: String
    let start: Date
    let end: Date
}

enum DragDropOwner: Equatable {
    case localDayTimeline
    case rootCoordinator

    static func nextOwner(
        afterShowing scope: DragSessionScope,
        currentOwner: DragDropOwner
    ) -> DragDropOwner {
        if currentOwner == .rootCoordinator || scope != .day {
            return .rootCoordinator
        }
        return .localDayTimeline
    }

    func handlesGlobalDrop(hasActiveSession: Bool) -> Bool {
        hasActiveSession && self == .rootCoordinator
    }

    func handlesLocalDrop(
        in scope: DragSessionScope,
        hasActiveSession: Bool
    ) -> Bool {
        hasActiveSession && self == .localDayTimeline && scope == .day
    }
}

enum DragSessionTermination: Equatable {
    case committed
    case cancelled
    case invalidDropRestored

    var clearsEditingState: Bool {
        switch self {
        case .committed:
            return true
        case .cancelled, .invalidDropRestored:
            return false
        }
    }
}

@Observable
final class CalendarDragCoordinator {
    private(set) var engine: DragSessionEngine
    private let overlayTimings: DragOverlayAnimationTimings
    private let traceSink: DragHandoffTraceSink
    private(set) var draggedItem: TicItem?
    private(set) var placeholderItemId: String?
    private(set) var displayedOverlayFrameGlobal: CGRect?
    private(set) var overlayPresentation: DragOverlayPresentation = .inactive
    private(set) var handoffState: DragOwnershipHandoffState = .idle
    private(set) var lastSessionTermination: DragSessionTermination?
    private(set) var sessionTerminationCount = 0

    private var rootFrameGlobal: CGRect = .zero
    private var timelineLayout: DragTimelineLayout?
    private var visibleDayDate: Date = .now.startOfDay
    private var visibleScope: DragSessionScope = .day
    private var calendarFramesByScope: [DragSessionScope: [DateCellFrame]] = [:]
    private var calendarPillWidth: CGFloat = DragOverlayPresentationResolver.defaultPillWidth
    private var phaseAdvanceWorkItem: DispatchWorkItem?
    private var restoreCleanupWorkItem: DispatchWorkItem?
    private var landingCleanupWorkItem: DispatchWorkItem?
    private var pendingLandingCommit: DragSessionCommit?
    private var touchClaimHandoff = DragTouchClaimHandoff()
    private var pendingTouchRelayToken: DragTouchClaimToken?
    private var claimFrameIndex = 0

    init(
        params: DragSessionParams = .baseline,
        overlayTimings: DragOverlayAnimationTimings = .baseline,
        traceSink: DragHandoffTraceSink = .disabled
    ) {
        self.engine = DragSessionEngine(params: params)
        self.overlayTimings = overlayTimings
        self.traceSink = traceSink
    }

    var overlayItem: TicItem? {
        guard let draggedItem else { return nil }
        if let pendingLandingCommit {
            return draggedItem.updatingDates(
                startDate: pendingLandingCommit.start,
                endDate: pendingLandingCommit.end
            )
        }
        if let finalDropResult = snapshot.finalDropResult,
           let absoluteDates = DragSessionGeometry.absoluteDates(from: finalDropResult) {
            return draggedItem.updatingDates(
                startDate: absoluteDates.start,
                endDate: absoluteDates.end
            )
        }
        guard let durationMinute = snapshot.durationMinute,
              let dropResult = DragSessionGeometry.buildFinalDropResult(
                dateCandidate: snapshot.dropCandidateDate,
                minuteCandidate: snapshot.minuteCandidate,
                durationMinute: durationMinute,
                minimumDurationMinute: engine.params.minimumDurationMinute
              ),
              let absoluteDates = DragSessionGeometry.absoluteDates(from: dropResult) else {
            return draggedItem
        }

        return draggedItem.updatingDates(
            startDate: absoluteDates.start,
            endDate: absoluteDates.end
        )
    }

    var rootOverlayItem: TicItem? {
        guard isRootOverlayVisible else { return nil }
        return overlayItem
    }

    var overlayFrameLocal: CGRect? {
        guard let displayedOverlayFrameGlobal else { return nil }
        guard rootFrameGlobal != .zero else { return displayedOverlayFrameGlobal }
        return CGRect(
            x: displayedOverlayFrameGlobal.minX - rootFrameGlobal.minX,
            y: displayedOverlayFrameGlobal.minY - rootFrameGlobal.minY,
            width: displayedOverlayFrameGlobal.width,
            height: displayedOverlayFrameGlobal.height
        )
    }

    var rootOverlayFrameLocal: CGRect? {
        guard isRootOverlayVisible else { return nil }
        return overlayFrameLocal
    }

    var isSessionVisible: Bool {
        displayedOverlayFrameGlobal != nil && draggedItem != nil
    }

    var isRootOverlayVisible: Bool {
        switch handoffState.phase {
        case .rootClaimAcquired, .landing:
            return true
        case .rootClaimPending:
            return visibleScope != .day
        case .restoring:
            return currentHandoffOwner == .root || visibleScope != .day
        case .idle, .localPreview:
            return false
        }
    }

    var snapshot: DragSessionSnapshot {
        engine.snapshot
    }

    var dropOwner: DragDropOwner {
        handoffState.dropOwner
    }

    var currentHandoffToken: DragTouchClaimToken? {
        handoffState.token
    }

    var currentHandoffOwner: DragTouchClaimOwner {
        handoffState.owner
    }

    var currentClaimSnapshot: DragTouchClaimSnapshot? {
        handoffState.claimSnapshot
    }

    var hasPendingTouchRelay: Bool {
        handoffState.phase == .rootClaimPending
            && pendingTouchRelayToken == handoffState.token
    }

    var sessionItem: TicItem? {
        draggedItem
    }

    var isGestureSessionActive: Bool {
        guard draggedItem != nil else { return false }
        guard pendingLandingCommit == nil else { return false }

        switch snapshot.state {
        case .pressing, .dragReady, .draggingTimeline, .draggingCalendar:
            return true
        case .idle, .restoring:
            return false
        }
    }

    var shouldHandleDragGlobally: Bool {
        handoffState.canHandleGlobalDrag && isGestureSessionActive
    }

    var shouldHandleDropLocally: Bool {
        handoffState.canHandleLocalDayDrop
            && isGestureSessionActive
            && snapshot.currentScope == .day
    }

    var hasActiveSession: Bool {
        draggedItem != nil || snapshot.source != nil
    }

    func sourcePlaceholderOpacity(for itemId: String?) -> Double? {
        guard let itemId,
              itemId == placeholderItemId,
              hasActiveSession,
              handoffState.showsPlaceholder else {
            return nil
        }
        return overlayPresentation.sourcePlaceholderOpacity
    }

    func localPreviewFrameGlobal(for itemId: String?) -> CGRect? {
        guard let itemId,
              draggedItem?.id == itemId,
              currentHandoffOwner == .localPreview,
              visibleScope == .day,
              handoffState.phase != .idle else {
            return nil
        }
        return displayedOverlayFrameGlobal
    }

    func shouldSuppressInlineSourceBlock(for itemId: String?) -> Bool {
        guard let itemId,
              itemId == placeholderItemId,
              hasActiveSession else {
            return false
        }

        switch handoffState.phase {
        case .rootClaimPending, .restoring:
            return visibleScope != .day
        case .idle, .localPreview, .rootClaimAcquired, .landing:
            return false
        }
    }

    func updateRootFrame(_ frameGlobal: CGRect) {
        rootFrameGlobal = frameGlobal
    }

    func updateVisibleScope(_ scope: CalendarScope) {
        let dragScope = map(scope)
        visibleScope = dragScope
        guard engine.snapshot.source != nil else { return }
        let previousActiveDate = snapshot.activeDate

        if isCommitLandingPendingOrRunning {
            maybeStartPendingLandingIfPossible()
            return
        }

        engine.updateScope(
            dragScope,
            visibleDayDate: visibleDayDate,
            pointerGlobal: engine.snapshot.pointerGlobal,
            timelineLayout: timelineLayout,
            calendarFrames: hoverEnabledCalendarFrames(for: dragScope)
        )
        updatePresentationForScopeChange(to: dragScope)
        syncDisplayedOverlayFrame(
            animated: shouldAnimateCalendarPillFrameChange(
                scope: dragScope,
                previousActiveDate: previousActiveDate
            )
        )
    }

    func updateVisibleDay(_ date: Date) {
        visibleDayDate = date.startOfDay
        if isCommitLandingPendingOrRunning {
            maybeStartPendingLandingIfPossible()
            return
        }
        guard engine.snapshot.dragStarted else { return }
        guard let pointer = engine.snapshot.pointerGlobal else { return }
        engine.updateScope(
            .day,
            visibleDayDate: visibleDayDate,
            pointerGlobal: pointer,
            timelineLayout: timelineLayout
        )
        syncDisplayedOverlayFrame()
    }

    func updateCalendarFrames(
        _ frames: [DateCellFrame],
        scope: DragSessionScope
    ) {
        calendarFramesByScope[scope] = frames

        if isCommitLandingPendingOrRunning {
            return
        }

        guard engine.snapshot.dragStarted,
              engine.snapshot.currentScope == scope,
              let pointer = engine.snapshot.pointerGlobal else {
            return
        }
        let previousActiveDate = snapshot.activeDate

        engine.updateScope(
            scope,
            visibleDayDate: visibleDayDate,
            pointerGlobal: pointer,
            timelineLayout: timelineLayout,
            calendarFrames: hoverEnabledCalendarFrames(for: scope)
        )
        syncDisplayedOverlayFrame(
            animated: shouldAnimateCalendarPillFrameChange(
                scope: scope,
                previousActiveDate: previousActiveDate
            )
        )
    }

    func updateTimelineLayout(
        frameGlobal: CGRect,
        scrollOffsetY: CGFloat,
        hourHeight: CGFloat = 60
    ) {
        timelineLayout = DragTimelineLayout(
            frameGlobal: frameGlobal,
            scrollOffsetY: scrollOffsetY,
            hourHeight: hourHeight
        )

        if isCommitLandingPendingOrRunning {
            maybeStartPendingLandingIfPossible()
            return
        }

        guard engine.snapshot.currentScope == .day,
              engine.snapshot.dragStarted,
              let pointer = engine.snapshot.pointerGlobal else { return }

        engine.updateScope(
            .day,
            visibleDayDate: visibleDayDate,
            pointerGlobal: pointer,
            timelineLayout: timelineLayout
        )
        syncDisplayedOverlayFrame()
    }

    @discardableResult
    func beginDayDrag(
        item: TicItem,
        sourceFrameGlobal: CGRect,
        pointerGlobal: CGPoint,
        claimTimestamp: DragTouchClaimTimestamp? = nil
    ) -> DragTouchClaimToken? {
        startLocalPreviewDrag(
            item: item,
            sourceFrameGlobal: sourceFrameGlobal,
            pointerGlobal: pointerGlobal
        )
        return requestRootClaim(at: claimTimestamp)
    }

    func startLocalPreviewDrag(
        item: TicItem,
        sourceFrameGlobal: CGRect,
        pointerGlobal: CGPoint
    ) {
        guard let startDate = item.startDate,
              let endDate = item.endDate else {
            return
        }

        phaseAdvanceWorkItem?.cancel()
        landingCleanupWorkItem?.cancel()
        restoreCleanupWorkItem?.cancel()
        let source = DragSessionSource(
            itemId: item.id,
            sourceDate: startDate,
            sourceStartMinute: minuteOfDay(for: startDate),
            sourceEndMinute: minuteOfDay(for: endDate),
            originalFrameGlobal: sourceFrameGlobal
        )

        engine.touchStart(source: source, at: pointerGlobal, scope: .day)
        let timestampMs = nowTimestampMs()
        engine.longPressRecognized(timestampMs: timestampMs)
        engine.dragMoved(
            to: pointerGlobal,
            timestampMs: timestampMs,
            timelineLayout: timelineLayout
        )

        draggedItem = item
        placeholderItemId = item.id
        visibleScope = .day
        calendarPillWidth = resolvedCalendarPillWidth(from: sourceFrameGlobal)
        overlayPresentation = resolvedPresentation(for: .lifted)
        handoffState = DragOwnershipHandoffState(
            phase: .localPreview,
            token: nil,
            owner: .localPreview,
            restoreReason: nil,
            claimSnapshot: nil
        )
        syncDisplayedOverlayFrame()
        scheduleLiftAdvance()
    }

    @discardableResult
    func requestRootClaim(
        at timestamp: DragTouchClaimTimestamp? = nil
    ) -> DragTouchClaimToken? {
        guard draggedItem != nil else { return nil }

        switch handoffState.phase {
        case .localPreview:
            let token = touchClaimHandoff.beginLocalPreview(at: timestamp ?? nextClaimTimestamp())
            pendingTouchRelayToken = nil
            handoffState = resolvedHandoffState(for: .rootClaimPending)
            traceSink.record(.dragStart(token: token))
            return token
        case .rootClaimPending, .rootClaimAcquired, .landing, .restoring:
            return handoffState.token
        case .idle:
            return nil
        }
    }

    @discardableResult
    func applyRootClaimSuccess(
        for token: DragTouchClaimToken,
        at timestamp: DragTouchClaimTimestamp? = nil
    ) -> DragTouchClaimEventResult {
        let result = touchClaimHandoff.reportClaimSucceeded(
            for: token,
            at: timestamp ?? nextClaimTimestamp()
        )

        switch result {
        case .applied:
            pendingTouchRelayToken = nil
            handoffState = resolvedHandoffState(for: .rootClaimAcquired)
            traceSink.record(.rootClaimSuccess(token: token))
            if let claimLatencyMs = touchClaimHandoff.snapshot.claimLatencyMs {
                traceSink.record(.claimLatencyMs(claimLatencyMs))
            }
            activateCalendarHoverIfNeeded()
            updatePresentationAfterRootClaimSuccess()
        case .ignored:
            beginRestoreAfterFinishedClaimIfNeeded()
        case .staleIgnored:
            break
        }

        return result
    }

    @discardableResult
    func applyRootClaimCancellation(
        for token: DragTouchClaimToken,
        at timestamp: DragTouchClaimTimestamp? = nil
    ) -> DragTouchClaimEventResult {
        let result = touchClaimHandoff.reportClaimCancelled(
            for: token,
            at: timestamp ?? nextClaimTimestamp()
        )

        if result == .applied {
            pendingTouchRelayToken = nil
            recordRestoreReason(.cancelled)
            beginRestoreAfterClaimFailure()
        }
        return result
    }

    @discardableResult
    func applyRootClaimEnd(
        for token: DragTouchClaimToken
    ) -> DragTouchClaimEventResult {
        let result = touchClaimHandoff.reportClaimEnded(for: token)
        if result == .applied {
            pendingTouchRelayToken = nil
        }
        return result
    }

    @discardableResult
    func expirePendingRootClaimIfNeeded(
    ) -> DragTouchClaimEventResult {
        expirePendingRootClaimIfNeeded(at: nextClaimTimestamp())
    }

    @discardableResult
    func expirePendingRootClaimIfNeeded(
        at timestamp: DragTouchClaimTimestamp
    ) -> DragTouchClaimEventResult {
        let result = touchClaimHandoff.expirePendingClaimIfNeeded(at: timestamp)
        if result == .applied {
            pendingTouchRelayToken = nil
            if let token = touchClaimHandoff.snapshot.token {
                traceSink.record(.rootClaimTimeout(token: token))
            }
            recordRestoreReason(.timeout)
            beginRestoreAfterClaimFailure()
        }
        return result
    }

    func updateDayDrag(pointerGlobal: CGPoint) {
        guard isGestureSessionActive else { return }
        engine.dragMoved(
            to: pointerGlobal,
            timestampMs: nowTimestampMs(),
            timelineLayout: timelineLayout
        )
        syncDisplayedOverlayFrame()
    }

    func updateActiveDrag(pointerGlobal: CGPoint) {
        guard isGestureSessionActive else { return }

        switch engine.snapshot.currentScope {
        case .day:
            updateDayDrag(pointerGlobal: pointerGlobal)
        case .month, .year:
            let previousActiveDate = snapshot.activeDate
            engine.dragMoved(
                to: pointerGlobal,
                timestampMs: nowTimestampMs(),
                calendarFrames: hoverEnabledCalendarFrames(for: engine.snapshot.currentScope)
            )
            syncDisplayedOverlayFrame(
                animated: shouldAnimateCalendarPillFrameChange(
                    scope: engine.snapshot.currentScope,
                    previousActiveDate: previousActiveDate
                )
            )
        }
    }

    func updateGlobalDrag(pointerGlobal: CGPoint) {
        guard shouldHandleDragGlobally else { return }
        updateActiveDrag(pointerGlobal: pointerGlobal)
    }

    func attachTouchTrackingRelay(for token: DragTouchClaimToken) {
        guard handoffState.phase == .rootClaimPending,
              handoffState.token == token else {
            return
        }
        pendingTouchRelayToken = token
    }

    func updateRelayedTouchMove(
        for token: DragTouchClaimToken,
        pointerGlobal: CGPoint
    ) {
        guard handoffState.token == token else { return }

        if handoffState.isRootClaimAcquired {
            updateGlobalDrag(pointerGlobal: pointerGlobal)
            return
        }

        guard hasPendingTouchRelay,
              visibleScope != .day,
              isGestureSessionActive else {
            return
        }

        engine.dragMoved(
            to: pointerGlobal,
            timestampMs: nowTimestampMs(),
            calendarFrames: []
        )
        syncDisplayedOverlayFrame()
    }

    func shouldPromoteRelayedTouchToRootClaim(
        for token: DragTouchClaimToken
    ) -> Bool {
        hasPendingTouchRelay
            && handoffState.token == token
            && visibleScope != .day
    }

    func completeLocalDrag() -> DragSessionCommit? {
        guard shouldHandleDropLocally else { return nil }
        return completeActiveDrag()
    }

    func completeTimelineDrop() -> DragSessionCommit? {
        guard isGestureSessionActive else { return nil }
        guard snapshot.currentScope == .day else { return nil }
        return completeActiveDrag()
    }

    func completeGlobalDrag() -> DragSessionCommit? {
        guard shouldHandleDragGlobally else { return nil }
        return completeActiveDrag()
    }

    func cancelDrag() {
        guard isCommitLandingPendingOrRunning == false else { return }
        if let token = handoffState.token {
            _ = touchClaimHandoff.reportClaimCancelled(
                for: token,
                at: nextClaimTimestamp()
            )
        }
        if handoffState.phase != .idle && handoffState.phase != .restoring {
            recordRestoreReason(.cancelled)
        }
        let snapshot = engine.cancel(timestampMs: nowTimestampMs())
        handoffState = resolvedHandoffState(for: .restoring)
        updatePresentation(to: .restoring, animated: true)
        syncDisplayedOverlayFrame()
        if snapshot.state == .restoring {
            scheduleRestoreCleanup()
        }
    }

    func isShowingPlaceholder(for itemId: String?) -> Bool {
        guard let itemId else { return false }
        return placeholderItemId == itemId && handoffState.showsPlaceholder
    }

    private func completeActiveDrag() -> DragSessionCommit? {
        guard let draggedItem else { return nil }
        if engine.snapshot.state == .pressing || engine.snapshot.state == .dragReady {
            cancelDrag()
            return nil
        }
        let snapshot = engine.drop(timestampMs: nowTimestampMs())
        syncDisplayedOverlayFrame(animated: overlayPresentation.style == .calendarPill && snapshot.activeDate != nil)

        if let finalDropResult = snapshot.finalDropResult,
           let absoluteDates = DragSessionGeometry.absoluteDates(from: finalDropResult) {
            let commit = DragSessionCommit(
                itemId: draggedItem.id,
                start: absoluteDates.start,
                end: absoluteDates.end
            )
            pendingLandingCommit = commit
            maybeStartPendingLandingIfPossible()
            return commit
        }

        if snapshot.state == .restoring {
            recordRestoreReason(.invalidDrop)
            handoffState = resolvedHandoffState(for: .restoring)
            updatePresentation(to: .restoring, animated: true)
            scheduleRestoreCleanup()
        }
        return nil
    }

    private func scheduleRestoreCleanup() {
        phaseAdvanceWorkItem?.cancel()
        restoreCleanupWorkItem?.cancel()
        landingCleanupWorkItem?.cancel()
        if let restoreTarget = engine.snapshot.restoreTargetFrameGlobal {
            withAnimation(.easeInOut(duration: Double(engine.params.restoreAnimationMs) / 1000.0)) {
                displayedOverlayFrameGlobal = restoreTarget
            }
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.engine.finishRestore()
            self.finishSession(self.terminationForRestoredSession())
        }
        restoreCleanupWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Double(engine.params.restoreAnimationMs) / 1000.0,
            execute: workItem
        )
    }

    private func finishSession(_ termination: DragSessionTermination) {
        endCurrentHandoffSessionIfNeeded()
        lastSessionTermination = termination
        sessionTerminationCount += 1
        resetSession()
    }

    private func terminationForRestoredSession() -> DragSessionTermination {
        switch engine.snapshot.invalidReason {
        case .invalidDrop:
            return .invalidDropRestored
        case .cancelledByEvent, .falseStartPreLongPress, nil:
            return .cancelled
        }
    }

    private func resetSession() {
        phaseAdvanceWorkItem?.cancel()
        phaseAdvanceWorkItem = nil
        restoreCleanupWorkItem?.cancel()
        restoreCleanupWorkItem = nil
        landingCleanupWorkItem?.cancel()
        landingCleanupWorkItem = nil
        engine = DragSessionEngine(params: engine.params)
        draggedItem = nil
        placeholderItemId = nil
        pendingLandingCommit = nil
        pendingTouchRelayToken = nil
        displayedOverlayFrameGlobal = nil
        overlayPresentation = .inactive
        handoffState = .idle
        visibleScope = .day
        calendarPillWidth = DragOverlayPresentationResolver.defaultPillWidth
        calendarFramesByScope[.month] = nil
        calendarFramesByScope[.year] = nil
    }

    private func syncDisplayedOverlayFrame(animated: Bool = false) {
        guard let nextFrame = resolvedDisplayedOverlayFrame() else {
            displayedOverlayFrameGlobal = nil
            return
        }

        if animated {
            withAnimation(.easeOut(duration: Double(overlayTimings.pillTransitionDurationMs) / 1000.0)) {
                displayedOverlayFrameGlobal = nextFrame
            }
        } else {
            withoutAnimation {
                displayedOverlayFrameGlobal = nextFrame
            }
        }
    }

    private func updatePresentationForScopeChange(to scope: DragSessionScope) {
        if scope == .day {
            phaseAdvanceWorkItem?.cancel()
            let nextPhase: DragOverlayVisualPhase =
                overlayPresentation.visualPhase == .lifted ? .lifted : .floating
            updatePresentation(to: nextPhase, animated: overlayPresentation.visualPhase != nextPhase)
            return
        }

        updatePresentation(to: .holding, animated: true)
        if handoffState.isRootClaimAcquired {
            scheduleCalendarPillAdvance(for: scope)
        }
    }

    private func scheduleLiftAdvance() {
        phaseAdvanceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.pendingLandingCommit == nil else { return }
            guard self.snapshot.currentScope == .day else { return }
            guard self.snapshot.dragStarted else { return }
            self.updatePresentation(to: .floating, animated: true)
        }
        phaseAdvanceWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Double(overlayTimings.liftDurationMs) / 1000.0,
            execute: workItem
        )
    }

    private func scheduleCalendarPillAdvance(for scope: DragSessionScope) {
        phaseAdvanceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.pendingLandingCommit == nil else { return }
            guard self.visibleScope == scope else { return }
            guard self.snapshot.currentScope == scope else { return }
            guard self.handoffState.isRootClaimAcquired else { return }
            self.updatePresentation(to: .floating, animated: true)
            self.syncDisplayedOverlayFrame(animated: self.snapshot.activeDate != nil)
        }
        phaseAdvanceWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Double(overlayTimings.scopeHoldDurationMs) / 1000.0,
            execute: workItem
        )
    }

    private func maybeStartPendingLandingIfPossible() {
        guard let pendingLandingCommit else { return }
        guard visibleScope == .day else { return }
        guard visibleDayDate.isSameDay(as: pendingLandingCommit.start) else { return }
        guard let targetFrame = landingTargetFrame(for: pendingLandingCommit) else { return }

        phaseAdvanceWorkItem?.cancel()
        handoffState = resolvedHandoffState(for: .landing)
        updatePresentation(to: .landing, animated: true)
        withAnimation(.spring(duration: Double(overlayTimings.landingDurationMs) / 1000.0, bounce: 0.08)) {
            displayedOverlayFrameGlobal = targetFrame
        }

        let cleanup = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.finishSession(.committed)
        }
        landingCleanupWorkItem?.cancel()
        landingCleanupWorkItem = cleanup
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Double(overlayTimings.landingDurationMs) / 1000.0,
            execute: cleanup
        )
        self.pendingLandingCommit = nil
    }

    private var isCommitLandingPendingOrRunning: Bool {
        pendingLandingCommit != nil || landingCleanupWorkItem != nil
    }

    private func hoverEnabledCalendarFrames(for scope: DragSessionScope) -> [DateCellFrame] {
        guard handoffState.allowsCalendarHover else { return [] }
        return calendarFrames(for: scope)
    }

    private func resolvedHandoffState(
        for phase: DragOwnershipHandoffPhase
    ) -> DragOwnershipHandoffState {
        let claimSnapshot: DragTouchClaimSnapshot? = switch phase {
        case .idle, .localPreview:
            nil
        case .rootClaimPending, .rootClaimAcquired, .landing, .restoring:
            touchClaimHandoff.snapshot
        }

        let token = claimSnapshot?.token ?? handoffState.token
        let owner: DragTouchClaimOwner = switch phase {
        case .idle:
            .none
        case .localPreview, .rootClaimPending:
            .localPreview
        case .rootClaimAcquired:
            .root
        case .landing, .restoring:
            if handoffState.isRootClaimAcquired || claimSnapshot?.rootClaimedAt != nil {
                .root
            } else if draggedItem != nil {
                .localPreview
            } else {
                .none
            }
        }

        let restoreReason = claimSnapshot?.restoreReason ?? handoffState.restoreReason
        return DragOwnershipHandoffState(
            phase: phase,
            token: token,
            owner: owner,
            restoreReason: phase == .idle ? nil : restoreReason,
            claimSnapshot: claimSnapshot
        )
    }

    private func activateCalendarHoverIfNeeded() {
        guard engine.snapshot.dragStarted,
              let pointer = engine.snapshot.pointerGlobal else {
            return
        }
        let previousActiveDate = snapshot.activeDate

        engine.updateScope(
            engine.snapshot.currentScope,
            visibleDayDate: visibleDayDate,
            pointerGlobal: pointer,
            timelineLayout: timelineLayout,
            calendarFrames: hoverEnabledCalendarFrames(for: engine.snapshot.currentScope)
        )
        syncDisplayedOverlayFrame(
            animated: shouldAnimateCalendarPillFrameChange(
                scope: engine.snapshot.currentScope,
                previousActiveDate: previousActiveDate
            )
        )
    }

    private func updatePresentationAfterRootClaimSuccess() {
        guard pendingLandingCommit == nil else { return }

        if visibleScope == .day {
            if overlayPresentation.visualPhase != .lifted && snapshot.dragStarted {
                updatePresentation(to: .floating, animated: true)
            }
            return
        }

        updatePresentation(to: .holding, animated: true)
        scheduleCalendarPillAdvance(for: visibleScope)
    }

    private func beginRestoreAfterFinishedClaimIfNeeded() {
        guard touchClaimHandoff.snapshot.restoreReason != nil else { return }
        beginRestoreAfterClaimFailure()
    }

    private func beginRestoreAfterClaimFailure() {
        guard handoffState.phase == .rootClaimPending || handoffState.phase == .rootClaimAcquired else {
            return
        }

        let snapshot = engine.cancel(timestampMs: nowTimestampMs())
        handoffState = resolvedHandoffState(for: .restoring)
        updatePresentation(to: .restoring, animated: true)
        syncDisplayedOverlayFrame()

        if snapshot.state == .restoring {
            scheduleRestoreCleanup()
        }
    }

    private func endCurrentHandoffSessionIfNeeded() {
        guard let token = handoffState.token else { return }
        _ = applyRootClaimEnd(for: token)
    }

    private func updatePresentation(
        to phase: DragOverlayVisualPhase,
        animated: Bool
    ) {
        let next = resolvedPresentation(for: phase)
        guard overlayPresentation != next else { return }

        if animated {
            let animation: Animation
            switch phase {
            case .lifted:
                animation = .spring(duration: Double(overlayTimings.liftDurationMs) / 1000.0, bounce: 0.12)
            case .holding, .floating:
                animation = .easeOut(duration: Double(overlayTimings.pillTransitionDurationMs) / 1000.0)
            case .restoring:
                animation = .easeInOut(duration: Double(engine.params.restoreAnimationMs) / 1000.0)
            case .landing:
                animation = .spring(duration: Double(overlayTimings.landingDurationMs) / 1000.0, bounce: 0.08)
            case .anchored, .inactive:
                animation = .easeOut(duration: 0.12)
            }

            withAnimation(animation) {
                overlayPresentation = next
            }
        } else {
            withoutAnimation {
                overlayPresentation = next
            }
        }
    }

    private func resolvedPresentation(for phase: DragOverlayVisualPhase) -> DragOverlayPresentation {
        DragOverlayPresentationResolver.resolve(
            DragOverlayPresentationContext(
                visualPhase: phase,
                scope: visibleScope,
                pillWidth: calendarPillWidth
            )
        )
    }

    private func resolvedDisplayedOverlayFrame() -> CGRect? {
        guard let baseFrame = engine.snapshot.overlayFrameGlobal ?? displayedOverlayFrameGlobal else {
            return displayedOverlayFrameGlobal
        }

        switch overlayPresentation.style {
        case .timelineCard:
            return baseFrame
        case .calendarPill:
            return calendarPillFrame(baseFrame: baseFrame)
        }
    }

    private func calendarPillFrame(baseFrame: CGRect) -> CGRect {
        let width = overlayPresentation.pillWidth ?? calendarPillWidth
        let height = overlayPresentation.pillHeight ?? DragOverlayPresentationResolver.defaultPillHeight
        let center: CGPoint

        if let activeDate = snapshot.activeDate,
           let cell = calendarFrames(for: visibleScope).first(where: { $0.date.isSameDay(as: activeDate) }) {
            center = CGPoint(x: cell.frameGlobal.midX, y: cell.frameGlobal.midY)
        } else {
            center = CGPoint(x: baseFrame.midX, y: baseFrame.midY)
        }

        return CGRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width,
            height: height
        )
    }

    private func landingTargetFrame(for commit: DragSessionCommit) -> CGRect? {
        guard let timelineLayout,
              let sourceFrame = snapshot.source?.originalFrameGlobal else {
            return nil
        }

        let startMinute = minuteOfDay(for: commit.start)
        let endMinute = minuteOfDay(for: commit.end)
        let yPosition = timelineLayout.frameGlobal.minY - timelineLayout.scrollOffsetY
            + (CGFloat(startMinute) / 60.0) * timelineLayout.hourHeight
        let height = max((CGFloat(endMinute - startMinute) / 60.0) * timelineLayout.hourHeight - 1, 16)

        return CGRect(
            x: sourceFrame.minX,
            y: yPosition,
            width: sourceFrame.width,
            height: height
        )
    }

    private func resolvedCalendarPillWidth(from sourceFrame: CGRect) -> CGFloat {
        let scaled = sourceFrame.width * 0.28
        return min(max(scaled, DragOverlayPresentationResolver.defaultPillWidth), 64)
    }

    private func nextClaimTimestamp() -> DragTouchClaimTimestamp {
        claimFrameIndex += 1
        return DragTouchClaimTimestamp(
            frameIndex: claimFrameIndex,
            uptimeMs: nowTimestampMs()
        )
    }

    private func withoutAnimation(_ updates: () -> Void) {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            updates()
        }
    }

    private func minuteOfDay(for date: Date) -> Int {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return hour * 60 + minute
    }

    private func nowTimestampMs() -> Int {
        Int(Date().timeIntervalSince1970 * 1000)
    }

    private func shouldAnimateCalendarPillFrameChange(
        scope: DragSessionScope,
        previousActiveDate: Date?
    ) -> Bool {
        DragCalendarPillAnimationPolicy.shouldAnimateFrameChange(
            style: overlayPresentation.style,
            scope: scope,
            previousActiveDate: previousActiveDate,
            nextActiveDate: snapshot.activeDate
        )
    }

    private func recordRestoreReason(_ reason: DragHandoffRestoreTraceReason) {
        traceSink.record(.restoreReason(reason))
    }

    private func calendarFrames(for scope: DragSessionScope) -> [DateCellFrame] {
        calendarFramesByScope[scope] ?? []
    }

    private func map(_ scope: CalendarScope) -> DragSessionScope {
        switch scope {
        case .day:
            return .day
        case .month:
            return .month
        case .year:
            return .year
        }
    }
}
