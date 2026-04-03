import AppIntents
import EventKit
import UserNotifications
import WidgetKit

// MARK: - CGColor → Hex (widget target)

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
        if let reminder = store.calendarItem(withIdentifier: eventIdentifier) as? EKReminder {
            reminder.isCompleted = true
            try store.save(reminder, commit: true)
        }
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
        let content = UNMutableNotificationContent()
        content.title = "스누즈 알림"
        content.body = "스누즈한 일정이 있습니다."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(eventIdentifier)-snooze",
            content: content,
            trigger: trigger
        )
        try await center.add(request)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
