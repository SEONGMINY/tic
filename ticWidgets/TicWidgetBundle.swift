import WidgetKit
import SwiftUI

@main
struct TicWidgetBundle: WidgetBundle {
    var body: some Widget {
        TicPlaceholderWidget()
    }
}

struct TicPlaceholderWidget: Widget {
    let kind: String = "TicWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TicPlaceholderProvider()) { _ in
            Text("tic")
        }
        .configurationDisplayName("tic")
        .description("tic 위젯")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TicPlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> TicPlaceholderEntry {
        TicPlaceholderEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (TicPlaceholderEntry) -> Void) {
        completion(TicPlaceholderEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TicPlaceholderEntry>) -> Void) {
        let entry = TicPlaceholderEntry(date: Date())
        let timeline = Timeline(entries: [entry], policy: .atEnd)
        completion(timeline)
    }
}

struct TicPlaceholderEntry: TimelineEntry {
    let date: Date
}
