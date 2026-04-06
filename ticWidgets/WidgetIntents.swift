import AppIntents
import ActivityKit
import CoreGraphics
import UserNotifications
import WidgetKit

// MARK: - CGColor → Hex

extension CGColor {
    var hexString: String {
        guard let components = converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil)?.components,
              components.count >= 3 else {
            return "#FF6B35"
        }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

struct CompleteEventIntent: AppIntent {
    static var title: LocalizedStringResource = "완료"
    static var openAppWhenRun: Bool = true  // 앱을 열어서 메인 앱에서 완료 처리

    @Parameter(title: "Event ID")
    var eventIdentifier: String

    init() {}

    init(eventIdentifier: String) {
        self.eventIdentifier = eventIdentifier
    }

    func perform() async throws -> some IntentResult {
        // Live Activity 종료
        for activity in Activity<TicActivityAttributes>.activities {
            let finalContent = ActivityContent(state: activity.content.state, staleDate: nil)
            await activity.end(finalContent, dismissalPolicy: .immediate)
        }

        // 앱에 완료 이벤트 전달 (메인 앱에서 EventKit 처리)
        NotificationCenter.default.post(
            name: Notification.Name("ticCompleteEvent"),
            object: nil,
            userInfo: ["eventIdentifier": eventIdentifier]
        )

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct SnoozeEventIntent: AppIntent {
    static var title: LocalizedStringResource = "10분 후 알림"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Event ID")
    var eventIdentifier: String

    init() {}

    init(eventIdentifier: String) {
        self.eventIdentifier = eventIdentifier
    }

    func perform() async throws -> some IntentResult {
        // 10분 후 로컬 알림 등록
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["\(eventIdentifier)-snooze"])

        let content = UNMutableNotificationContent()
        content.title = "일정 알림"
        content.body = "스누즈한 일정을 확인하세요."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(eventIdentifier)-snooze",
            content: content,
            trigger: trigger
        )
        try await center.add(request)

        // Live Activity 종료
        for activity in Activity<TicActivityAttributes>.activities {
            let finalContent = ActivityContent(state: activity.content.state, staleDate: nil)
            await activity.end(finalContent, dismissalPolicy: .immediate)
        }

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
