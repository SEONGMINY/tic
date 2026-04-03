import EventKit
import SwiftUI
import SwiftData

struct SettingsView: View {
    var eventKitService: EventKitService
    @Environment(\.modelContext) private var modelContext
    @Query private var selections: [CalendarSelection]

    var body: some View {
        NavigationStack {
            List {
                Section("캘린더") {
                    ForEach(eventKitService.availableCalendars(), id: \.calendarIdentifier) { calendar in
                        calendarRow(calendar)
                    }
                }
                Section("미리 알림") {
                    ForEach(eventKitService.availableReminderLists(), id: \.calendarIdentifier) { list in
                        calendarRow(list)
                    }
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func calendarRow(_ calendar: EKCalendar) -> some View {
        let isEnabled = bindingForCalendar(calendar)
        return Toggle(isOn: isEnabled) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(cgColor: calendar.cgColor))
                    .frame(width: 12, height: 12)
                Text(calendar.title)
            }
        }
    }

    private func bindingForCalendar(_ calendar: EKCalendar) -> Binding<Bool> {
        Binding(
            get: {
                if let selection = selections.first(where: { $0.calendarIdentifier == calendar.calendarIdentifier }) {
                    return selection.isEnabled
                }
                return true // 기본값: 활성화
            },
            set: { newValue in
                if let selection = selections.first(where: { $0.calendarIdentifier == calendar.calendarIdentifier }) {
                    selection.isEnabled = newValue
                } else {
                    modelContext.insert(CalendarSelection(calendarIdentifier: calendar.calendarIdentifier, isEnabled: newValue))
                }
                try? modelContext.save()
            }
        )
    }
}
