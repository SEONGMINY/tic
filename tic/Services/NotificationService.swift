import UserNotifications

class NotificationService {
    private let center = UNUserNotificationCenter.current()

    init() {
        registerCategories()
    }

    func requestPermission() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func schedule(for item: TicItem, alert: AlertTiming) {
        guard alert != .none, let startDate = item.startDate else { return }

        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.isReminder ? "리마인더" : "\(alert.displayName)"
        content.sound = .default
        content.categoryIdentifier = "TIC_EVENT"

        let triggerDate = startDate.addingTimeInterval(TimeInterval(-alert.rawValue * 60))
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: triggerDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(identifier: item.id, content: content, trigger: trigger)
        center.add(request)
    }

    func scheduleSnooze(for identifier: String, minutes: Int = 10) {
        let content = UNMutableNotificationContent()
        content.title = "스누즈 알림"
        content.body = "스누즈한 일정이 있습니다."
        content.sound = .default
        content.categoryIdentifier = "TIC_EVENT"

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(minutes * 60),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: "\(identifier)-snooze",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    func cancel(for identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier, "\(identifier)-snooze"])
    }

    private func registerCategories() {
        let completeAction = UNNotificationAction(
            identifier: "COMPLETE",
            title: "완료",
            options: [.destructive]
        )
        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE",
            title: "10분 후",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: "TIC_EVENT",
            actions: [completeAction, snoozeAction],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])
    }
}
