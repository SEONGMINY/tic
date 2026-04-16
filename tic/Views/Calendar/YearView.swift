import SwiftUI

struct YearView: View {
    var viewModel: CalendarViewModel
    var eventKitService: EventKitService
    var dragCoordinator: CalendarDragCoordinator

    @State private var initialized = false
    @State private var scrollToTodayTrigger = false
    @State private var buttonTapped = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    private let years = Array(1...9999)

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(years, id: \.self) { year in
                            YearSection(
                                year: year,
                                dragCoordinator: dragCoordinator,
                                onMonthTap: { monthNum in
                                    if let date = Calendar.current.date(from: DateComponents(year: year, month: monthNum, day: 1)) {
                                        withAnimation(.spring(duration: 0.35, bounce: 0.05)) {
                                            viewModel.goToMonth(date)
                                        }
                                    }
                                }
                            )
                            .id(year)
                            .onAppear {
                                viewModel.displayedYear = year
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .onAppear {
                    let target = viewModel.displayedYear
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                }
                .onChange(of: scrollToTodayTrigger) { _, _ in
                    let currentYear = Calendar.current.component(.year, from: .now)
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(currentYear, anchor: .top)
                    }
                }
                .onPreferenceChange(CalendarDateFramePreferenceKey.self) { frames in
                    dragCoordinator.updateCalendarFrames(frames, scope: .year)
                }
                .onDisappear {
                    dragCoordinator.updateCalendarFrames([], scope: .year)
                }
            }

            // 올해 버튼
            Button {
                withAnimation(.spring(duration: 0.15)) { buttonTapped = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.spring(duration: 0.15)) { buttonTapped = false }
                }
                scrollToTodayTrigger.toggle()
            } label: {
                Text("올해")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(buttonTapped ? .white : .orange)
                    .padding(.horizontal, 16)
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
}

// 년도 섹션
private struct YearSection: View {
    let year: Int
    let dragCoordinator: CalendarDragCoordinator
    let onMonthTap: (Int) -> Void

    private static let currentMonth = Calendar.current.component(.month, from: .now)
    private static let currentYear = Calendar.current.component(.year, from: .now)
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        let isCurrentYear = year == Self.currentYear

        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: "\(year)년")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(isCurrentYear ? .orange : .primary)
                .padding(.top, 4)

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(1...12, id: \.self) { monthNum in
                    let isCurrentMonth = isCurrentYear && monthNum == Self.currentMonth
                    LightweightMiniMonth(
                        year: year,
                        month: monthNum,
                        isCurrentMonth: isCurrentMonth,
                        dragCoordinator: dragCoordinator
                    )
                        .contentShape(Rectangle())
                        .onTapGesture { onMonthTap(monthNum) }
                }
            }
        }
    }
}

// 경량 미니 월 셀
private struct LightweightMiniMonth: View {
    let year: Int
    let month: Int
    let isCurrentMonth: Bool
    let dragCoordinator: CalendarDragCoordinator

    private static let cal = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 7)

    var body: some View {
        VStack(spacing: 2) {
            Text(verbatim: "\(month)월")
                .font(.system(size: 11, weight: isCurrentMonth ? .bold : .medium))
                .foregroundStyle(isCurrentMonth ? .orange : .secondary)
                .frame(maxWidth: .infinity, alignment: .center)

            Text("일 월 화 수 목 금 토")
                .font(.system(size: 5))
                .foregroundStyle(.quaternary)
                .frame(maxWidth: .infinity, alignment: .center)

            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(date)
                    } else {
                        Color.clear
                            .frame(height: 12)
                    }
                }
            }
        }
    }

    private var days: [Date?] {
        guard let firstDay = Self.cal.date(from: DateComponents(year: year, month: month, day: 1)) else {
            return []
        }
        let weekdayOfFirst = Self.cal.component(.weekday, from: firstDay)
        let range = Self.cal.range(of: .day, in: .month, for: firstDay) ?? 1..<29

        var result: [Date?] = Array(repeating: nil, count: weekdayOfFirst - 1)
        for day in range {
            result.append(
                Self.cal.date(from: DateComponents(year: year, month: month, day: day))
            )
        }
        return result
    }

    private func dayCell(_ date: Date) -> some View {
        let isToday = date.isToday
        let isActiveDropTarget =
            dragCoordinator.snapshot.currentScope == .year &&
            dragCoordinator.isSessionVisible &&
            dragCoordinator.snapshot.activeDate?.isSameDay(as: date) == true

        return Text(verbatim: "\(date.day)")
            .font(.system(size: 7, weight: isToday ? .bold : .light, design: .monospaced))
            .foregroundStyle(isToday ? .white : .primary)
            .frame(maxWidth: .infinity, minHeight: 12)
            .background {
                RoundedRectangle(cornerRadius: 4)
                    .fill(backgroundColor(isToday: isToday, isActiveDropTarget: isActiveDropTarget))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isActiveDropTarget ? Color.orange : Color.clear, lineWidth: 1.5)
                    }
            }
            .reportCalendarDateFrame(date)
    }

    private func backgroundColor(
        isToday: Bool,
        isActiveDropTarget: Bool
    ) -> Color {
        if isToday {
            return .orange
        }
        if isActiveDropTarget {
            return .orange.opacity(0.12)
        }
        return .clear
    }
}
