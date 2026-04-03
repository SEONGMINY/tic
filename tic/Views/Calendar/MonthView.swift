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
    @State private var isExpanding = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    let pages = allPages
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
                            expandIfNeeded(index: index, total: pages.count)
                        }
                    }
                }
            }
            .onAppear {
                if !initialized {
                    anchorMonth = viewModel.displayedMonth.startOfMonth
                    initialized = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        proxy.scrollTo(anchorMonth, anchor: .top)
                    }
                }
            }
        }
    }

    // 캐시된 배열 — body 내에서 1회만 계산
    private var allPages: [Date] {
        let calendar = Calendar.current
        return (-monthsBefore...monthsAfter).compactMap { offset in
            calendar.date(byAdding: .month, value: offset, to: anchorMonth)?.startOfMonth
        }
    }

    // debounce + 플래그로 무한 루프 방지
    private func expandIfNeeded(index: Int, total: Int) {
        guard !isExpanding else { return }
        let needsExpand: Bool
        if index <= 3 {
            needsExpand = true
        } else if index >= total - 4 {
            needsExpand = true
        } else {
            needsExpand = false
        }
        guard needsExpand else { return }

        isExpanding = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if index <= 3 {
                monthsBefore += 24
            } else {
                monthsAfter += 24
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isExpanding = false
            }
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
        let isWeekend = date.weekday == 1 || date.weekday == 7  // 일=1, 토=7

        return VStack(spacing: 4) {
            Text(verbatim: "\(date.day)")
                .font(.system(size: 16, weight: isToday ? .semibold : .regular))
                .foregroundStyle(isToday ? .white : (isWeekend ? .secondary : .primary))
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
