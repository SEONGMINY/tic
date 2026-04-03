# Phase 4: event-form

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `/docs/prd.md` — 일정 관리 (생성, 수정, 삭제, 반복, 알림), 일정 추가 폼 필드 테이블
- `/docs/flow.md` — F4 (일정 상세/수정), F5 (일정 생성)
- `/docs/adr.md` — ADR-012 (권한 요청 전략), ADR-013 (제한적 반복 일정)

그리고 이전 phase의 작업물을 반드시 확인하라:

- `/tic/Views/ContentView.swift` — showEventForm 상태, + 버튼
- `/tic/Views/Calendar/DayView.swift` — onEventTap, onTimeSlotLongPress 콜백
- `/tic/Views/Components/TimelineView.swift` — 이벤트 블록 탭/꾹 처리
- `/tic/Services/EventKitService.swift` — create/update/delete/complete 메서드
- `/tic/Services/NotificationService.swift` — schedule/cancel 메서드
- `/tic/Models/TicItem.swift` — RecurrenceOption, AlertTiming 열거형

이전 phase에서 만들어진 코드를 꼼꼼히 읽고, 설계 의도를 이해한 뒤 작업하라.

## 작업 내용

일정 추가/수정 bottom sheet, 삭제 확인 alert, context menu를 구현한다. 이 phase가 끝나면 일정 CRUD가 전부 동작해야 한다.

### 1. `/tic/ViewModels/EventFormViewModel.swift`

```swift
@Observable
class EventFormViewModel {
    // 폼 상태
    var title: String = ""
    var notes: String = ""
    var selectedCalendar: EKCalendar?
    var isCalendarType: Bool = true  // true=캘린더, false=리마인더
    var startDate: Date? = nil
    var endDate: Date? = nil
    var recurrence: RecurrenceOption = .none
    var alertTiming: AlertTiming = .thirtyMin
    
    // 수정 모드
    var editingItem: TicItem? = nil
    var isEditMode: Bool { editingItem != nil }
    
    // 유효성
    var canSave: Bool { ... }
    
    // 초기화
    func prepareForCreate()
    func prepareForCreate(at date: Date)  // 타임라인 꾹 → 시간 자동 입력
    func prepareForEdit(_ item: TicItem)
    
    // 저장/삭제
    func save(service: EventKitService, notificationService: NotificationService) throws
    func delete(service: EventKitService, notificationService: NotificationService) throws
}
```

핵심 규칙:
- `canSave` 조건:
  - 제목이 비어있지 않음
  - `selectedCalendar`가 nil이 아님
  - 캘린더 타입이면 `startDate`와 `endDate` 둘 다 nil이 아님
- `prepareForCreate()`: 모든 필드 초기화. 날짜 비움. 캘린더/리마인더 선택 안 됨.
- `prepareForCreate(at:)`: startDate = 전달받은 시간, endDate = startDate + 1시간, isCalendarType = true.
- `prepareForEdit`: editingItem에서 모든 필드를 복사. selectedCalendar는 item의 calendarTitle로 매칭.
- `save`: isEditMode에 따라 create 또는 update 호출. 저장 후 알림 스케줄.
  - **첫 일정 생성 시 알림 권한 요청** (ADR-012). NotificationService.requestPermission()을 save 시 한 번만 호출.
- `delete`: 확인 후 EventKitService.delete() + NotificationService.cancel() 호출.

### 2. `/tic/Views/EventFormView.swift`

Bottom sheet 폼.

```swift
struct EventFormView: View {
    @Bindable var viewModel: EventFormViewModel
    var eventKitService: EventKitService
    var notificationService: NotificationService
    var onDismiss: () -> Void
    
    @State private var showDeleteAlert = false
    
    var body: some View {
        NavigationStack {
            Form {
                // 제목 TextField
                // 설명 TextField
                // 저장 위치 Picker (캘린더 + 리마인더 리스트)
                // 캘린더 선택 시: 시작/종료 DatePicker
                // 리마인더 선택 시: 날짜/시간 선택적 DatePicker
                // 반복 Picker
                // 알림 Picker
                // 수정 모드: 삭제 버튼
            }
            .navigationTitle(viewModel.isEditMode ? "일정 수정" : "새 일정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { ... }
                        .disabled(!viewModel.canSave)
                }
            }
        }
    }
}
```

