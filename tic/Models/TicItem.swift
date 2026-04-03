import EventKit
import SwiftUI

struct TicItem: Identifiable, Hashable {
    let id: String
    let title: String
    let notes: String?
    let startDate: Date?
    let endDate: Date?
    let isAllDay: Bool
    let isCompleted: Bool
    let isReminder: Bool
    let hasTime: Bool
    let calendarTitle: String
    let calendarColor: CGColor
    let recurrenceRule: EKRecurrenceRule?
    let ekEvent: EKEvent?
    let ekReminder: EKReminder?

    static func == (lhs: TicItem, rhs: TicItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
