import SwiftUI

struct MonthView: View {
    var viewModel: CalendarViewModel
    var eventKitService: EventKitService

    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    private let weekdays = ["일", "월", "화", "수", "목", "금", "토"]

    @State private var anchorMonth: Date = .now
    @State private var initialized = false
    @State private var monthsBefore: Int = 48
    @State private var monthsAfter: Int = 48

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    let pages = monthPages()
                    ForEach(Array(pages.enumerated()), id: \.element) { index, month in
                        MonthSection(
                            month: month,
                            viewModel: viewModel,
                            eventKitService: eventKitService,
                            columns: columns,
                            weekdays: weekdays
                        )
                        .id(month)
                        .onAppear {
                            viewModel.displayedYear = month.year
                            // 끝에서 5번째에서 미리 확장
                            if index <= 4 {
                                monthsBefore += 24
                            } else if index >= pages.count - 5 {
                                monthsAfter += 24
                            }
                        }
                    }
                }
            }
            .onAppear {
                if !initialized {
                    anchorMonth = viewModel.displayedMonth.startOfMonth
                    initialized = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        proxy.scrollTo(anchorMonth, anchor: .top)
                    }
                }
            }
        }
    }

    // @State 변수와 anchorMonth(상수)에만 의존 — @Observable 프로퍼티 의존 없음
    private func monthPages() -> [Date] {
        let calendar = Calendar.current
        return (-monthsBefore...monthsAfter).compactMap { offset in
            calendar.date(byAdding: .month, value: offset, to: anchorMonth)?.startOfMonth
        }
    }
}

// 개별 월 섹션
private struct MonthSection: View {
    let month: Date
    let viewModel: CalendarViewModel
    let eventKitService: EventKitService
    let columns: [GridItem]
    let weekdays: [String]

    @State private var eventCounts: [Int: Int]?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(monthHeaderText())
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 8)

            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
            }
            .padding(.horizontal, 16)

            monthGrid()
        }
        .task {
            // 이미 로드된 경우 스킵 — 쿼리 폭주 방지
            if eventCounts == nil {
                eventCounts = eventKitService.eventCountsForMonth(month)
            }
        }
    }

    private func monthHeaderText() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월"
        return formatter.string(from: month)
    }

    private func monthGrid() -> some View {
        let days = viewModel.daysInMonth(for: month)
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                        .onTapGesture {
                            withAnimation(.spring(duration: 0.35, bounce: 0.05)) {
                                viewModel.selectDate(day)
                            }
                        }
                } else {
                    Color.clear
                        .frame(height: 40)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private func dayCell(_ date: Date) -> some View {
        let isToday = date.isToday
        let counts = eventCounts ?? [:]
        let count = min(counts[date.day] ?? 0, 3)

        return VStack(spacing: 4) {
            Text(verbatim: "\(date.day)")
                .font(.system(size: 16, weight: isToday ? .semibold : .regular))
                .foregroundStyle(isToday ? .white : .primary)
                .frame(width: 34, height: 34)
                .background {
                    if isToday {
                        Circle()
                            .fill(.orange)
                    }
                }

            HStack(spacing: 2) {
                ForEach(0..<count, id: \.self) { _ in
                    Circle()
                        .fill(.orange)
                        .frame(width: 4, height: 4)
                }
            }
            .frame(height: 5)
        }
        .frame(height: 40)
    }
}
