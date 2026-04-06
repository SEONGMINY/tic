import EventKit
import SwiftUI

@Observable
class EventFormViewModel {
    // 폼 상태
    var title: String = ""
    var notes: String = ""
    var selectedCalendar: EKCalendar?
    var isCalendarType: Bool = true
    var startDate: Date?
    var endDate: Date?
    var isAllDay: Bool = false
    var recurrence: RecurrenceOption = .none
    var alertTiming: AlertTiming = .thirtyMin

    // 수정 모드
    var editingItem: TicItem?
    var isEditMode: Bool { editingItem != nil }

    // 유효성
    var canSave: Bool {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard selectedCalendar != nil else { return false }
        if isCalendarType {
            guard startDate != nil, endDate != nil else { return false }
        }
        return true
    }

    // MARK: - 초기화

    func prepareForCreate() {
        title = ""
        notes = ""
        selectedCalendar = nil
        isCalendarType = true
        isAllDay = false
        startDate = nil
        endDate = nil
        recurrence = .none
        alertTiming = .thirtyMin
        editingItem = nil
    }

    func prepareForCreate(at date: Date) {
        prepareForCreate()
        startDate = date
        endDate = date.addingTimeInterval(3600)
        isCalendarType = true
    }

    func prepareForEdit(_ item: TicItem, service: EventKitService) {
        title = item.title
        notes = item.notes ?? ""
        isCalendarType = !item.isReminder
        isAllDay = item.isAllDay
        startDate = item.startDate
        endDate = item.endDate
        editingItem = item

        // 캘린더 매칭
        let calendars = isCalendarType ? service.availableCalendars() : service.availableReminderLists()
        selectedCalendar = calendars.first { $0.title == item.calendarTitle }

        // 반복 매칭
        if let rule = item.recurrenceRule {
            switch rule.frequency {
            case .daily: recurrence = .daily
            case .weekly: recurrence = rule.interval == 2 ? .biweekly : .weekly
            case .monthly: recurrence = .monthly
            case .yearly: recurrence = .yearly
            @unknown default: recurrence = .none
            }
        } else {
            recurrence = .none
        }

        // 알림 매칭
        if let alarm = item.ekEvent?.alarms?.first {
            let minutes = Int(-alarm.relativeOffset / 60)
            alertTiming = AlertTiming(rawValue: minutes) ?? .thirtyMin
        } else if let alarm = item.ekReminder?.alarms?.first, let absoluteDate = alarm.absoluteDate, let start = item.startDate {
            let minutes = Int(start.timeIntervalSince(absoluteDate) / 60)
            alertTiming = AlertTiming(rawValue: minutes) ?? .thirtyMin
        } else {
            alertTiming = .thirtyMin
        }
    }

    // MARK: - 저장

    func save(service: EventKitService, notificationService: NotificationService) async throws {
        // 첫 저장 시 알림 권한 요청
        if !UserDefaults.standard.bool(forKey: "notificationPermissionRequested") {
            await notificationService.requestPermission()
            UserDefaults.standard.set(true, forKey: "notificationPermissionRequested")
        }

        if isEditMode {
            guard let item = editingItem else { return }
            try service.update(
                item,
                title: title,
                notes: notes.isEmpty ? nil : notes,
                start: startDate,
                end: endDate,
                isAllDay: isCalendarType && isAllDay,
                recurrence: recurrence,
                alert: alertTiming
            )
            notificationService.cancel(for: item.id)
            if alertTiming != .none {
                notificationService.schedule(for: item, alert: alertTiming)
            }
        } else {
            guard let calendar = selectedCalendar else { return }
            if isCalendarType {
                guard let start = startDate, let end = endDate else { return }
                let id = try service.createEvent(
                    title: title,
                    notes: notes.isEmpty ? nil : notes,
                    start: start,
                    end: end,
                    calendar: calendar,
                    isAllDay: isAllDay,
                    recurrence: recurrence,
                    alert: alertTiming
                )
                if alertTiming != .none {
                    let item = TicItem(
                        id: id, title: title, notes: notes,
                        startDate: start, endDate: end,
                        isAllDay: false, isCompleted: false,
                        isReminder: false, hasTime: true,
                        calendarTitle: calendar.title,
                        calendarColor: calendar.cgColor,
                        recurrenceRule: nil, ekEvent: nil, ekReminder: nil
                    )
                    notificationService.schedule(for: item, alert: alertTiming)
                }
            } else {
                let id = try service.createReminder(
                    title: title,
                    notes: notes.isEmpty ? nil : notes,
                    dueDate: startDate,
                    list: calendar,
                    alert: alertTiming
                )
                if alertTiming != .none, startDate != nil {
                    let item = TicItem(
                        id: id, title: title, notes: notes,
                        startDate: startDate, endDate: startDate,
                        isAllDay: false, isCompleted: false,
                        isReminder: true, hasTime: true,
                        calendarTitle: calendar.title,
                        calendarColor: calendar.cgColor,
                        recurrenceRule: nil, ekEvent: nil, ekReminder: nil
                    )
                    notificationService.schedule(for: item, alert: alertTiming)
                }
            }
        }
    }

    // MARK: - 삭제

    func delete(service: EventKitService, notificationService: NotificationService) throws {
        guard let item = editingItem else { return }
        try service.delete(item)
        notificationService.cancel(for: item.id)
    }
}
