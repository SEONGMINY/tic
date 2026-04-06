import EventKit
import SwiftUI

struct EventFormView: View {
    @Bindable var viewModel: EventFormViewModel
    var eventKitService: EventKitService
    var notificationService: NotificationService
    var onDismiss: () -> Void

    @State private var showDeleteAlert = false
    @FocusState private var focusedField: Field?

    enum Field { case title, notes }

    private var allCalendars: [EKCalendar] {
        eventKitService.availableCalendars()
    }

    private var allReminderLists: [EKCalendar] {
        eventKitService.availableReminderLists()
    }

    private var selectedCalendarId: Binding<String> {
        Binding(
            get: { viewModel.selectedCalendar?.calendarIdentifier ?? "" },
            set: { newId in
                if newId.isEmpty {
                    viewModel.selectedCalendar = nil
                } else if let cal = allCalendars.first(where: { $0.calendarIdentifier == newId }) {
                    viewModel.selectedCalendar = cal
                    viewModel.isCalendarType = true
                    if viewModel.startDate == nil {
                        let now = Date()
                        let calendar = Calendar.current
                        var components = calendar.dateComponents([.year, .month, .day], from: now)
                        components.hour = 9
                        components.minute = 0
                        viewModel.startDate = calendar.date(from: components)
                        components.hour = 10
                        viewModel.endDate = calendar.date(from: components)
                    }
                } else if let list = allReminderLists.first(where: { $0.calendarIdentifier == newId }) {
                    viewModel.selectedCalendar = list
                    viewModel.isCalendarType = false
                }
            }
        )
    }

    /// The list to show in the calendar picker, based on current type
    private var calendarListForCurrentType: [EKCalendar] {
        viewModel.isCalendarType ? allCalendars : allReminderLists
    }

    private var datePickerComponents: DatePickerComponents {
        viewModel.isAllDay ? [.date] : [.date, .hourAndMinute]
    }

    var body: some View {
        NavigationStack {
            Form {
                // Segmented Control (생성 모드에서만)
                if !viewModel.isEditMode {
                    Picker("타입", selection: $viewModel.isCalendarType) {
                        Text("이벤트").tag(true)
                        Text("미리 알림").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .onChange(of: viewModel.isCalendarType) { oldValue, newValue in
                        guard oldValue != newValue else { return }
                        viewModel.selectedCalendar = nil
                        if newValue {
                            // 미리 알림 → 이벤트: 기본 시간 세팅
                            if viewModel.startDate == nil || viewModel.endDate == nil {
                                let calendar = Calendar.current
                                var components = calendar.dateComponents([.year, .month, .day], from: Date())
                                components.hour = 9
                                components.minute = 0
                                viewModel.startDate = calendar.date(from: components)
                                components.hour = 10
                                viewModel.endDate = calendar.date(from: components)
                            }
                        }
                    }
                }

                // 제목
                Section {
                    TextField("제목", text: $viewModel.title)
                        .font(.system(size: 15))
                        .focused($focusedField, equals: .title)
                    TextField("설명", text: $viewModel.notes, axis: .vertical)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(2...4)
                        .focused($focusedField, equals: .notes)
                }

                // 저장 위치
                Section {
                    HStack {
                        Text("캘린더")
                            .font(.system(size: 14))
                        Spacer()
                        Menu {
                            ForEach(calendarListForCurrentType, id: \.calendarIdentifier) { cal in
                                Button {
                                    selectedCalendarId.wrappedValue = cal.calendarIdentifier
                                } label: {
                                    Label(cal.title, systemImage: viewModel.isCalendarType ? "calendar" : "checklist")
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if let cal = viewModel.selectedCalendar {
                                    Circle()
                                        .fill(Color(cgColor: cal.cgColor))
                                        .frame(width: 8, height: 8)
                                    Text(cal.title)
                                        .font(.system(size: 14))
                                        .foregroundStyle(.primary)
                                } else {
                                    Text("선택")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.secondary)
                                }
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // 시간
                if viewModel.isCalendarType {
                    Section {
                        Toggle("하루 종일", isOn: $viewModel.isAllDay)
                            .font(.system(size: 14))
                        DatePicker(
                            "시작",
                            selection: Binding(
                                get: { viewModel.startDate ?? Date() },
                                set: { newStart in
                                    viewModel.startDate = newStart
                                    if let end = viewModel.endDate, newStart >= end {
                                        viewModel.endDate = Calendar.current.date(byAdding: .hour, value: 1, to: newStart)
                                    }
                                }
                            ),
                            displayedComponents: datePickerComponents
                        )
                        .font(.system(size: 14))
                        DatePicker(
                            "종료",
                            selection: Binding(
                                get: { viewModel.endDate ?? Date() },
                                set: { viewModel.endDate = $0 }
                            ),
                            in: (viewModel.startDate ?? Date())...,
                            displayedComponents: datePickerComponents
                        )
                        .font(.system(size: 14))
                    }
                } else {
                    Section {
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
                        .font(.system(size: 14))
                        if viewModel.startDate != nil {
                            DatePicker(
                                "날짜",
                                selection: Binding(
                                    get: { viewModel.startDate ?? Date() },
                                    set: { viewModel.startDate = $0 }
                                ),
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .font(.system(size: 14))
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
                    .font(.system(size: 14))
                }

                // 알림
                Section {
                    Picker("알림", selection: $viewModel.alertTiming) {
                        ForEach(AlertTiming.allCases, id: \.self) { timing in
                            Text(timing.displayName).tag(timing)
                        }
                    }
                    .font(.system(size: 14))
                }

                // 삭제
                if viewModel.isEditMode {
                    Section {
                        Button("이 일정 삭제", role: .destructive) {
                            showDeleteAlert = true
                        }
                        .font(.system(size: 14))
                    }
                }
            }
            .listSectionSpacing(.compact)
            .environment(\.defaultMinListRowHeight, 44)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(viewModel.isEditMode ? "일정 수정" : "새 일정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { onDismiss() }
                        .font(.system(size: 15))
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
                    .font(.system(size: 15, weight: .semibold))
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
        .presentationDetents([.medium, .large])
    }
}
