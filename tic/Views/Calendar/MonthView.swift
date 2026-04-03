import SwiftUI

struct MonthView: View {
    var viewModel: CalendarViewModel
    var eventKitService: EventKitService

    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    private let weekdays = ["일", "월", "화", "수", "목", "금", "토"]

    var body: some View {
        VStack(spacing: 0) {
            // 요일 헤더
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }

            // 월 스와이프
            TabView(selection: Binding(
                get: { viewModel.displayedMonth.startOfMonth },
                set: { newMonth in
                    viewModel.displayedMonth = newMonth
                    viewModel.displayedYear = newMonth.year
                }
            )) {
                ForEach(monthPages(), id: \.self) { month in
                    monthGrid(for: month)
                        .tag(month)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }

    private func monthGrid(for date: Date) -> some View {
        let days = viewModel.daysInMonth(for: date)
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                        .onTapGesture {
                            viewModel.selectDate(day)
                        }
                } else {
                    Color.clear
                        .frame(height: 36)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func dayCell(_ date: Date) -> some View {
        let isToday = date.isToday
        let hasEvent = viewModel.hasEvents(on: date, service: eventKitService)

        return VStack(spacing: 4) {
            Text("\(date.day)")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(isToday ? .white : .primary)
                .frame(width: 32, height: 32)
                .background {
                    if isToday {
                        Circle()
                            .fill(.orange)
                    }
                }

            Circle()
                .fill(hasEvent ? .orange : .clear)
                .frame(width: 4, height: 4)
        }
        .frame(height: 36)
    }

    private func monthPages() -> [Date] {
        let calendar = Calendar.current
        let current = viewModel.displayedMonth.startOfMonth
        return (-6...6).compactMap { offset in
            calendar.date(byAdding: .month, value: offset, to: current)?.startOfMonth
        }
    }
}
