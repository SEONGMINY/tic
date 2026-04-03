import AppIntents
import ActivityKit
import EventKit
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

    @Parameter(title: "Event ID")
    var eventIdentifier: String

    init() {}

    init(eventIdentifier: String) {
        self.eventIdentifier = eventIdentifier
    }

    func perform() async throws -> some IntentResult {
        let store = EKEventStore()

        // 리마인더 완료 처리
        if let reminder = store.calendarItem(withIdentifier: eventIdentifier) as? EKReminder {
            reminder.isCompleted = true
            try store.save(reminder, commit: true)
        }

        // Live Activity 종료
        for activity in Activity<TicActivityAttributes>.activities {
            if activity.attributes.eventIdentifier == eventIdentifier {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        // 위젯 캐시 갱신
        WidgetCache.save(events: buildUpdatedCache(store: store))
        WidgetCenter.shared.reloadAllTimelines()

        return .result()
    }

    private func buildUpdatedCache(store: EKEventStore) -> [WidgetEventItem] {
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 7, to: now)!
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let events = store.events(matching: predicate)
        return Array(events.prefix(20).map { event in
            WidgetEventItem(
                id: event.eventIdentifier,
                title: event.title ?? "",
                startDate: event.startDate,
                endDate: event.endDate,
                isReminder: false,
                isCompleted: false,
                calendarColorHex: event.calendar.cgColor.hexString,
                isAllDay: event.isAllDay
            )
        })
    }
}

struct SnoozeEventIntent: AppIntent {
    static var title: LocalizedStringResource = "10분 후 알림"

    @Parameter(title: "Event ID")
    var eventIdentifier: String

    init() {}

    init(eventIdentifier: String) {
        self.eventIdentifier = eventIdentifier
    }

    func perform() async throws -> some IntentResult {
        let center = UNUserNotificationCenter.current()

        // 기존 알림 제거
        center.removePendingNotificationRequests(withIdentifiers: ["\(eventIdentifier)-snooze"])

        // 10분 후 알림 등록
        let content = UNMutableNotificationContent()
        content.title = "일정 알림"
        content.body = "스누즈한 일정을 확인하세요."
        content.sound = .default
        content.categoryIdentifier = "TIC_EVENT"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(eventIdentifier)-snooze",
            content: content,
            trigger: trigger
        )
        try await center.add(request)

        // Live Activity 업데이트 (스누즈 상태 표시)
        for activity in Activity<TicActivityAttributes>.activities {
            if activity.attributes.eventIdentifier == eventIdentifier {
                // Activity를 유지하되 갱신
                let state = activity.content.state
                await activity.update(
                    ActivityContent(state: state, staleDate: Date().addingTimeInterval(600))
                )
            }
        }

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