저장 위치 Picker 규칙:
- `eventKitService.availableCalendars()` + `eventKitService.availableReminderLists()`를 합쳐서 표시.
- 각 항목: 캘린더 색상 원 + 이름 + (📅 또는 ☑️ 아이콘으로 유형 구분)
- 캘린더 선택 시 `isCalendarType = true` + 기본 시간 표시 (09:00-10:00)
- 리마인더 리스트 선택 시 `isCalendarType = false` + 시간 필드 선택적

시작/종료 시간:
- `DatePicker`를 사용. `displayedComponents: [.date, .hourAndMinute]`
- 캘린더 타입 기본값: startDate = nil (비어있음), endDate = nil
- 타임라인 꾹으로 진입 시: startDate = 눌린 시간, endDate = +1시간

반복 Picker:
- `RecurrenceOption.allCases`를 나열. 기본 "없음".

알림 Picker:
- `AlertTiming.allCases`를 나열. 기본 "30분 전".

삭제:
- 수정 모드에서만 표시. 빨간색 버튼.
- 탭 → `showDeleteAlert = true` → Alert "이 일정을 삭제하시겠습니까? Apple Calendar/Reminders에서도 삭제됩니다."
- 확인 → `viewModel.delete()` → dismiss

### 3. Context Menu 연결

DayView의 TimelineView와 ChecklistSheet에 context menu를 추가하라:

```swift
.contextMenu {
    Button("수정") { ... }
    Button("삭제", role: .destructive) { ... }
    if item.isReminder {
        Button("완료") { ... }
    }
}
```

- "수정" → EventFormViewModel.prepareForEdit(item) → sheet 표시
- "삭제" → 확인 alert → EventKitService.delete()
- "완료" → EventKitService.complete() → 리스트 리프레시

### 4. ContentView에서 EventFormView 연결

- `showEventForm` 상태가 true일 때 `.sheet`으로 EventFormView 표시.
- + 버튼 → `eventFormViewModel.prepareForCreate()` → `showEventForm = true`
- DayView의 이벤트 탭 → `eventFormViewModel.prepareForEdit(item)` → `showEventForm = true`
- DayView의 타임라인 꾹 → `eventFormViewModel.prepareForCreate(at: date)` → `showEventForm = true`

### 5. 알림 권한 요청 (첫 일정 생성 시)

EventFormViewModel의 `save` 메서드에서:
```swift
// 첫 저장 시 알림 권한 요청 (한 번만)
if !UserDefaults.standard.bool(forKey: "notificationPermissionRequested") {
    await notificationService.requestPermission()
    UserDefaults.standard.set(true, forKey: "notificationPermissionRequested")
}
```

### 6. xcodegen 재생성

파일 추가 후 `xcodegen generate` 실행.

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodegen generate && xcodebuild build -project tic.xcodeproj -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -1 | grep -q "BUILD SUCCEEDED"
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/0-tic-mvp/index.json`의 phase 4 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.
작업 중 사용자 개입이 반드시 필요한 상황이 발생하면 status를 `"blocked"`로, `"blocked_reason"` 필드에 사유를 기록하고 작업을 즉시 중단하라.

## 주의사항

- `EKCalendar`는 `Identifiable`이 아니므로 Picker에서 사용 시 `id: \.calendarIdentifier` 지정.
- `EKCalendar.cgColor`는 CGColor. SwiftUI Color로 변환: `Color(cgColor: calendar.cgColor)`.
- `EKRecurrenceRule` 생성 시 `recurrenceEnd`는 nil (무한 반복).
- EventKit에서 리마인더 완료 처리: `reminder.isCompleted = true` → `store.save(reminder, commit: true)`.
- Form 내 DatePicker가 캘린더/리마인더 전환 시 정상적으로 표시/숨겨지는지 확인.
- 시뮬레이터 이름이 `iPhone 16`이 아닐 수 있다. `xcrun simctl list devices available`로 확인하고 적절히 조정하라.
