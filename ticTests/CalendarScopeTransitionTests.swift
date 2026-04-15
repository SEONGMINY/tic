import XCTest
import UIKit
@testable import tic

final class CalendarScopeTransitionTests: XCTestCase {
    func testPinchOutMovesDayToMonth() {
        let nextState = CalendarScopeTransition.nextState(
            from: makeState(scope: .day),
            pinch: .pinchOut,
            referenceDate: referenceDate
        )

        XCTAssertEqual(nextState?.scope, .month)
        XCTAssertEqual(nextState?.displayedMonth, selectedDate.startOfMonth)
    }

    func testPinchOutMovesMonthToYear() {
        let nextState = CalendarScopeTransition.nextState(
            from: makeState(scope: .month),
            pinch: .pinchOut,
            referenceDate: referenceDate
        )

        XCTAssertEqual(nextState?.scope, .year)
        XCTAssertEqual(nextState?.displayedYear, selectedDate.year)
    }

    func testPinchOutAtYearIsNoOp() {
        let nextState = CalendarScopeTransition.nextState(
            from: makeState(scope: .year),
            pinch: .pinchOut,
            referenceDate: referenceDate
        )

        XCTAssertNil(nextState)
    }

    func testPinchInMovesYearToMonth() {
        let nextState = CalendarScopeTransition.nextState(
            from: makeState(scope: .year),
            pinch: .pinchIn,
            referenceDate: referenceDate
        )

        XCTAssertEqual(nextState?.scope, .month)
        XCTAssertEqual(nextState?.displayedMonth, selectedDate.startOfMonth)
    }

    func testPinchInMovesMonthToDay() {
        let nextState = CalendarScopeTransition.nextState(
            from: makeState(scope: .month),
            pinch: .pinchIn,
            referenceDate: referenceDate
        )

        XCTAssertEqual(nextState?.scope, .day)
        XCTAssertEqual(nextState?.selectedDate, selectedDate.startOfDay)
    }

    func testActiveDragSessionRemainsVisibleAcrossScopeChanges() {
        let coordinator = CalendarDragCoordinator()
        let item = makeItem()
        let sourceFrame = CGRect(x: 100, y: 200, width: 180, height: 60)
        let dragPoint = CGPoint(x: 180, y: 330)

        coordinator.updateVisibleDay(selectedDate)
        coordinator.updateTimelineLayout(
            frameGlobal: CGRect(x: 52, y: 120, width: 280, height: 1440),
            scrollOffsetY: 0
        )
        coordinator.beginDayDrag(
            item: item,
            sourceFrameGlobal: sourceFrame,
            pointerGlobal: CGPoint(x: 120, y: 210)
        )
        coordinator.updateDayDrag(pointerGlobal: dragPoint)

        let source = coordinator.snapshot.source
        let duration = coordinator.snapshot.durationMinute
        let minuteCandidate = coordinator.snapshot.minuteCandidate
        let overlayFrame = coordinator.displayedOverlayFrameGlobal

        XCTAssertTrue(coordinator.isSessionVisible)

        coordinator.updateVisibleScope(.month)

        XCTAssertEqual(coordinator.snapshot.currentScope, .month)
        XCTAssertEqual(coordinator.snapshot.source, source)
        XCTAssertEqual(coordinator.snapshot.durationMinute, duration)
        XCTAssertEqual(coordinator.snapshot.minuteCandidate, minuteCandidate)
        XCTAssertEqual(coordinator.displayedOverlayFrameGlobal, overlayFrame)
        XCTAssertTrue(coordinator.isSessionVisible)

        coordinator.updateVisibleScope(.day)

        XCTAssertEqual(coordinator.snapshot.currentScope, .day)
        XCTAssertEqual(coordinator.snapshot.source, source)
        XCTAssertEqual(coordinator.snapshot.durationMinute, duration)
        XCTAssertEqual(coordinator.snapshot.minuteCandidate, minuteCandidate)
        XCTAssertEqual(coordinator.displayedOverlayFrameGlobal, overlayFrame)
        XCTAssertTrue(coordinator.isSessionVisible)
    }

    private var selectedDate: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 16))!
    }

    private var referenceDate: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 10))!
    }

    private func makeState(scope: CalendarScope) -> CalendarScopeTransitionState {
        CalendarScopeTransitionState(
            scope: scope,
            selectedDate: selectedDate,
            displayedMonth: selectedDate.startOfMonth,
            displayedYear: selectedDate.year
        )
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
