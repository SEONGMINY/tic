import SwiftUI

enum CalendarScope {
    case year, month, day
}

@Observable
class CalendarViewModel {
    var scope: CalendarScope = .month
    var selectedDate: Date = .now
    var displayedMonth: Date = .now
    var displayedYear: Int = Calendar.current.component(.year, from: .now)

    // MARK: - 월간 뷰 데이터

    func daysInMonth(for date: Date) -> [Date?] {
        let calendar = Calendar.current
        let firstDay = date.startOfMonth
        let weekdayOfFirst = calendar.component(.weekday, from: firstDay) // 1=일요일
        let range = calendar.range(of: .day, in: .month, for: date)!

        var days: [Date?] = Array(repeating: nil, count: weekdayOfFirst - 1)
        for day in range {
            if let d = calendar.date(byAdding: .day, value: day - 1, to: firstDay) {
                days.append(d)
            }
        }
        return days
    }

    func hasEvents(on date: Date, service: EventKitService) -> Bool {
        service.hasEvents(on: date)
    }

    // MARK: - 년간 뷰 데이터

    func monthsInYear() -> [Date] {
        let calendar = Calendar.current
        let year = displayedYear
        return (1...12).compactMap { month in
            calendar.date(from: DateComponents(year: year, month: month, day: 1))
        }
    }

    // MARK: - 네비게이션

    func goToToday() {
        selectedDate = .now
        displayedMonth = .now
        displayedYear = Calendar.current.component(.year, from: .now)
    }

    func selectDate(_ date: Date) {
        selectedDate = date
        scope = .day
    }

    func goToMonth(_ date: Date) {
        displayedMonth = date
        displayedYear = Calendar.current.component(.year, from: date)
        scope = .month
    }
}
