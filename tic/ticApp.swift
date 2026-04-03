import SwiftUI
import SwiftData

extension Notification.Name {
    static let ticDeepLinkDate = Notification.Name("ticDeepLinkDate")
}

@main
struct ticApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    guard url.scheme == "tic", url.host == "day" else { return }
                    if let dateString = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "date" })?.value {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        if let date = formatter.date(from: dateString) {
                            NotificationCenter.default.post(
                                name: .ticDeepLinkDate,
                                object: nil,
                                userInfo: ["date": date]
                            )
                        }
                    }
                }
        }
        .modelContainer(for: [SearchHistory.self, CalendarSelection.self, NotificationMeta.self])
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier
        let eventKitService = EventKitService()
        let liveActivityService = LiveActivityService()
        let notificationService = NotificationService()

        switch response.actionIdentifier {
        case "COMPLETE":
            let items = await eventKitService.fetchAllItems(for: Date())
            if let item = items.first(where: { $0.id == identifier }) {
                try? eventKitService.complete(item)
                liveActivityService.end(for: identifier)
            }
        case "SNOOZE":
            notificationService.scheduleSnooze(for: identifier)
        default:
            // 알림 탭 → Live Activity 시작
            let items = await eventKitService.fetchAllItems(for: Date())
            if let item = items.first(where: { $0.id == identifier }) {
                try? liveActivityService.start(for: item)
            }
        }
    }
}
