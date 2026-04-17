import XCTest
@testable import tic

final class DragOverlayPresentationTests: XCTestCase {
    func testInactivePhaseKeepsOverlayInactive() {
        let presentation = DragOverlayPresentationResolver.resolve(
            DragOverlayPresentationContext(
                visualPhase: .inactive,
                scope: .day,
                pillWidth: 48
            )
        )

        XCTAssertEqual(presentation, .inactive)
    }

    func testLiftedDayPresentationUsesTimelineCard() {
        let presentation = DragOverlayPresentationResolver.resolve(
            DragOverlayPresentationContext(
                visualPhase: .lifted,
                scope: .day,
                pillWidth: 48
            )
        )

        XCTAssertEqual(presentation.style, .timelineCard)
        XCTAssertEqual(presentation.visualPhase, .lifted)
        XCTAssertTrue(presentation.showsTitle)
        XCTAssertFalse(presentation.showsResizeHandles)
        XCTAssertFalse(presentation.showsToolbar)
        XCTAssertGreaterThan(presentation.overlayScale, 1)
        XCTAssertGreaterThan(presentation.sourcePlaceholderOpacity, 0)
    }

    func testFloatingTimelineKeepsTimelineCardWithoutEditingAffordances() {
        let presentation = DragOverlayPresentationResolver.resolve(
            DragOverlayPresentationContext(
                visualPhase: .floating,
                scope: .day,
                pillWidth: 48
            )
        )

        XCTAssertEqual(presentation.style, .timelineCard)
        XCTAssertTrue(presentation.showsTitle)
        XCTAssertFalse(presentation.showsResizeHandles)
        XCTAssertFalse(presentation.showsToolbar)
    }

    func testFloatingCalendarUsesAnonymousPillAndSameWidthAcrossScopes() {
        let monthPresentation = DragOverlayPresentationResolver.resolve(
            DragOverlayPresentationContext(
                visualPhase: .floating,
                scope: .month,
                pillWidth: 52
            )
        )
        let yearPresentation = DragOverlayPresentationResolver.resolve(
            DragOverlayPresentationContext(
                visualPhase: .floating,
                scope: .year,
                pillWidth: 52
            )
        )

        XCTAssertEqual(monthPresentation.style, .calendarPill)
        XCTAssertEqual(yearPresentation.style, .calendarPill)
        XCTAssertFalse(monthPresentation.showsTitle)
        XCTAssertFalse(yearPresentation.showsTitle)
        XCTAssertEqual(monthPresentation.pillWidth, yearPresentation.pillWidth)
        XCTAssertEqual(monthPresentation.pillHeight, yearPresentation.pillHeight)
    }

    func testDragFollowDoesNotChangeResolvedPresentationForSameContext() {
        let context = DragOverlayPresentationContext(
            visualPhase: .floating,
            scope: .day,
            pillWidth: 48
        )

        let first = DragOverlayPresentationResolver.resolve(context)
        let second = DragOverlayPresentationResolver.resolve(context)

        XCTAssertEqual(first, second)
    }

    func testCalendarPillFrameAnimationSkipsPointerFollowWithinSameActiveDate() {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 20))!

        XCTAssertFalse(
            DragCalendarPillAnimationPolicy.shouldAnimateFrameChange(
                style: .calendarPill,
                scope: .month,
                previousActiveDate: date.startOfDay,
                nextActiveDate: date.startOfDay
            )
        )
    }

    func testCalendarPillFrameAnimationRunsWhenActiveDateChanges() {
        let previousDate = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 20))!
        let nextDate = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 21))!

        XCTAssertTrue(
            DragCalendarPillAnimationPolicy.shouldAnimateFrameChange(
                style: .calendarPill,
                scope: .month,
                previousActiveDate: previousDate.startOfDay,
                nextActiveDate: nextDate.startOfDay
            )
        )
        XCTAssertFalse(
            DragCalendarPillAnimationPolicy.shouldAnimateFrameChange(
                style: .timelineCard,
                scope: .month,
                previousActiveDate: previousDate.startOfDay,
                nextActiveDate: nextDate.startOfDay
            )
        )
    }

    func testYearHoverPolicyIsMoreConservativeThanMonth() {
        let monthPolicy = DragCalendarHoverPolicy.forScope(
            .month,
            baseHitInset: 6,
            baseHysteresis: 12
        )
        let yearPolicy = DragCalendarHoverPolicy.forScope(
            .year,
            baseHitInset: 6,
            baseHysteresis: 12
        )

        XCTAssertGreaterThan(yearPolicy.cellHitInset, monthPolicy.cellHitInset)
        XCTAssertGreaterThan(yearPolicy.cellHysteresis, monthPolicy.cellHysteresis)
    }

    func testYearHoverNeedsMoreCenteredPointThanMonth() {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 20))!
        let frames = [
            DateCellFrame(
                date: date,
                frameGlobal: CGRect(x: 100, y: 100, width: 60, height: 60)
            )
        ]
        let pointNearEdge = CGPoint(x: 107, y: 107)

        let monthActive = DragCalendarHoverResolver.activeDate(
            pointerGlobal: pointNearEdge,
            scope: .month,
            dateCellFrames: frames,
            baseHitInset: 6,
            previousActiveDate: nil,
            baseHysteresis: 12
        )
        let yearActive = DragCalendarHoverResolver.activeDate(
            pointerGlobal: pointNearEdge,
            scope: .year,
            dateCellFrames: frames,
            baseHitInset: 6,
            previousActiveDate: nil,
            baseHysteresis: 12
        )

        XCTAssertEqual(monthActive, date.startOfDay)
        XCTAssertNil(yearActive)
    }
}
