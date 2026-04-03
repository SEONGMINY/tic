import EventKit
import SwiftUI
import WidgetKit

enum RecurrenceOption: String, CaseIterable {
    case none = "없음"
    case daily = "매일"
    case weekly = "매주"
    case biweekly = "2주마다"
    case monthly = "매월"
    case yearly = "매년"

    func toRule() -> EKRecurrenceRule? {
        switch self {
        case .none: return nil
        case .daily: return EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        case .weekly: return EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
        case .biweekly: return EKRecurrenceRule(recurrenceWith: .weekly, interval: 2, end: nil)
        case .monthly: return EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: nil)
        case .yearly: return EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)
        }
    }
}

enum AlertTiming: Int, CaseIterable {
    case none = 0
    case fiveMin = 5
    case fifteenMin = 15
    case thirtyMin = 30
    case oneHour = 60

    var displayName: String {
        switch self {
        case .none: return "없음"
        case .fiveMin: return "5분 전"
        case .fifteenMin: return "15분 전"
        case .thirtyMin: return "30분 전"
        case .oneHour: return "1시간 전"
        }
    }
}

@Observable
class EventKitService {
    private let store = EKEventStore()
    var calendarAccessGranted = false
    var reminderAccessGranted = false
    var lastChangeDate = Date()
    var enabledCalendarIdentifiers: Set<String>?

    // MARK: - 권한 요청

