import Foundation
import CoreGraphics
import Observation
import SwiftUI

struct DragSessionCommit {
    let itemId: String
    let start: Date
    let end: Date
}

@Observable
final class CalendarDragCoordinator {
    private(set) var engine: DragSessionEngine
    private(set) var draggedItem: TicItem?
    private(set) var placeholderItemId: String?
    private(set) var displayedOverlayFrameGlobal: CGRect?

    private var rootFrameGlobal: CGRect = .zero
    private var timelineLayout: DragTimelineLayout?
    private var visibleDayDate: Date = .now.startOfDay
    private var calendarFramesByScope: [DragSessionScope: [DateCellFrame]] = [:]
    private var restoreCleanupWorkItem: DispatchWorkItem?
    private var rootOwnedSession = false

    init(params: DragSessionParams = .baseline) {
        self.engine = DragSessionEngine(params: params)
    }

    var overlayItem: TicItem? {
        guard let draggedItem else { return nil }
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

    var isSessionVisible: Bool {
        displayedOverlayFrameGlobal != nil && draggedItem != nil
    }

    var snapshot: DragSessionSnapshot {
        engine.snapshot
    }

    var sessionItem: TicItem? {
        draggedItem
    }

    var shouldHandleDragGlobally: Bool {
        rootOwnedSession && draggedItem != nil
    }

    var shouldHandleDropLocally: Bool {
        rootOwnedSession == false
    }

    func updateRootFrame(_ frameGlobal: CGRect) {
        rootFrameGlobal = frameGlobal
    }

    func updateVisibleScope(_ scope: CalendarScope) {
        let dragScope = map(scope)
        guard engine.snapshot.source != nil else { return }

        if dragScope != .day {
            rootOwnedSession = true
        }

        engine.updateScope(
            dragScope,
            visibleDayDate: visibleDayDate,
            pointerGlobal: engine.snapshot.pointerGlobal,
            timelineLayout: timelineLayout,
            calendarFrames: calendarFrames(for: dragScope)
        )
        syncDisplayedOverlayFrame()
    }

    func updateVisibleDay(_ date: Date) {
        visibleDayDate = date.startOfDay
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

        guard engine.snapshot.dragStarted,
              engine.snapshot.currentScope == scope,
              let pointer = engine.snapshot.pointerGlobal else {
            return
        }

        engine.updateScope(
            scope,
            visibleDayDate: visibleDayDate,
            pointerGlobal: pointer,
            timelineLayout: timelineLayout,
            calendarFrames: frames
        )
        syncDisplayedOverlayFrame()
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

    func beginDayDrag(
        item: TicItem,
        sourceFrameGlobal: CGRect,
        pointerGlobal: CGPoint
    ) {
        guard let startDate = item.startDate,
              let endDate = item.endDate else {
            return
        }

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
        rootOwnedSession = false
        syncDisplayedOverlayFrame()
    }

    func updateDayDrag(pointerGlobal: CGPoint) {
        guard draggedItem != nil else { return }
        engine.dragMoved(
            to: pointerGlobal,
            timestampMs: nowTimestampMs(),
            timelineLayout: timelineLayout
        )
        syncDisplayedOverlayFrame()
    }

    func updateGlobalDrag(pointerGlobal: CGPoint) {
        guard shouldHandleDragGlobally else { return }
        engine.dragMoved(
            to: pointerGlobal,
            timestampMs: nowTimestampMs(),
            timelineLayout: engine.snapshot.currentScope == .day ? timelineLayout : nil,
            calendarFrames: calendarFrames(for: engine.snapshot.currentScope)
        )
        syncDisplayedOverlayFrame()
    }

    func dropDayDrag() -> DragSessionCommit? {
        guard let draggedItem else { return nil }
        if engine.snapshot.state == .pressing || engine.snapshot.state == .dragReady {
            cancelDrag()
            return nil
        }
        let snapshot = engine.drop(timestampMs: nowTimestampMs())
        syncDisplayedOverlayFrame()

        if let finalDropResult = snapshot.finalDropResult,
           let absoluteDates = DragSessionGeometry.absoluteDates(from: finalDropResult) {
            let commit = DragSessionCommit(
                itemId: draggedItem.id,
                start: absoluteDates.start,
                end: absoluteDates.end
            )
            resetSession()
            return commit
        }

        if snapshot.state == .restoring {
            scheduleRestoreCleanup()
        }
        return nil
    }

    func completeGlobalDrag() -> DragSessionCommit? {
        guard shouldHandleDragGlobally else { return nil }
        return dropDayDrag()
    }

    func cancelDrag() {
        let snapshot = engine.cancel(timestampMs: nowTimestampMs())
        syncDisplayedOverlayFrame()
        if snapshot.state == .restoring {
            scheduleRestoreCleanup()
        }
    }

    func isShowingPlaceholder(for itemId: String?) -> Bool {
        guard let itemId else { return false }
        return placeholderItemId == itemId
    }

    private func scheduleRestoreCleanup() {
        restoreCleanupWorkItem?.cancel()
        if let restoreTarget = engine.snapshot.restoreTargetFrameGlobal {
            withAnimation(.easeInOut(duration: Double(engine.params.restoreAnimationMs) / 1000.0)) {
                displayedOverlayFrameGlobal = restoreTarget
            }
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.engine.finishRestore()
            self.resetSession()
        }
        restoreCleanupWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Double(engine.params.restoreAnimationMs) / 1000.0,
            execute: workItem
        )
    }

    private func resetSession() {
        engine = DragSessionEngine(params: engine.params)
        draggedItem = nil
        placeholderItemId = nil
        displayedOverlayFrameGlobal = nil
        rootOwnedSession = false
    }

    private func syncDisplayedOverlayFrame() {
        displayedOverlayFrameGlobal = engine.snapshot.overlayFrameGlobal
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
