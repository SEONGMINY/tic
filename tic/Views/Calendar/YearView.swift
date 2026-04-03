import SwiftUI

struct YearView: View {
    var viewModel: CalendarViewModel
    var eventKitService: EventKitService

    @State private var anchorYear: Int = Calendar.current.component(.year, from: .now)
    @State private var initialized = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    // 고정 범위. 동적 확장 없음 — 스크롤 끊김 제거.
    // Apple Calendar과 동일: 1년~9999년

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(yearsRange, id: \.self) { year in
                            YearSection(year: year, onMonthTap: { monthNum in
                                if let date = Calendar.current.date(from: DateComponents(year: year, month: monthNum, day: 1)) {
                                    withAnimation(.spring(duration: 0.35, bounce: 0.05)) {
                                        viewModel.goToMonth(date)
                                    }
                                }
                            })
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
                    if !initialized {
                        anchorYear = viewModel.displayedYear
                        initialized = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            proxy.scrollTo(anchorYear, anchor: .top)
                        }
                    }
                }
                .onChange(of: scrollToToday) { _, _ in
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(Calendar.current.component(.year, from: .now), anchor: .top)
                    }
                }
            }

            // 오늘 버튼
            Button {
                scrollToToday.toggle()
            } label: {
                Text("오늘")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
            .padding(.leading, 16)
            .padding(.bottom, 16)
        }
    }

    @State private var scrollToToday = false

    private var yearsRange: [Int] {
        Array(1...9999)
    }
}

// 년도 섹션 — 별도 struct로 분리하여 불필요한 리렌더 방지
private struct YearSection: View {
    let year: Int
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
                    LightweightMiniMonth(year: year, month: monthNum, isCurrentMonth: isCurrentMonth)
                        .contentShape(Rectangle())
                        .onTapGesture { onMonthTap(monthNum) }
                }
            }
        }
    }
}

// 극도로 경량화된 미니 월 — 단순 Text만 사용
private struct LightweightMiniMonth: View {
    let year: Int
    let month: Int
    let isCurrentMonth: Bool

    private static let cal = Calendar.current
    private static let todayDay = Calendar.current.component(.day, from: .now)
    private static let todayMonth = Calendar.current.component(.month, from: .now)
    private static let todayYear = Calendar.current.component(.year, from: .now)

    var body: some View {
        VStack(spacing: 2) {
            Text(verbatim: "\(month)월")
                .font(.system(size: 11, weight: isCurrentMonth ? .bold : .medium))
                .foregroundStyle(isCurrentMonth ? .orange : .secondary)
                .frame(maxWidth: .infinity, alignment: .center)

            // 요일 헤더
            Text("일 월 화 수 목 금 토")
                .font(.system(size: 5))
                .foregroundStyle(.quaternary)
                .frame(maxWidth: .infinity, alignment: .center)

            // 날짜
            Text(daysText)
                .font(.system(size: 7, weight: .light, design: .monospaced))
                .foregroundStyle(.primary)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // 날짜를 단순 문자열로 생성 — 뷰 갯수 최소화
    private var daysText: String {
        guard let firstDay = Self.cal.date(from: DateComponents(year: year, month: month, day: 1)) else {
            return ""
        }
        let weekdayOfFirst = Self.cal.component(.weekday, from: firstDay)
        let range = Self.cal.range(of: .day, in: .month, for: firstDay) ?? 1..<29

        var lines: [String] = []
        var currentLine = String(repeating: "   ", count: weekdayOfFirst - 1)
        var dayOfWeek = weekdayOfFirst

        for day in range {
            let dayStr = day < 10 ? " \(day) " : "\(day) "
            currentLine += dayStr
            if dayOfWeek == 7 {
                lines.append(currentLine)
                currentLine = ""
                dayOfWeek = 1
            } else {
                dayOfWeek += 1
            }
        }
        if !currentLine.isEmpty {
            lines.append(currentLine)
        }
        return lines.joined(separator: "\n")
    }
}
