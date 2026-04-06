import SwiftUI
import WidgetKit

struct MediumTicWidget: Widget {
    let kind: String = "MediumTicWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TicWidgetProvider()) { entry in
            MediumWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("tic")
        .description("오늘의 일정을 한눈에")
        .supportedFamilies([.systemMedium])
    }
}

struct MediumWidgetView: View {
    var entry: TicWidgetEntry

    private var upcomingEvents: [WidgetEventItem] {
        Array(entry.events.filter { !$0.isCompleted }.prefix(4))
    }

    private var remainingCount: Int {
        let total = entry.events.filter { !$0.isCompleted }.count
        return max(0, total - 4)
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: entry.date)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // MARK: - Left: Event List (~55%)
            VStack(alignment: .leading, spacing: 4) {
                if upcomingEvents.isEmpty {
                    Spacer()
                    Text("예정된 일정이 없습니다")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ForEach(upcomingEvents, id: \.id) { event in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color(hex: event.calendarColorHex))
                                    .frame(width: 6, height: 6)
                                Text(event.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                            }
                            HStack(spacing: 0) {
                                // Indent to align with title (dot + spacing)
                                Color.clear.frame(width: 10, height: 1)
                                if let start = event.startDate {
                                    let df = Self.dateTimeFormatter
                                    Text(event.isAllDay ? "종일" : df.string(from: start))
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("종일")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if remainingCount > 0 {
                        Text("+\(remainingCount)개 더")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // MARK: - Right: Mini Calendar (~45%)
            MiniCalendarView(
                currentDate: entry.date,
                eventDates: entry.eventDateStrings
            )
            .frame(maxWidth: .infinity)
        }
        .widgetURL(URL(string: "tic://day?date=\(dateString)")!)
    }

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd - h:mm a"
        return f
    }()
}

// MARK: - Mini Calendar View

struct MiniCalendarView: View {
    let currentDate: Date
    let eventDates: Set<String>

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let weekdaySymbols = ["일", "월", "화", "수", "목", "금", "토"]

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M월"
        return formatter.string(from: currentDate)
    }

    private var todayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: currentDate)
    }

    private var calendarDays: [CalendarDay] {
        let comps = calendar.dateComponents([.year, .month], from: currentDate)
        guard let firstOfMonth = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: firstOfMonth) // 1=Sun
        let leadingBlanks = firstWeekday - 1

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        var days: [CalendarDay] = []

        // Leading blanks
        for _ in 0..<leadingBlanks {
            days.append(CalendarDay(day: 0, dateString: "", isToday: false, hasEvent: false))
        }

        // Actual days
        for day in range {
            var dayComps = comps
            dayComps.day = day
            let dateStr: String
            if let d = calendar.date(from: dayComps) {
                dateStr = formatter.string(from: d)
            } else {
                dateStr = ""
            }
            let isToday = dateStr == todayString
            let hasEvent = eventDates.contains(dateStr)
            days.append(CalendarDay(day: day, dateString: dateStr, isToday: isToday, hasEvent: hasEvent))
        }

        return days
    }

    var body: some View {
        VStack(spacing: 2) {
            // Month title
            Text(monthTitle)
                .font(.system(size: 10, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .trailing)

            // Weekday headers
            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Day grid
            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(Array(calendarDays.enumerated()), id: \.offset) { _, day in
                    if day.day == 0 {
                        Text("")
                            .frame(maxWidth: .infinity, minHeight: 12)
                    } else {
                        VStack(spacing: 0) {
                            Text("\(day.day)")
                                .font(.system(size: 9, weight: day.hasEvent ? .bold : .regular))
                                .foregroundStyle(day.isToday ? .white : .primary)
                                .frame(width: 16, height: 16)
                                .background {
                                    if day.isToday {
                                        Circle().fill(Color.orange)
                                    }
                                }
                            if day.hasEvent && !day.isToday {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 2.5, height: 2.5)
                            } else {
                                Color.clear.frame(width: 2.5, height: 2.5)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

private struct CalendarDay {
    let day: Int
    let dateString: String
    let isToday: Bool
    let hasEvent: Bool
}

// MARK: - Color from Hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
