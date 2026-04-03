import SwiftUI

struct YearView: View {
    var viewModel: CalendarViewModel
    var eventKitService: EventKitService

    @State private var anchorYear: Int = Calendar.current.component(.year, from: .now)
    @State private var initialized = false
    @State private var yearsBefore: Int = 20
    @State private var yearsAfter: Int = 20

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    private let miniColumns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let weekdays = ["일", "월", "화", "수", "목", "금", "토"]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 20) {
                    let years = yearsRange()
                    ForEach(Array(years.enumerated()), id: \.element) { index, year in
                        yearSection(year: year)
                            .id(year)
                            .onAppear {
                                viewModel.displayedYear = year
                                // 끝에서 3번째에서 미리 확장
                                if index <= 2 {
                                    yearsBefore += 10
                                } else if index >= years.count - 3 {
                                    yearsAfter += 10
                                }
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onAppear {
                if !initialized {
                    anchorYear = viewModel.displayedYear
                    initialized = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        proxy.scrollTo(anchorYear, anchor: .top)
                    }
                }
            }
        }
    }

    // @State 변수와 anchorYear(상수)에만 의존
    private func yearsRange() -> [Int] {
        return Array((anchorYear - yearsBefore)...(anchorYear + yearsAfter))
    }

    private func yearSection(year: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: "\(year)년")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.top, 4)

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(monthsForYear(year), id: \.self) { month in
                    miniMonthCell(month)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(duration: 0.35, bounce: 0.05)) {
                                viewModel.goToMonth(month)
                            }
                        }
                }
            }
        }
    }

    private func monthsForYear(_ year: Int) -> [Date] {
        let calendar = Calendar.current
        return (1...12).compactMap { month in
            calendar.date(from: DateComponents(year: year, month: month, day: 1))
        }
    }

    // EventKit 쿼리 없음 — 년간 뷰에서는 점 표시 안 함 (성능 최적화)
    private func miniMonthCell(_ month: Date) -> some View {
        let days = viewModel.daysInMonth(for: month)

        return VStack(alignment: .leading, spacing: 2) {
            Text("\(month.month)월")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: miniColumns, spacing: 1) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 6))
                        .foregroundStyle(.quaternary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        Text(verbatim: "\(day.day)")
                            .font(.system(size: 8, weight: .light))
                            .foregroundStyle(day.isToday ? .orange : .primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 12)
                    } else {
                        Color.clear
                            .frame(height: 12)
                    }
                }
            }
        }
    }
}
