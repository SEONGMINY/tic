import XCTest
@testable import tic

final class DragSessionEngineTests: XCTestCase {
    func testDragStartRequiresLongPressAndDistanceThreshold() {
        var engine = DragSessionEngine()
        let source = makeSource()
        let layout = makeTimelineLayout()

        engine.touchStart(source: source, at: CGPoint(x: 120, y: 210), scope: .day)
        engine.longPressRecognized(timestampMs: 500)
        engine.dragMoved(
            to: CGPoint(x: 123, y: 213),
            timestampMs: 520,
            timelineLayout: layout
        )

        XCTAssertEqual(engine.snapshot.state, .dragReady)
        XCTAssertFalse(engine.snapshot.dragStarted)

        engine.dragMoved(
            to: CGPoint(x: 130, y: 220),
            timestampMs: 560,
            timelineLayout: layout
        )

        XCTAssertEqual(engine.snapshot.state, .draggingTimeline)
        XCTAssertTrue(engine.snapshot.dragStarted)
        XCTAssertEqual(engine.snapshot.dragStartTimestampMs, 560)
    }

    func testFalseStartBeforeLongPressReturnsIdle() {
        var engine = DragSessionEngine()
        let source = makeSource()

        engine.touchStart(source: source, at: CGPoint(x: 120, y: 210), scope: .day)
        engine.dragMoved(
            to: CGPoint(x: 150, y: 240),
            timestampMs: 120,
            timelineLayout: makeTimelineLayout()
        )

        XCTAssertEqual(engine.snapshot.state, .idle)
        XCTAssertEqual(engine.snapshot.invalidReason, .falseStartPreLongPress)
    }

    func testInvalidCalendarDropRestoresAndFinishesIdle() {
        var engine = DragSessionEngine()
        let source = makeSource()

        engine.touchStart(source: source, at: CGPoint(x: 120, y: 210), scope: .day)
        engine.longPressRecognized(timestampMs: 500)
        engine.dragMoved(
            to: CGPoint(x: 130, y: 220),
            timestampMs: 560,
            timelineLayout: makeTimelineLayout()
        )
        engine.updateScope(.month, pointerGlobal: CGPoint(x: 260, y: 120), calendarFrames: [])

        let snapshot = engine.drop(timestampMs: 800)

        XCTAssertEqual(snapshot.state, .restoring)
        XCTAssertEqual(snapshot.outcome, .cancelled)
        XCTAssertEqual(snapshot.invalidReason, .invalidDrop)
        XCTAssertFalse(snapshot.droppable)

        engine.finishRestore()

        XCTAssertEqual(engine.snapshot.state, .idle)
        XCTAssertEqual(engine.snapshot.outcome, .cancelled)
        XCTAssertEqual(engine.snapshot.invalidReason, .invalidDrop)
    }

    func testCalendarDropNeedsActiveDate() {
        var engine = DragSessionEngine()
        let source = makeSource()
        let april18 = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 18))!
        let frames = [
            DateCellFrame(date: april18, frameGlobal: CGRect(x: 240, y: 80, width: 60, height: 60))
        ]

        engine.touchStart(source: source, at: CGPoint(x: 120, y: 210), scope: .day)
        engine.longPressRecognized(timestampMs: 500)
        engine.dragMoved(
            to: CGPoint(x: 130, y: 220),
            timestampMs: 560,
            timelineLayout: makeTimelineLayout()
        )
        engine.updateScope(.month, pointerGlobal: CGPoint(x: 40, y: 40), calendarFrames: [])
        XCTAssertFalse(engine.snapshot.droppable)

        engine.dragMoved(
            to: CGPoint(x: 260, y: 100),
            timestampMs: 680,
            calendarFrames: frames
        )

        XCTAssertEqual(engine.snapshot.activeDate, april18.startOfDay)
        XCTAssertTrue(engine.snapshot.droppable)
    }

    func testScopeRoundTripPreservesMinuteCandidateForCalendarDrop() {
        var engine = DragSessionEngine()
        let source = makeSource()
        let timelineLayout = makeTimelineLayout()
        let april20 = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 20))!
        let frames = [
            DateCellFrame(date: april20, frameGlobal: CGRect(x: 240, y: 80, width: 60, height: 60))
        ]

        engine.touchStart(source: source, at: CGPoint(x: 120, y: 210), scope: .day)
        engine.longPressRecognized(timestampMs: 500)
        engine.dragMoved(
            to: CGPoint(x: 180, y: 330),
            timestampMs: 560,
            timelineLayout: timelineLayout
        )
        let preservedMinute = engine.snapshot.minuteCandidate

        engine.updateScope(
            .month,
            pointerGlobal: CGPoint(x: 260, y: 100),
            calendarFrames: frames
        )

        let snapshot = engine.drop(timestampMs: 900)

        XCTAssertEqual(preservedMinute, 210)
        XCTAssertEqual(snapshot.finalDropResult?.date, april20.startOfDay)
        XCTAssertEqual(snapshot.finalDropResult?.startMinute, preservedMinute)
        XCTAssertEqual(snapshot.finalDropResult?.endMinute, (preservedMinute ?? 0) + source.durationMinute)
    }

    func testCancelRestoresAndFinishRestoreEndsIdle() {
        var engine = DragSessionEngine()
        let source = makeSource()

        engine.touchStart(source: source, at: CGPoint(x: 120, y: 210), scope: .day)
        engine.longPressRecognized(timestampMs: 500)
        engine.dragMoved(
            to: CGPoint(x: 130, y: 220),
            timestampMs: 560,
            timelineLayout: makeTimelineLayout()
        )

        let cancelled = engine.cancel(timestampMs: 700)
        XCTAssertEqual(cancelled.state, .restoring)
        XCTAssertEqual(cancelled.outcome, .cancelled)
        XCTAssertEqual(cancelled.restoreTargetFrameGlobal, source.originalFrameGlobal)

        engine.finishRestore()
        XCTAssertEqual(engine.snapshot.state, .idle)
        XCTAssertEqual(engine.snapshot.outcome, .cancelled)
        XCTAssertEqual(engine.snapshot.invalidReason, .cancelledByEvent)
        XCTAssertNil(engine.snapshot.finalDropResult)
    }

    private func makeSource() -> DragSessionSource {
        DragSessionSource(
            itemId: "event-1",
            sourceDate: Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 16))!,
            sourceStartMinute: 120,
            sourceEndMinute: 180,
            originalFrameGlobal: CGRect(x: 100, y: 200, width: 180, height: 60)
        )
    }

    private func makeTimelineLayout() -> DragTimelineLayout {
        DragTimelineLayout(
            frameGlobal: CGRect(x: 52, y: 120, width: 280, height: 1440),
            scrollOffsetY: 0,
            hourHeight: 60
        )
    }
}
