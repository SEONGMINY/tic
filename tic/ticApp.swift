import SwiftUI
import SwiftData

@main
struct ticApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [SearchHistory.self, CalendarSelection.self, NotificationMeta.self])
    }
}
