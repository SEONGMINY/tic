import SwiftUI

struct MonthView: View {
    var viewModel: CalendarViewModel
    var eventKitService: EventKitService

    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    private let weekdays = ["일", "월", "화", "수", "목", "금", "토"]

    // 기준점: 2026년 1월 (고정). 모든 offset은 이 기준으로 계산.
    private static let baseDate: Date = {
        Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1))!
    }()
    // ±120개월 = ±10년 (2016년 1월 ~ 2036년 1월)
    private let rangeStart = -120
    private let rangeEnd = 120

    @State private var scrollToThisMonthTrigger = false
    @State private var buttonTapped = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(rangeStart...rangeEnd, id: \.self) { offset in
                            let month = Self.monthDate(offset: offset)
                            MonthSection(
                                month: month,
                                viewModel: viewModel,
                                eventKitService: eventKitService,
                                columns: columns,
                                weekdays: weekdays
                            )
                            .id(offset)
                            .onAppear {
                                viewModel.displayedYear = month.year
                            }
                        }
                    }
                }
                .onAppear {
                    let targetOffset = Self.offsetForDate(viewModel.displayedMonth)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        proxy.scrollTo(targetOffset, anchor: .top)
                    }
                }
                .onChange(of: scrollToThisMonthTrigger) { _, _ in
                    let currentOffset = Self.offsetForDate(Date())
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(currentOffset, anchor: .top)
                    }
                }
            }

            // 이번달 버튼
            Button {
                withAnimation(.spring(duration: 0.15)) { buttonTapped = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.spring(duration: 0.15)) { buttonTapped = false }
                }
                scrollToThisMonthTrigger.toggle()
            } label: {
                Text("이번달")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(buttonTapped ? .white : .orange)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(buttonTapped ? Color.orange : Color.clear)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
            .scaleEffect(buttonTapped ? 1.15 : 1.0)
            .padding(.leading, 16)
            .padding(.bottom, 16)
        }
    }

    // offset → Date 변환 (baseDate 기준)
    private static func monthDate(offset: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: offset, to: baseDate)!.startOfMonth
    }

    // Date → offset 변환
    private static func offsetForDate(_ date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.month], from: baseDate, to: date.startOfMonth)
        return comps.month ?? 0
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
        let isWeekend = date.weekday == 1 || date.weekday == 7

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
