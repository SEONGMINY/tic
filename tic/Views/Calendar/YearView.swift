import SwiftUI

struct YearView: View {
    var viewModel: CalendarViewModel
    var eventKitService: EventKitService

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    private let miniColumns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let weekdays = ["일", "월", "화", "수", "목", "금", "토"]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(viewModel.monthsInYear(), id: \.self) { month in
                    miniMonthCell(month)
                        .onTapGesture {
                            viewModel.goToMonth(month)
                        }
                }
            }
            .padding(16)
        }
    }

    private func miniMonthCell(_ month: Date) -> some View {
        let days = viewModel.daysInMonth(for: month)

        return VStack(alignment: .leading, spacing: 4) {
            Text("\(month.month)월")
                .font(.system(size: 12, weight: .medium))
                .padding(.bottom, 2)

            LazyVGrid(columns: miniColumns, spacing: 2) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 6))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        VStack(spacing: 1) {
                            Text("\(day.day)")
                                .font(.system(size: 8, weight: .light))
                                .foregroundStyle(day.isToday ? .orange : .primary)

                            Circle()
                                .fill(viewModel.hasEvents(on: day, service: eventKitService) ? .orange : .clear)
                                .frame(width: 2, height: 2)
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Color.clear
                            .frame(height: 14)
                    }
                }
            }
        }
    }
}
