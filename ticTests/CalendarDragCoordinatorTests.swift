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

    func testReturningToDayAfterRootOwnershipDoesNotCommitLocally() {
        let coordinator = makeCoordinator()
        let item = makeItem()

        beginDrag(coordinator, item: item)
        coordinator.updateDayDrag(pointerGlobal: movedPointer)
        coordinator.updateVisibleScope(.month)
        coordinator.updateVisibleScope(.day)

        XCTAssertEqual(coordinator.dropOwner, .rootCoordinator)
        XCTAssertTrue(coordinator.snapshot.droppable)
        XCTAssertFalse(coordinator.shouldHandleDropLocally)
        XCTAssertTrue(coordinator.shouldHandleDragGlobally)
        XCTAssertNil(coordinator.completeLocalDrag())

        let commit = coordinator.completeGlobalDrag()

        XCTAssertEqual(commit?.itemId, item.id)
        XCTAssertEqual(commit?.start, movedStartDate)
        XCTAssertEqual(commit?.end, movedEndDate)
    }

    func testSameDayDropCommitsThroughLocalPath() {
        let coordinator = makeCoordinator()
        let item = makeItem()

        beginDrag(coordinator, item: item)
        coordinator.updateDayDrag(pointerGlobal: movedPointer)

        XCTAssertEqual(coordinator.dropOwner, .localDayTimeline)
        XCTAssertTrue(coordinator.shouldHandleDropLocally)
        XCTAssertFalse(coordinator.shouldHandleDragGlobally)

        let commit = coordinator.completeLocalDrag()

        XCTAssertEqual(commit?.itemId, item.id)
        XCTAssertEqual(commit?.start, movedStartDate)
        XCTAssertEqual(commit?.end, movedEndDate)
    }

    func testPlaceholderClearsAfterGlobalSessionEnds() {
        let coordinator = makeCoordinator()
        let item = makeItem()

        beginDrag(coordinator, item: item)
        coordinator.updateDayDrag(pointerGlobal: movedPointer)
        coordinator.updateVisibleScope(.month)
        coordinator.updateVisibleScope(.day)

        XCTAssertTrue(coordinator.snapshot.placeholderVisible)
        XCTAssertTrue(coordinator.isShowingPlaceholder(for: item.id))
        XCTAssertTrue(coordinator.isSessionVisible)

        _ = coordinator.completeGlobalDrag()

        XCTAssertFalse(coordinator.snapshot.placeholderVisible)
        XCTAssertFalse(coordinator.isShowingPlaceholder(for: item.id))
        XCTAssertFalse(coordinator.isSessionVisible)
        XCTAssertNil(coordinator.sessionItem)
    }

    func testInvalidGlobalDropRestoresAndCleansUpToIdle() {
        let coordinator = makeCoordinator(restoreAnimationMs: 1)
        let item = makeItem()

        beginDrag(coordinator, item: item)
        coordinator.updateDayDrag(pointerGlobal: movedPointer)
        coordinator.updateVisibleScope(.month)

        XCTAssertTrue(coordinator.shouldHandleDragGlobally)
        XCTAssertTrue(coordinator.snapshot.placeholderVisible)
        XCTAssertTrue(coordinator.isSessionVisible)
        XCTAssertNil(coordinator.completeGlobalDrag())

        waitForRestoreCleanup()

        XCTAssertEqual(coordinator.snapshot.state, .idle)
        XCTAssertEqual(coordinator.lastSessionTermination, .invalidDropRestored)
        XCTAssertFalse(coordinator.snapshot.placeholderVisible)
        XCTAssertFalse(coordinator.isSessionVisible)
        XCTAssertNil(coordinator.sessionItem)
    }

    func testCancelEndsWithoutCommit() {
        let coordinator = makeCoordinator(restoreAnimationMs: 1)
        let item = makeItem()

        beginDrag(coordinator, item: item)
        coordinator.updateDayDrag(pointerGlobal: movedPointer)

        coordinator.cancelDrag()
        let commitAfterCancel = coordinator.completeLocalDrag()

        waitForRestoreCleanup()

        XCTAssertNil(commitAfterCancel)
        XCTAssertEqual(coordinator.snapshot.state, .idle)
        XCTAssertEqual(coordinator.lastSessionTermination, .cancelled)
        XCTAssertFalse(coordinator.isSessionVisible)
        XCTAssertFalse(coordinator.isShowingPlaceholder(for: item.id))
    }

    func testScopeRoundTripGlobalDropReturnsCommittedDayState() {
        let coordinator = makeCoordinator()
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
        coordinator.updateDayDrag(pointerGlobal: movedPointer)
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

    func testStaleCalendarFrameRegistryDoesNotLeakIntoNextSession() {
        let coordinator = makeCoordinator()
        let item = makeItem()
        let staleDate = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 18))!
        let stalePoint = CGPoint(x: 260, y: 100)
        let staleFrames = [
            DateCellFrame(date: staleDate, frameGlobal: CGRect(x: 240, y: 80, width: 60, height: 60))
        ]

        coordinator.updateCalendarFrames(staleFrames, scope: .month)

        beginDrag(coordinator, item: item)
        coordinator.updateDayDrag(pointerGlobal: movedPointer)
        coordinator.updateVisibleScope(.month)
        coordinator.updateGlobalDrag(pointerGlobal: stalePoint)

        XCTAssertEqual(coordinator.snapshot.activeDate, staleDate.startOfDay)

        _ = coordinator.completeGlobalDrag()

        beginDrag(coordinator, item: item)
        coordinator.updateDayDrag(pointerGlobal: movedPointer)
        coordinator.updateVisibleScope(.month)
        coordinator.updateGlobalDrag(pointerGlobal: stalePoint)

        XCTAssertNil(coordinator.snapshot.activeDate)
        XCTAssertFalse(coordinator.snapshot.droppable)
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

    private func makeCoordinator(restoreAnimationMs: Int = 220) -> CalendarDragCoordinator {
        var params = DragSessionParams.baseline
        params.restoreAnimationMs = restoreAnimationMs

        let coordinator = CalendarDragCoordinator(params: params)
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
            pointerGlobal: startPointer
        )
    }

    private func waitForRestoreCleanup() {
        let expectation = expectation(description: "restore cleanup")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 0.2)
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
