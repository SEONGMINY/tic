import XCTest
@testable import tic

final class DragSessionGeometryTests: XCTestCase {
    func testMinuteCandidateSnapsInsideTimeline() {
        let layout = DragTimelineLayout(
            frameGlobal: CGRect(x: 40, y: 120, width: 280, height: 1440),
            scrollOffsetY: 0,
            hourHeight: 60
        )

        let candidate = DragSessionGeometry.minuteCandidate(
            pointerGlobal: CGPoint(x: 180, y: 120 + 150),
            layout: layout,
            snapStep: 15,
            dropInset: 8
        )

        XCTAssertEqual(candidate, 150)
    }

    func testMinuteCandidateReturnsNilOutsideTimelineDropZone() {
        let layout = DragTimelineLayout(
            frameGlobal: CGRect(x: 40, y: 120, width: 280, height: 1440),
            scrollOffsetY: 0,
            hourHeight: 60
        )

        let candidate = DragSessionGeometry.minuteCandidate(
            pointerGlobal: CGPoint(x: 20, y: 120 + 150),
            layout: layout,
            snapStep: 15,
            dropInset: 8
        )

        XCTAssertNil(candidate)
    }

    func testMinuteCandidateUsesOverlayTopWhenFingerLeavesTimelineBottom() {
        let layout = DragTimelineLayout(
            frameGlobal: CGRect(x: 40, y: 120, width: 280, height: 1440),
            scrollOffsetY: 0,
            hourHeight: 60
        )
        let dropZone = DragSessionGeometry.inset(layout.frameGlobal, by: 8)
        let overlayFrame = CGRect(x: 80, y: 120 + 600, width: 120, height: 255)
        let probePoint = DragSessionGeometry.timelineDropProbePoint(
            pointerGlobal: CGPoint(x: 180, y: dropZone.maxY + 40),
            overlayFrameGlobal: overlayFrame,
            dropZone: dropZone
        )

        let candidate = DragSessionGeometry.minuteCandidate(
            pointerGlobal: CGPoint(x: 180, y: dropZone.maxY + 40),
            overlayFrameGlobal: overlayFrame,
            layout: layout,
            snapStep: 15,
            dropInset: 8
        )

        XCTAssertEqual(probePoint.y, overlayFrame.minY)
        XCTAssertEqual(candidate, 600)
    }

    func testMinuteCandidateUsesOverlayMidXWhenFingerHitsDayEdgeHoverZone() {
        let layout = DragTimelineLayout(
            frameGlobal: CGRect(x: 40, y: 120, width: 280, height: 1440),
            scrollOffsetY: 0,
            hourHeight: 60
        )
        let dropZone = DragSessionGeometry.inset(layout.frameGlobal, by: 8)
        let overlayFrame = CGRect(x: 120, y: 120 + 240, width: 120, height: 255)
        let probePoint = DragSessionGeometry.timelineDropProbePoint(
            pointerGlobal: CGPoint(x: dropZone.minX - 40, y: 120 + 300),
            overlayFrameGlobal: overlayFrame,
            dropZone: dropZone
        )

        let candidate = DragSessionGeometry.minuteCandidate(
            pointerGlobal: CGPoint(x: dropZone.minX - 40, y: 120 + 300),
            overlayFrameGlobal: overlayFrame,
            layout: layout,
            snapStep: 15,
            dropInset: 8
        )

        XCTAssertGreaterThanOrEqual(probePoint.x, dropZone.minX)
        XCTAssertLessThanOrEqual(probePoint.x, dropZone.maxX)
        XCTAssertEqual(candidate, 240)
    }

    func testActiveDateUsesInsetAndHysteresis() {
        let april16 = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 16))!
        let april17 = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 17))!
        let frames = [
            DateCellFrame(date: april16, frameGlobal: CGRect(x: 0, y: 0, width: 60, height: 60)),
            DateCellFrame(date: april17, frameGlobal: CGRect(x: 60, y: 0, width: 60, height: 60))
        ]

        let initial = DragSessionGeometry.activeDate(
            pointerGlobal: CGPoint(x: 20, y: 20),
            dateCellFrames: frames,
            cellHitInset: 6,
            previousActiveDate: nil,
            cellHysteresis: 12
        )
        let hysteresis = DragSessionGeometry.activeDate(
            pointerGlobal: CGPoint(x: 64, y: 20),
            dateCellFrames: frames,
            cellHitInset: 6,
            previousActiveDate: initial,
            cellHysteresis: 12
        )

        XCTAssertEqual(initial, april16.startOfDay)
        XCTAssertEqual(hysteresis, april16.startOfDay)
    }

    func testActiveDateReturnsNilWhenPointerLeavesAllCells() {
        let april16 = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 16))!
        let frames = [
            DateCellFrame(date: april16, frameGlobal: CGRect(x: 0, y: 0, width: 60, height: 60))
        ]

        let active = DragSessionGeometry.activeDate(
            pointerGlobal: CGPoint(x: 20, y: 20),
            dateCellFrames: frames,
            cellHitInset: 6,
            previousActiveDate: nil,
            cellHysteresis: 12
        )
        let outside = DragSessionGeometry.activeDate(
            pointerGlobal: CGPoint(x: 120, y: 120),
            dateCellFrames: frames,
            cellHitInset: 6,
            previousActiveDate: active,
            cellHysteresis: 12
        )

        XCTAssertEqual(active, april16.startOfDay)
        XCTAssertNil(outside)
    }

    func testBuildFinalDropResultRejectsOverflow() {
        let april16 = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 16))!
        let result = DragSessionGeometry.buildFinalDropResult(
            dateCandidate: april16,
            minuteCandidate: 1420,
            durationMinute: 60,
            minimumDurationMinute: 30
        )

        XCTAssertNil(result)
    }

    func testAbsoluteDatesBuildsStartAndEndDates() {
        let april16 = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 16))!
        let result = DragDropResult(date: april16, startMinute: 90, endMinute: 150)
        let dates = DragSessionGeometry.absoluteDates(from: result)

        XCTAssertEqual(Calendar.current.component(.hour, from: dates?.start ?? .distantPast), 1)
        XCTAssertEqual(Calendar.current.component(.minute, from: dates?.start ?? .distantPast), 30)
        XCTAssertEqual(Calendar.current.component(.hour, from: dates?.end ?? .distantPast), 2)
        XCTAssertEqual(Calendar.current.component(.minute, from: dates?.end ?? .distantPast), 30)
    }
}
