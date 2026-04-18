import Foundation
import CoreGraphics

struct DragSessionEngine {
    let params: DragSessionParams
    private(set) var snapshot: DragSessionSnapshot

    init(params: DragSessionParams = .baseline) {
        self.params = params
        self.snapshot = DragSessionSnapshot(params: params)
    }

    mutating func touchStart(
        source: DragSessionSource,
        at point: CGPoint,
        scope: DragSessionScope
    ) {
        let anchor = CGPoint(
            x: point.x - source.originalFrameGlobal.minX,
            y: point.y - source.originalFrameGlobal.minY
        )

        snapshot = DragSessionSnapshot(
            params: params,
            state: .pressing,
            outcome: .none,
            currentScope: scope,
            source: source,
            pointerGlobal: point,
            pressStartPointGlobal: point,
            anchorToBlockOrigin: anchor,
            overlayFrameGlobal: DragSessionGeometry.overlayFrame(
                pointerGlobal: point,
                anchorToBlockOrigin: anchor,
                sourceFrame: source.originalFrameGlobal
            ),
            restoreTargetFrameGlobal: source.originalFrameGlobal,
            dateCandidate: source.sourceDate,
            minuteCandidate: source.sourceStartMinute,
            activeDate: nil,
            dragStarted: false,
            dragStartTimestampMs: nil,
            invalidReason: nil,
            finalDropResult: nil
        )
    }

    mutating func longPressRecognized(timestampMs: Int) {
        guard snapshot.state == .pressing else { return }
        snapshot.state = .dragReady
        snapshot.invalidReason = nil
    }

    mutating func dragMoved(
        to point: CGPoint,
        timestampMs: Int,
        timelineLayout: DragTimelineLayout? = nil,
        calendarFrames: [DateCellFrame] = []
    ) {
        guard snapshot.source != nil else { return }

        snapshot.pointerGlobal = point
        updateOverlayFrame(for: point)

        if snapshot.state == .pressing,
           let pressStart = snapshot.pressStartPointGlobal,
           distance(from: pressStart, to: point) > params.pressSlopPt {
            snapshot = idleSnapshot(
                scope: snapshot.currentScope,
                outcome: .none,
                invalidReason: .falseStartPreLongPress
            )
            return
        }

        if snapshot.state == .dragReady,
           snapshot.dragStarted == false,
           let pressStart = snapshot.pressStartPointGlobal,
           distance(from: pressStart, to: point) >= params.dragStartMinDistancePt {
            snapshot.dragStarted = true
            snapshot.dragStartTimestampMs = timestampMs
            snapshot.state = snapshot.currentScope == .day ? .draggingTimeline : .draggingCalendar
        }

        switch snapshot.state {
        case .draggingTimeline:
            updateTimelineCandidates(with: point, layout: timelineLayout)
        case .draggingCalendar:
            updateCalendarCandidates(with: point, calendarFrames: calendarFrames)
        default:
            break
        }
    }

    mutating func updateScope(
        _ scope: DragSessionScope,
        visibleDayDate: Date? = nil,
        pointerGlobal: CGPoint? = nil,
        timelineLayout: DragTimelineLayout? = nil,
        calendarFrames: [DateCellFrame] = []
    ) {
        snapshot.currentScope = scope
        if let pointerGlobal {
            snapshot.pointerGlobal = pointerGlobal
            updateOverlayFrame(for: pointerGlobal)
        }

        guard snapshot.dragStarted else { return }

        switch scope {
        case .day:
            snapshot.state = .draggingTimeline
            if let visibleDayDate {
                snapshot.dateCandidate = visibleDayDate.startOfDay
            } else if snapshot.dateCandidate == nil {
                snapshot.dateCandidate = snapshot.source?.sourceDate
            }
            if let pointerGlobal {
                updateTimelineCandidates(with: pointerGlobal, layout: timelineLayout)
            }
        case .month, .year:
            snapshot.state = .draggingCalendar
            snapshot.activeDate = nil
            snapshot.dateCandidate = nil
            if let pointerGlobal {
                updateCalendarCandidates(with: pointerGlobal, calendarFrames: calendarFrames)
            }
        }
    }

