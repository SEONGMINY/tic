import Foundation
import CoreGraphics

enum DragSessionGeometry {
    static func isFinite(_ value: CGFloat) -> Bool {
        Double(value).isFinite
    }

    static func isUsableRect(_ rect: CGRect) -> Bool {
        isFinite(rect.minX)
            && isFinite(rect.minY)
            && isFinite(rect.width)
            && isFinite(rect.height)
            && rect.width > 0
            && rect.height > 0
    }

    static func inset(_ rect: CGRect, by inset: CGFloat) -> CGRect {
        rect.insetBy(dx: inset, dy: inset)
    }

    static func safeInset(_ rect: CGRect, by inset: CGFloat) -> CGRect {
        let dx = min(max(inset, 0), rect.width * 0.35)
        let dy = min(max(inset, 0), rect.height * 0.35)
        return rect.insetBy(dx: dx, dy: dy)
    }

    static func expand(_ rect: CGRect, by amount: CGFloat) -> CGRect {
        rect.insetBy(dx: -amount, dy: -amount)
    }

    static func pointInRect(_ point: CGPoint, rect: CGRect) -> Bool {
        rect.contains(point)
    }

    static func timelineLocalY(pointerGlobal: CGPoint, layout: DragTimelineLayout) -> CGFloat {
        pointerGlobal.y - layout.frameGlobal.minY + layout.scrollOffsetY
    }

    static func timelineDropProbePoint(
        pointerGlobal: CGPoint,
        overlayFrameGlobal: CGRect?,
        dropZone: CGRect
    ) -> CGPoint {
        guard let overlayFrameGlobal,
              isUsableRect(overlayFrameGlobal) else {
            return pointerGlobal
        }

        let clampedX = min(
            max(overlayFrameGlobal.midX, dropZone.minX + 1),
            dropZone.maxX - 1
        )

        return CGPoint(
            x: clampedX,
            y: overlayFrameGlobal.minY
        )
    }

    static func rawMinute(localY: CGFloat, hourHeight: CGFloat) -> CGFloat {
        (localY / hourHeight) * 60
    }

    static func clampMinute(_ minuteValue: CGFloat) -> CGFloat {
        min(1439, max(0, minuteValue))
    }

    static func snapMinute(_ minuteValue: CGFloat, step: Int) -> Int {
        Int((minuteValue / CGFloat(step)).rounded() * CGFloat(step))
    }

    static func minuteCandidate(
        pointerGlobal: CGPoint,
        overlayFrameGlobal: CGRect? = nil,
        layout: DragTimelineLayout,
        snapStep: Int,
        dropInset: CGFloat
    ) -> Int? {
        guard isUsableRect(layout.frameGlobal) else {
            return nil
        }
        let dropZone = inset(layout.frameGlobal, by: dropInset)
        let probePoint = timelineDropProbePoint(
            pointerGlobal: pointerGlobal,
            overlayFrameGlobal: overlayFrameGlobal,
            dropZone: dropZone
        )
        guard pointInRect(probePoint, rect: dropZone) else {
            return nil
        }
        let localY = timelineLocalY(pointerGlobal: probePoint, layout: layout)
        let minute = rawMinute(localY: localY, hourHeight: layout.hourHeight)
        return snapMinute(clampMinute(minute), step: snapStep)
    }

    static func overlayFrame(
        pointerGlobal: CGPoint,
        anchorToBlockOrigin: CGPoint,
        sourceFrame: CGRect
    ) -> CGRect {
        CGRect(
            x: pointerGlobal.x - anchorToBlockOrigin.x,
            y: pointerGlobal.y - anchorToBlockOrigin.y,
            width: sourceFrame.width,
            height: sourceFrame.height
        )
    }

    static func activeDate(
        pointerGlobal: CGPoint,
        dateCellFrames: [DateCellFrame],
        cellHitInset: CGFloat,
        previousActiveDate: Date?,
        cellHysteresis: CGFloat
    ) -> Date? {
        if let previousActiveDate {
            if let previousCell = dateCellFrames.first(where: { $0.date.isSameDay(as: previousActiveDate) }) {
                let hysteresisRect = expand(previousCell.frameGlobal, by: cellHysteresis)
                if pointInRect(pointerGlobal, rect: hysteresisRect) {
                    return previousCell.date
                }
            }
        }

        for cell in dateCellFrames {
            let targetRect = safeInset(cell.frameGlobal, by: cellHitInset)
            if pointInRect(pointerGlobal, rect: targetRect) {
                return cell.date
            }
        }
        return nil
    }

    static func buildFinalDropResult(
        dateCandidate: Date?,
        minuteCandidate: Int?,
        durationMinute: Int,
        minimumDurationMinute: Int
    ) -> DragDropResult? {
        guard let dateCandidate, let minuteCandidate else { return nil }
        guard durationMinute >= minimumDurationMinute else { return nil }
        guard minuteCandidate >= 0 else { return nil }

        let endMinute = minuteCandidate + durationMinute
        guard endMinute <= 1440 else { return nil }

        return DragDropResult(
            date: dateCandidate,
            startMinute: minuteCandidate,
            endMinute: endMinute
        )
    }

    static func absoluteDates(
        from result: DragDropResult,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date)? {
        let startOfDay = result.date.startOfDay
        guard let start = calendar.date(byAdding: .minute, value: result.startMinute, to: startOfDay),
              let end = calendar.date(byAdding: .minute, value: result.endMinute, to: startOfDay) else {
            return nil
        }
        return (start, end)
    }
}