    func requestCalendarAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            calendarAccessGranted = granted
            return granted
        } catch {
            return false
        }
    }

    func requestReminderAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToReminders()
            reminderAccessGranted = granted
            return granted
        } catch {
            return false
        }
    }

    // MARK: - 읽기

    func fetchEvents(from start: Date, to end: Date) -> [TicItem] {
        let calendars: [EKCalendar]? = enabledCalendarIdentifiers.map { ids in
            store.calendars(for: .event).filter { ids.contains($0.calendarIdentifier) }
        }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let events = store.events(matching: predicate)
        return events.map { event in
            TicItem(
                id: event.eventIdentifier,
                title: event.title ?? "",
                notes: event.notes,
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay,
                isCompleted: false,
                isReminder: false,
                hasTime: true,
                calendarTitle: event.calendar.title,
                calendarColor: event.calendar.cgColor,
                recurrenceRule: event.recurrenceRules?.first,
                ekEvent: event,
                ekReminder: nil
            )
        }
    }

    func fetchReminders(from start: Date?, to end: Date?) async -> [TicItem] {
        let reminderCalendars: [EKCalendar]? = enabledCalendarIdentifiers.map { ids in
            store.calendars(for: .reminder).filter { ids.contains($0.calendarIdentifier) }
        }
        let predicate: NSPredicate
        if let start, let end {
            predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: start,
                ending: end,
                calendars: reminderCalendars
            )
        } else {
            predicate = store.predicateForReminders(in: reminderCalendars)
        }

        let reminders: [EKReminder] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { result in
                continuation.resume(returning: result ?? [])
            }
        }

        return reminders.map { reminder in
            let dueDate = reminder.dueDateComponents?.date
            let hasTime = reminder.dueDateComponents?.hour != nil
            return TicItem(
                id: reminder.calendarItemIdentifier,
                title: reminder.title ?? "",
                notes: reminder.notes,
                startDate: dueDate,
                endDate: dueDate,
                isAllDay: false,
                isCompleted: reminder.isCompleted,
                isReminder: true,
                hasTime: hasTime,
                calendarTitle: reminder.calendar.title,
                calendarColor: reminder.calendar.cgColor,
                recurrenceRule: reminder.recurrenceRules?.first,
                ekEvent: nil,
                ekReminder: reminder
            )
        }
    }

    func fetchAllItems(for date: Date) async -> [TicItem] {
        let start = date.startOfDay
        let end = date.endOfDay
        let events = fetchEvents(from: start, to: end)
        let reminders = await fetchReminders(from: start, to: end)
        return (events + reminders).sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    func hasEvents(on date: Date) -> Bool {
        let start = date.startOfDay
        let end = date.endOfDay
        let calendars: [EKCalendar]? = enabledCalendarIdentifiers.map { ids in
            store.calendars(for: .event).filter { ids.contains($0.calendarIdentifier) }
        }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return !store.events(matching: predicate).isEmpty
    }

    // MARK: - 쓰기

    @discardableResult
    func createEvent(
        title: String,
        notes: String?,
        start: Date,
        end: Date,
        calendar: EKCalendar,
        recurrence: RecurrenceOption,
        alert: AlertTiming
    ) throws -> String {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.notes = notes
        event.startDate = start
        event.endDate = end
        event.calendar = calendar
        if let rule = recurrence.toRule() {
            event.recurrenceRules = [rule]
        }
        if alert != .none {
            event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-alert.rawValue * 60)))
        }
        try store.save(event, span: .thisEvent)
        return event.eventIdentifier
    }

    @discardableResult
    func createReminder(
        title: String,
        notes: String?,
        dueDate: Date?,
        list: EKCalendar,
        alert: AlertTiming
    ) throws -> String {
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = list
        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        }
        if alert != .none, let dueDate {
            reminder.addAlarm(EKAlarm(absoluteDate: dueDate.addingTimeInterval(TimeInterval(-alert.rawValue * 60))))
        }
        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    func update(
        _ item: TicItem,
        title: String,
        notes: String?,
        start: Date?,
        end: Date?,
        recurrence: RecurrenceOption,
        alert: AlertTiming
    ) throws {
        if let event = item.ekEvent {
            event.title = title
            event.notes = notes
            if let start { event.startDate = start }
            if let end { event.endDate = end }
            event.recurrenceRules = nil
            if let rule = recurrence.toRule() {
                event.recurrenceRules = [rule]
            }
            event.alarms?.forEach { event.removeAlarm($0) }
            if alert != .none {
                event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-alert.rawValue * 60)))
            }
            try store.save(event, span: .thisEvent)
        } else if let reminder = item.ekReminder {
            reminder.title = title
            reminder.notes = notes
            if let start {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: start
                )
            }
            reminder.recurrenceRules = nil
            if let rule = recurrence.toRule() {
                reminder.recurrenceRules = [rule]
            }
            reminder.alarms?.forEach { reminder.removeAlarm($0) }
            if alert != .none, let start {
                reminder.addAlarm(EKAlarm(absoluteDate: start.addingTimeInterval(TimeInterval(-alert.rawValue * 60))))
            }
            try store.save(reminder, commit: true)
        }
    }

    func delete(_ item: TicItem) throws {
        if let event = item.ekEvent {
            try store.remove(event, span: .thisEvent)
        } else if let reminder = item.ekReminder {
            try store.remove(reminder, commit: true)
        }
    }

    func complete(_ item: TicItem) throws {
        guard let reminder = item.ekReminder else { return }
        reminder.isCompleted = true
        try store.save(reminder, commit: true)
    }

    // MARK: - 캘린더 목록

    func availableCalendars() -> [EKCalendar] {
        store.calendars(for: .event)
    }

    func availableReminderLists() -> [EKCalendar] {
        store.calendars(for: .reminder)
    }

    // MARK: - 위젯 캐시

    func updateWidgetCache() {
        let now = Date()
        let end = now.adding(days: 7)
        let events = fetchEvents(from: now, to: end)
        let widgetItems = Array(events.prefix(20).map { item in
            WidgetEventItem(
                id: item.id,
                title: item.title,
                startDate: item.startDate,
                endDate: item.endDate,
                isReminder: item.isReminder,
                isCompleted: item.isCompleted,
                calendarColorHex: item.calendarColor.hexString,
                isAllDay: item.isAllDay
            )
        })
        WidgetCache.save(events: widgetItems)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - 변경 감지

    func startObservingChanges() {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            self?.lastChangeDate = Date()
            self?.updateWidgetCache()
        }
    }
}
