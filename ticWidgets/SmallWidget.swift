import SwiftUI
import WidgetKit

struct SmallTicWidget: Widget {
    let kind: String = "SmallTicWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TicWidgetProvider()) { entry in
            SmallWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("tic")
        .description("다음 일정을 확인하세요")
        .supportedFamilies([.systemSmall])
    }
}

struct SmallWidgetView: View {
    var entry: TicWidgetEntry

    private var upcomingEvents: [WidgetEventItem] {
        Array(entry.events.filter { !$0.isCompleted }.prefix(3))
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: entry.date)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 상단: 요일 + 날짜 (컴팩트)
            HStack(alignment: .bottom, spacing: 6) {
                Text(verbatim: "\(Calendar.current.component(.day, from: entry.date))")
                    .font(.system(size: 26, weight: .bold))

                Text(weekdayText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)

                Spacer()
            }

            Spacer().frame(height: 8)

            // 일정 리스트
            if upcomingEvents.isEmpty {
                Spacer()
                Text("일정 없음")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(upcomingEvents, id: \.id) { event in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color(hex: event.calendarColorHex))
                                .frame(width: 6, height: 6)

                            Text(event.title)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        }

                        if let start = event.startDate, !event.isAllDay {
                            HStack(spacing: 0) {
                                Spacer().frame(width: 11)
                                Text(Self.timeFormatter.string(from: start))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, -4)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .widgetURL(URL(string: "tic://day?date=\(dateString)")!)
    }

    private var weekdayText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: entry.date)
    }
}
