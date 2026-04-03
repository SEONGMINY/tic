import WidgetKit
import Foundation

struct TicWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TicWidgetEntry {
        TicWidgetEntry(date: .now, events: [], eventDateStrings: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (TicWidgetEntry) -> Void) {
        let events = WidgetCache.load()
        let dateStrings = Self.eventDateStrings(from: events)
        completion(TicWidgetEntry(date: .now, events: events, eventDateStrings: dateStrings))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TicWidgetEntry>) -> Void) {
        let events = WidgetCache.load()
        let dateStrings = Self.eventDateStrings(from: events)
        let entry = TicWidgetEntry(date: .now, events: events, eventDateStrings: dateStrings)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private static func eventDateStrings(from events: [WidgetEventItem]) -> Set<String> {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        var strings = Set<String>()
        for event in events {
            if let start = event.startDate {
                strings.insert(formatter.string(from: start))
            }
        }
        return strings
    }
}

struct TicWidgetEntry: TimelineEntry {
    let date: Date
    let events: [WidgetEventItem]
    let eventDateStrings: Set<String>
}
