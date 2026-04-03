import WidgetKit

struct TicWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TicWidgetEntry {
        TicWidgetEntry(date: .now, events: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (TicWidgetEntry) -> Void) {
        let events = WidgetCache.load()
        completion(TicWidgetEntry(date: .now, events: events))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TicWidgetEntry>) -> Void) {
        let events = WidgetCache.load()
        let entry = TicWidgetEntry(date: .now, events: events)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct TicWidgetEntry: TimelineEntry {
    let date: Date
    let events: [WidgetEventItem]
}
