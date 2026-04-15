import Foundation

enum CalendarScopePinchDirection: Equatable {
    case pinchIn
    case pinchOut
}

struct CalendarScopeTransitionState: Equatable {
    var scope: CalendarScope
    var selectedDate: Date
    var displayedMonth: Date
    var displayedYear: Int

    init(
        scope: CalendarScope,
        selectedDate: Date,
        displayedMonth: Date,
        displayedYear: Int
    ) {
        self.scope = scope
        self.selectedDate = selectedDate.startOfDay
        self.displayedMonth = displayedMonth.startOfMonth
        self.displayedYear = displayedYear
    }
}

enum CalendarScopeTransition {
    static func nextState(
        from state: CalendarScopeTransitionState,
        pinch direction: CalendarScopePinchDirection,
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> CalendarScopeTransitionState? {
        switch (state.scope, direction) {
        case (.day, .pinchOut):
            let targetMonth = state.selectedDate.startOfMonth
            return CalendarScopeTransitionState(
                scope: .month,
                selectedDate: state.selectedDate,
                displayedMonth: targetMonth,
                displayedYear: targetMonth.year
            )

        case (.month, .pinchOut):
            let targetMonth = state.displayedMonth.startOfMonth
            return CalendarScopeTransitionState(
                scope: .year,
                selectedDate: state.selectedDate,
                displayedMonth: targetMonth,
                displayedYear: targetMonth.year
            )

        case (.year, .pinchIn):
            let targetMonth = monthAnchor(
                for: state,
                referenceDate: referenceDate,
                calendar: calendar
            )
            let targetSelectedDate: Date
            if calendar.isDate(state.selectedDate, equalTo: targetMonth, toGranularity: .month) {
                targetSelectedDate = state.selectedDate
            } else {
                targetSelectedDate = targetMonth
            }

            return CalendarScopeTransitionState(
                scope: .month,
                selectedDate: targetSelectedDate,
                displayedMonth: targetMonth,
                displayedYear: targetMonth.year
            )

        case (.month, .pinchIn):
            let targetMonth = state.displayedMonth.startOfMonth
            let targetSelectedDate: Date
            if calendar.isDate(state.selectedDate, equalTo: targetMonth, toGranularity: .month) {
                targetSelectedDate = state.selectedDate
            } else {
                targetSelectedDate = targetMonth
            }

            return CalendarScopeTransitionState(
                scope: .day,
                selectedDate: targetSelectedDate,
                displayedMonth: targetMonth,
                displayedYear: targetMonth.year
            )

        case (.day, .pinchIn), (.year, .pinchOut):
            return nil
        }
    }

    private static func monthAnchor(
        for state: CalendarScopeTransitionState,
        referenceDate: Date,
        calendar: Calendar
    ) -> Date {
        let selectedMonth = state.selectedDate.startOfMonth
        if selectedMonth.year == state.displayedYear {
            return selectedMonth
        }

        let displayedMonth = state.displayedMonth.startOfMonth
        if displayedMonth.year == state.displayedYear {
            return displayedMonth
        }

        let referenceMonth = referenceDate.startOfMonth
        if referenceMonth.year == state.displayedYear {
            return referenceMonth
        }

        return calendar.date(
            from: DateComponents(year: state.displayedYear, month: 1, day: 1)
        )!.startOfMonth
    }
}

extension CalendarViewModel {
    var scopeTransitionState: CalendarScopeTransitionState {
        CalendarScopeTransitionState(
            scope: scope,
            selectedDate: selectedDate,
            displayedMonth: displayedMonth,
            displayedYear: displayedYear
        )
    }

    func applyScopeTransitionState(_ state: CalendarScopeTransitionState) {
        selectedDate = state.selectedDate
        displayedMonth = state.displayedMonth
        displayedYear = state.displayedYear
        scope = state.scope
    }
}
