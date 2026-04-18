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
    static let uiTestMidnightEventTitle = "UITest Midnight Drag"

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

        // 미완료 리마인더를 전부 가져와서 날짜로 필터링 (predicate 날짜 필터가 불안정하므로)
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: reminderCalendars
        )

        let allReminders: [EKReminder] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { result in
                continuation.resume(returning: result ?? [])
            }
        }

        let calendar = Calendar.current

        let filtered: [EKReminder]
        if let start, let end {
            filtered = allReminders.filter { reminder in
                guard let comps = reminder.dueDateComponents,
                      let dueDate = calendar.date(from: comps) else {
                    // 날짜 없는 리마인더도 포함 (체크리스트용)
                    return true
                }
                return dueDate >= start && dueDate <= end
            }
        } else {
            filtered = allReminders
        }

        return filtered.map { reminder in
            let comps = reminder.dueDateComponents
            let hasTime = comps?.hour != nil
            let dueDate: Date? = {
                guard let comps else { return nil }
                return calendar.date(from: comps)
            }()
            let endDate: Date? = {
                guard let d = dueDate, hasTime else { return dueDate }
                return d.addingTimeInterval(1800)
            }()
            return TicItem(
                id: reminder.calendarItemIdentifier,
                title: reminder.title ?? "",
                notes: reminder.notes,
                startDate: dueDate,
                endDate: endDate,
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
        eventCount(on: date) > 0
    }

    func eventCount(on date: Date) -> Int {
        let start = date.startOfDay
        let end = date.endOfDay
        let calendars: [EKCalendar]? = enabledCalendarIdentifiers.map { ids in
            store.calendars(for: .event).filter { ids.contains($0.calendarIdentifier) }
        }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate).count
    }

    // 메모리 캐시: 월별 이벤트 수
    private var monthCountsCache: [Date: [Int: Int]] = [:]

    // 한 달 전체 이벤트+리마인더 수를 한 번에 계산 (캐시 적용)
    func eventCountsForMonth(_ monthStart: Date) -> [Int: Int] {
        let key = monthStart.startOfMonth
        if let cached = monthCountsCache[key] {
            return cached
        }

        let calendar = Calendar.current
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: key)!

        var counts: [Int: Int] = [:]

        // 캘린더 이벤트
        let eventCals: [EKCalendar]? = enabledCalendarIdentifiers.map { ids in
            store.calendars(for: .event).filter { ids.contains($0.calendarIdentifier) }
        }
        let predicate = store.predicateForEvents(withStart: key, end: monthEnd, calendars: eventCals)
        let events = store.events(matching: predicate)

        for event in events {
            let eventStart = max(event.startDate, key)
            let eventEnd = min(event.endDate, monthEnd)
            var current = eventStart.startOfDay
            while current < eventEnd {
                let day = calendar.component(.day, from: current)
                counts[day, default: 0] += 1
                current = calendar.date(byAdding: .day, value: 1, to: current)!
            }
        }

        // 시간 있는 리마인더
        let reminderCals: [EKCalendar]? = enabledCalendarIdentifiers.map { ids in
            store.calendars(for: .reminder).filter { ids.contains($0.calendarIdentifier) }
        }
        let reminderPredicate = store.predicateForIncompleteReminders(
            withDueDateStarting: key,
            ending: monthEnd,
            calendars: reminderCals
        )

        // 동기적으로 리마인더 fetch (세마포어 사용)
        let semaphore = DispatchSemaphore(value: 0)
        var reminders: [EKReminder] = []
        store.fetchReminders(matching: reminderPredicate) { result in
            reminders = result ?? []
            semaphore.signal()
        }
        semaphore.wait()

        for reminder in reminders {
            if let dueComps = reminder.dueDateComponents,
               let dueDate = calendar.date(from: dueComps),
               dueComps.hour != nil {
                let day = calendar.component(.day, from: dueDate)
                let month = calendar.component(.month, from: dueDate)
                let expectedMonth = calendar.component(.month, from: key)
                if month == expectedMonth {
                    counts[day, default: 0] += 1
                }
            }
        }

        monthCountsCache[key] = counts
        return counts
    }

    func invalidateMonthCache() {
        monthCountsCache.removeAll()
    }

    // MARK: - 쓰기

    @discardableResult
    func createEvent(
        title: String,
        notes: String?,
        start: Date,
        end: Date,
        calendar: EKCalendar,
        isAllDay: Bool = false,
        recurrence: RecurrenceOption,
        alert: AlertTiming
    ) throws -> String {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.notes = notes
        event.startDate = start
        event.endDate = end
        event.calendar = calendar
        event.isAllDay = isAllDay
        if let rule = recurrence.toRule() {
            event.recurrenceRules = [rule]
        }
        if alert != .none {
            event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-alert.rawValue * 60)))
        }
        try store.save(event, span: .thisEvent)
        lastChangeDate = Date()
        updateWidgetCache()
        return event.eventIdentifier
    }

    @discardableResult
    func ensureUITestMidnightEvent(on date: Date) throws -> String? {
        guard calendarAccessGranted else { return nil }
        guard let calendar = preferredWritableEventCalendar() else { return nil }

        let start = Calendar.current.date(
            bySettingHour: 0,
            minute: 0,
            second: 0,
            of: date.startOfDay
        )!
        let end = Calendar.current.date(byAdding: .hour, value: 1, to: start)!
        let predicate = store.predicateForEvents(
            withStart: start,
            end: end,
            calendars: [calendar]
        )

        if let existing = store.events(matching: predicate).first(where: {
            $0.title == Self.uiTestMidnightEventTitle
                && $0.startDate == start
                && $0.endDate == end
        }) {
            return existing.eventIdentifier
        }

        return try createEvent(
            title: Self.uiTestMidnightEventTitle,
            notes: nil,
            start: start,
            end: end,
            calendar: calendar,
            recurrence: .none,
            alert: .none
        )
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
        lastChangeDate = Date()
        updateWidgetCache()
        return reminder.calendarItemIdentifier
    }

    func update(
        _ item: TicItem,
        title: String,
        notes: String?,
        start: Date?,
        end: Date?,
        isAllDay: Bool = false,
        recurrence: RecurrenceOption,
        alert: AlertTiming
    ) throws {
        if let event = item.ekEvent {
            event.title = title
            event.notes = notes
            if let start { event.startDate = start }
            if let end { event.endDate = end }
            event.isAllDay = isAllDay
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
        lastChangeDate = Date()
        updateWidgetCache()
    }

    func delete(_ item: TicItem) throws {
        if let event = item.ekEvent {
            try store.remove(event, span: .thisEvent)
        } else if let reminder = item.ekReminder {
            try store.remove(reminder, commit: true)
        }
        lastChangeDate = Date()
        updateWidgetCache()
    }

    func complete(_ item: TicItem) throws {
        guard let reminder = item.ekReminder else { return }
        reminder.isCompleted = true
        try store.save(reminder, commit: true)
        lastChangeDate = Date()
        updateWidgetCache()
    }

    /// 동일 시간에 일정 복제. 반복 규칙은 제외.
    @discardableResult
    func duplicate(_ item: TicItem) throws -> String {
        if let event = item.ekEvent {
            let newEvent = EKEvent(eventStore: store)
            newEvent.title = event.title
            newEvent.notes = event.notes
            newEvent.calendar = event.calendar
            newEvent.startDate = event.startDate
            newEvent.endDate = event.endDate
            newEvent.isAllDay = event.isAllDay
            // 알림 복사, 반복 규칙은 제외
            event.alarms?.forEach { alarm in
                newEvent.addAlarm(EKAlarm(relativeOffset: alarm.relativeOffset))
            }
            try store.save(newEvent, span: .thisEvent)
            lastChangeDate = Date()
            updateWidgetCache()
            return newEvent.eventIdentifier
        } else if let reminder = item.ekReminder {
            let newReminder = EKReminder(eventStore: store)
            newReminder.title = reminder.title
            newReminder.notes = reminder.notes
            newReminder.calendar = reminder.calendar
            newReminder.dueDateComponents = reminder.dueDateComponents
            // 알림 복사, 반복 규칙은 제외
            reminder.alarms?.forEach { alarm in
                if let absoluteDate = alarm.absoluteDate {
                    newReminder.addAlarm(EKAlarm(absoluteDate: absoluteDate))
                } else {
                    newReminder.addAlarm(EKAlarm(relativeOffset: alarm.relativeOffset))
                }
            }
            try store.save(newReminder, commit: true)
            lastChangeDate = Date()
            updateWidgetCache()
            return newReminder.calendarItemIdentifier
        }
        throw NSError(domain: "EventKitService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No event or reminder to duplicate"])
    }

    /// 일정의 시작/종료 시간을 변경 (날짜 간 이동 또는 같은 날 시간 변경에 사용)
    func moveToDate(_ item: TicItem, newStart: Date, newEnd: Date) throws {
        if let event = item.ekEvent {
            event.startDate = newStart
            event.endDate = newEnd
            try store.save(event, span: .thisEvent)
        } else if let reminder = item.ekReminder {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: newStart
            )
            try store.save(reminder, commit: true)
        }
        lastChangeDate = Date()
        updateWidgetCache()
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
            self?.invalidateMonthCache()
            self?.lastChangeDate = Date()
            self?.updateWidgetCache()
        }
    }

    private func preferredWritableEventCalendar() -> EKCalendar? {
        let writableCalendars = store.calendars(for: .event).filter(\.allowsContentModifications)

        if let enabledCalendarIdentifiers {
            return writableCalendars.first { enabledCalendarIdentifiers.contains($0.calendarIdentifier) }
        }

        if let defaultCalendar = store.defaultCalendarForNewEvents,
           let matchingDefault = writableCalendars.first(where: {
               $0.calendarIdentifier == defaultCalendar.calendarIdentifier
           }) {
            return matchingDefault
        }

        return writableCalendars.first
    }
}
