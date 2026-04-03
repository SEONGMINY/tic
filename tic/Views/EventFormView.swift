import EventKit
import SwiftUI

struct EventFormView: View {
    @Bindable var viewModel: EventFormViewModel
    var eventKitService: EventKitService
    var notificationService: NotificationService
    var onDismiss: () -> Void

    @State private var showDeleteAlert = false

    private var allCalendars: [EKCalendar] {
        eventKitService.availableCalendars()
    }

    private var allReminderLists: [EKCalendar] {
        eventKitService.availableReminderLists()
    }

    var body: some View {
        NavigationStack {
            Form {
                // 제목
                Section {
                    TextField("제목", text: $viewModel.title)
                    TextField("설명", text: $viewModel.notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                // 저장 위치
                Section("저장 위치") {
                    Picker("캘린더", selection: $viewModel.selectedCalendar) {
                        Text("선택 안 됨").tag(EKCalendar?.none)

                        if !allCalendars.isEmpty {
                            Section("캘린더") {
                                ForEach(allCalendars, id: \.calendarIdentifier) { cal in
                                    Label {
                                        Text(cal.title)
                                    } icon: {
                                        Image(systemName: "calendar")
                                            .foregroundStyle(Color(cgColor: cal.cgColor))
                                    }
                                    .tag(EKCalendar?.some(cal))
                                }
                            }
                        }

                        if !allReminderLists.isEmpty {
                            Section("리마인더") {
                                ForEach(allReminderLists, id: \.calendarIdentifier) { list in
                                    Label {
                                        Text(list.title)
                                    } icon: {
                                        Image(systemName: "checklist")
                                            .foregroundStyle(Color(cgColor: list.cgColor))
                                    }
                                    .tag(EKCalendar?.some(list))
                                }
                            }
                        }
                    }
                    .onChange(of: viewModel.selectedCalendar) { _, newValue in
                        guard let cal = newValue else { return }
                        let isCalendar = allCalendars.contains(where: { $0.calendarIdentifier == cal.calendarIdentifier })
                        viewModel.isCalendarType = isCalendar
                        if isCalendar && viewModel.startDate == nil {
                            let now = Date()
                            let calendar = Calendar.current
                            var components = calendar.dateComponents([.year, .month, .day], from: now)
                            components.hour = 9
                            components.minute = 0
                            viewModel.startDate = calendar.date(from: components)
                            components.hour = 10
                            viewModel.endDate = calendar.date(from: components)
                        }
                    }
                }

                // 시간
                if viewModel.isCalendarType {
                    Section("시간") {
                        DatePicker(
                            "시작",
                            selection: Binding(
                                get: { viewModel.startDate ?? Date() },
                                set: { viewModel.startDate = $0 }
                            ),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        DatePicker(
                            "종료",
                            selection: Binding(
                                get: { viewModel.endDate ?? Date() },
                                set: { viewModel.endDate = $0 }
                            ),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                } else {
                    Section("시간") {
                        Toggle("날짜/시간 설정", isOn: Binding(
                            get: { viewModel.startDate != nil },
                            set: { enabled in
                                if enabled {
                                    viewModel.startDate = Date()
                                } else {
                                    viewModel.startDate = nil
                                    viewModel.endDate = nil
                                }
                            }
                        ))
                        if viewModel.startDate != nil {
                            DatePicker(
                                "날짜",
                                selection: Binding(
                                    get: { viewModel.startDate ?? Date() },
                                    set: { viewModel.startDate = $0 }
                                ),
                                displayedComponents: [.date, .hourAndMinute]
                            )
                        }
                    }
                }

                // 반복
                Section {
                    Picker("반복", selection: $viewModel.recurrence) {
                        ForEach(RecurrenceOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                }

                // 알림
                Section {
                    Picker("알림", selection: $viewModel.alertTiming) {
                        ForEach(AlertTiming.allCases, id: \.self) { timing in
                            Text(timing.displayName).tag(timing)
                        }
                    }
                }

                // 삭제
                if viewModel.isEditMode {
                    Section {
                        Button("이 일정 삭제", role: .destructive) {
                            showDeleteAlert = true
                        }
                    }
                }
            }
            .navigationTitle(viewModel.isEditMode ? "일정 수정" : "새 일정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        Task {
                            try? await viewModel.save(
                                service: eventKitService,
                                notificationService: notificationService
                            )
                            onDismiss()
                        }
                    }
                    .disabled(!viewModel.canSave)
                }
            }
            .alert("이 일정을 삭제하시겠습니까?", isPresented: $showDeleteAlert) {
                Button("삭제", role: .destructive) {
                    try? viewModel.delete(
                        service: eventKitService,
                        notificationService: notificationService
                    )
                    onDismiss()
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("Apple Calendar/Reminders에서도 삭제됩니다.")
            }
        }
        .presentationDetents([.large])
    }
}