    mutating func drop(timestampMs: Int) -> DragSessionSnapshot {
        guard snapshot.source != nil else { return snapshot }
        guard snapshot.state == .draggingTimeline || snapshot.state == .draggingCalendar else {
            return snapshot
        }

        if let finalDropResult = DragSessionGeometry.buildFinalDropResult(
            dateCandidate: snapshot.dropCandidateDate,
            minuteCandidate: snapshot.minuteCandidate,
            durationMinute: snapshot.durationMinute ?? 0,
            minimumDurationMinute: params.minimumDurationMinute
        ) {
            snapshot.finalDropResult = finalDropResult
            snapshot.outcome = .dropped
            snapshot.invalidReason = nil
            snapshot.state = .idle
            return snapshot
        }

        snapshot.outcome = .cancelled
        snapshot.invalidReason = .invalidDrop
        snapshot.state = .restoring
        snapshot.restoreTargetFrameGlobal = snapshot.source?.originalFrameGlobal
        return snapshot
    }

    mutating func cancel(timestampMs: Int) -> DragSessionSnapshot {
        guard snapshot.source != nil else { return snapshot }
        guard snapshot.state != .idle else { return snapshot }

        snapshot.outcome = snapshot.dragStarted ? .cancelled : .none
        snapshot.invalidReason = .cancelledByEvent
        snapshot.state = .restoring
        snapshot.restoreTargetFrameGlobal = snapshot.source?.originalFrameGlobal
        return snapshot
    }

    mutating func finishRestore() {
        guard snapshot.state == .restoring else { return }
        let scope = snapshot.currentScope
        let outcome = snapshot.outcome
        let invalidReason = snapshot.invalidReason
        snapshot = idleSnapshot(
            scope: scope,
            outcome: outcome,
            invalidReason: invalidReason
        )
    }

    private mutating func updateOverlayFrame(for point: CGPoint) {
        guard let anchor = snapshot.anchorToBlockOrigin,
              let source = snapshot.source else { return }
        snapshot.overlayFrameGlobal = DragSessionGeometry.overlayFrame(
            pointerGlobal: point,
            anchorToBlockOrigin: anchor,
            sourceFrame: source.originalFrameGlobal
        )
    }

    private mutating func updateTimelineCandidates(with point: CGPoint, layout: DragTimelineLayout?) {
        guard let layout else {
            DragDebugLog.log(
                "updateTimelineCandidates layout=nil point=\(point.debugDescription)"
            )
            snapshot.minuteCandidate = nil
            return
        }
        snapshot.currentScope = .day
        snapshot.dateCandidate = snapshot.dateCandidate ?? snapshot.source?.sourceDate
        let dropZone = DragSessionGeometry.inset(
            layout.frameGlobal,
            by: params.timelineDropInsetPt
        )
        let probePoint = DragSessionGeometry.timelineDropProbePoint(
            pointerGlobal: point,
            overlayFrameGlobal: snapshot.overlayFrameGlobal,
            dropZone: dropZone
        )
        snapshot.minuteCandidate = DragSessionGeometry.minuteCandidate(
            pointerGlobal: point,
            overlayFrameGlobal: snapshot.overlayFrameGlobal,
            layout: layout,
            snapStep: params.minuteSnapStep,
            dropInset: params.timelineDropInsetPt
        )
        DragDebugLog.log(
            "updateTimelineCandidates point=\(point.debugDescription) probe=\(probePoint.debugDescription) frame=\(layout.frameGlobal.debugDescription) zone=\(dropZone.debugDescription) minute=\(String(describing: snapshot.minuteCandidate))"
        )
    }

    private mutating func updateCalendarCandidates(with point: CGPoint, calendarFrames: [DateCellFrame]) {
        snapshot.activeDate = DragCalendarHoverResolver.activeDate(
            pointerGlobal: point,
            scope: snapshot.currentScope,
            dateCellFrames: calendarFrames,
            baseHitInset: params.cellHitInsetPt,
            previousActiveDate: snapshot.activeDate,
            baseHysteresis: params.cellHysteresisPt
        )
        if let activeDate = snapshot.activeDate {
            snapshot.dateCandidate = activeDate
        }
    }

    private func idleSnapshot(
        scope: DragSessionScope,
        outcome: DragSessionOutcome,
        invalidReason: DragSessionInvalidReason?
    ) -> DragSessionSnapshot {
        DragSessionSnapshot(
            params: params,
            state: .idle,
            outcome: outcome,
            currentScope: scope,
            source: nil,
            pointerGlobal: nil,
            pressStartPointGlobal: nil,
            anchorToBlockOrigin: nil,
            overlayFrameGlobal: nil,
            restoreTargetFrameGlobal: nil,
            dateCandidate: nil,
            minuteCandidate: nil,
            activeDate: nil,
            dragStarted: false,
            dragStartTimestampMs: nil,
            invalidReason: invalidReason,
            finalDropResult: nil
        )
    }

    private func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        return sqrt((dx * dx) + (dy * dy))
    }
}
