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

    private var headerDateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 EEEE"
        return formatter.string(from: entry.date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("tic")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.orange)
                Spacer()
                Text(headerDateString)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if upcomingEvents.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text("예정된 일정이 없습니다")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Spacer()
            } else {
                ForEach(upcomingEvents, id: \.id) { event in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: event.calendarColorHex))
                            .frame(width: 6, height: 6)

                        if let start = event.startDate, !event.isAllDay {
                            let formatter = {
                                let f = DateFormatter()
                                f.dateFormat = "HH:mm"
                                return f
                            }()
                            Text(formatter.string(from: start))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .leading)
                        } else {
                            Text("종일")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .leading)
                        }

                        Text(event.title)
                            .font(.system(size: 13))
                            .lineLimit(1)

                        Spacer()

                        if event.isReminder {
                            Button(intent: CompleteEventIntent(eventIdentifier: event.id)) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.orange)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if remainingCount > 0 {
                    Text("+\(remainingCount)개 더")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .widgetURL(URL(string: "tic://day?date=\(dateString)")!)
    }
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
