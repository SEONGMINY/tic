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

    private var nextEvent: WidgetEventItem? {
        entry.events.first { !$0.isCompleted }
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: entry.date)
    }

    var body: some View {
        Group {
            if let event = nextEvent {
                VStack(alignment: .leading, spacing: 8) {
                    Text("tic")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.orange)

                    Spacer()

                    Text(event.title)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(2)

                    HStack {
                        if let start = event.startDate, !event.isAllDay {
                            let formatter = {
                                let f = DateFormatter()
                                f.dateFormat = "HH:mm"
                                return f
                            }()
                            Text(formatter.string(from: start))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        } else if event.isAllDay {
                            Text("종일")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if event.isReminder {
                            Button(intent: CompleteEventIntent(eventIdentifier: event.id)) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.orange)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Text("tic")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.orange)
                    Spacer()
                    Text("예정된 일정이\n없습니다")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
            }
        }
        .widgetURL(URL(string: "tic://day?date=\(dateString)")!)
    }
}
