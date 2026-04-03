import SwiftUI
import SwiftData

@main
struct ticApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { _ in
                    // 딥링크 처리 (위젯 → 앱) — Phase 7에서 완성
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
