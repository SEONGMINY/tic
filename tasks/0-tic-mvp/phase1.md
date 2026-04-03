# Phase 1: models-services

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `/docs/data-schema.md` — 데이터 스키마 (EventKit 중심, SwiftData 3모델, TicItem)
- `/docs/code-architecture.md` — 코드 아키텍처 (서비스 계약, 데이터 흐름)
- `/docs/adr.md` — 기술 결정 기록 (ADR-001~004 특히 중요)

그리고 이전 phase의 작업물을 반드시 확인하라:

- `/tic/ticApp.swift` — 앱 진입점
- `/tic/ContentView.swift` — 루트 뷰
- `project.yml` — 프로젝트 설정

이전 phase에서 만들어진 코드를 꼼꼼히 읽고, 설계 의도를 이해한 뒤 작업하라.

## 작업 내용

데이터 모델과 서비스 레이어를 구현한다. 이 phase가 끝나면 EventKit CRUD, 로컬 알림 스케줄링, SwiftData 모델이 전부 동작해야 한다.

### 1. `/tic/Models/TicItem.swift` — 통합 뷰 모델

```swift
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
}
```

핵심 규칙:
- `Hashable` 구현 시 `ekEvent`, `ekReminder`는 제외하라 (EKEvent/EKReminder는 Hashable이 아님). `id`로만 hash/equality 판단.
- `ekEvent`와 `ekReminder`는 수정/삭제 시 직접 참조하기 위한 것. 둘 중 하나만 non-nil.
- `hasTime`: 리마인더가 시간이 있는지 없는지 구분. 시간 없는 리마인더는 체크리스트에만 표시.

### 2. SwiftData 모델 3개

`/tic/Models/SearchHistory.swift`:
```swift
@Model class SearchHistory {
    var query: String
    var searchedAt: Date
    init(query: String) { ... }
}
```

`/tic/Models/CalendarSelection.swift`:
```swift
@Model class CalendarSelection {
    @Attribute(.unique) var calendarIdentifier: String
    var isEnabled: Bool
    init(calendarIdentifier: String, isEnabled: Bool = true) { ... }
}
```

`/tic/Models/NotificationMeta.swift`:
```swift
@Model class NotificationMeta {
    @Attribute(.unique) var eventIdentifier: String
    var snoozedUntil: Date?
    init(eventIdentifier: String) { ... }
}
```

### 3. `/tic/Services/EventKitService.swift`

`@Observable` 클래스. EKEventStore를 래핑하고 모든 EventKit 작업을 담당.

인터페이스:
```swift
@Observable
class EventKitService {
    private let store = EKEventStore()
    var calendarAccessGranted = false
    var reminderAccessGranted = false
    
    // 권한 요청
    func requestCalendarAccess() async -> Bool
    func requestReminderAccess() async -> Bool
    
    // 읽기
    func fetchEvents(from: Date, to: Date) -> [TicItem]
    func fetchReminders(from: Date?, to: Date?) async -> [TicItem]
    func fetchAllItems(for date: Date) async -> [TicItem]
    func hasEvents(on date: Date) -> Bool
    
    // 쓰기
    func createEvent(title: String, notes: String?, start: Date, end: Date, calendar: EKCalendar, recurrence: RecurrenceOption, alert: AlertTiming) throws -> String
    func createReminder(title: String, notes: String?, dueDate: Date?, list: EKCalendar, alert: AlertTiming) throws -> String
    func update(_ item: TicItem, title: String, notes: String?, start: Date?, end: Date?, recurrence: RecurrenceOption, alert: AlertTiming) throws
    func delete(_ item: TicItem) throws
    func complete(_ item: TicItem) throws
    
    // 캘린더 목록
    func availableCalendars() -> [EKCalendar]
    func availableReminderLists() -> [EKCalendar]
    
    // 변경 감지
    func startObservingChanges()
}
```

핵심 구현 규칙:
- `fetchEvents`는 `EKEventStore.events(matching:)`를 사용. predicate는 `predicateForEvents(withStart:end:calendars:)`.
- `fetchReminders`는 `EKEventStore.fetchReminders(matching:)`을 사용. 비동기(completion handler)이므로 async/await로 래핑.
- `fetchAllItems`는 위 두 함수를 호출하고 결과를 합쳐 시간순 정렬.
- EKEvent → TicItem 변환 시: `id = eventIdentifier`, `isReminder = false`, `hasTime = true`.
- EKReminder → TicItem 변환 시: `id = calendarItemIdentifier`, `isReminder = true`, `hasTime = (dueDateComponents에 hour가 있는지)`.
- `startObservingChanges()`는 `NotificationCenter.default`에서 `.EKEventStoreChanged`를 구독. 변경 시 published 속성을 갱신하여 뷰가 리프레시되게.
- 반복 일정 생성 시 `EKRecurrenceRule` 사용.

### 4. 열거형 정의 (EventKitService 파일 내 또는 별도 파일)

```swift
enum RecurrenceOption: String, CaseIterable {
    case none = "없음"
    case daily = "매일"
    case weekly = "매주"
    case biweekly = "2주마다"
    case monthly = "매월"
    case yearly = "매년"
    
    func toRule() -> EKRecurrenceRule? { ... }
}

enum AlertTiming: Int, CaseIterable {
    case none = 0
    case fiveMin = 5
    case fifteenMin = 15
    case thirtyMin = 30
    case oneHour = 60
    
    var displayName: String { ... }
}
```

### 5. `/tic/Services/NotificationService.swift`

```swift
class NotificationService {
    func requestPermission() async -> Bool
    func schedule(for item: TicItem, alert: AlertTiming)
    func scheduleSnooze(for identifier: String, minutes: Int = 10)
    func cancel(for identifier: String)
}
```

핵심 규칙:
- `UNUserNotificationCenter`를 사용.
- `schedule`은 `UNTimeIntervalNotificationTrigger` 또는 `UNCalendarNotificationTrigger` 사용.
- 알림 카테고리에 "완료"와 "10분 후" 액션 버튼을 등록하라.
- 알림 identifier는 EventKit의 identifier를 사용하여 중복 스케줄 방지.

### 6. `/tic/Extensions/Date+Extensions.swift`

```swift
extension Date {
    var startOfDay: Date { ... }
    var endOfDay: Date { ... }
    var startOfMonth: Date { ... }
    var endOfMonth: Date { ... }
    var startOfYear: Date { ... }
    func adding(days: Int) -> Date { ... }
    func adding(months: Int) -> Date { ... }
    func isSameDay(as other: Date) -> Bool { ... }
    var isToday: Bool { ... }
    var weekday: Int { ... }  // 1=일, 2=월, ...
    var day: Int { ... }
    var month: Int { ... }
    var year: Int { ... }
}
```

### 7. ticApp.swift 업데이트

SwiftData ModelContainer를 설정하라:

```swift
@main
struct ticApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [SearchHistory.self, CalendarSelection.self, NotificationMeta.self])
    }
}
```

### 8. xcodegen 재생성

파일 추가 후 `xcodegen generate`를 실행하여 프로젝트를 갱신하라.

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodegen generate && xcodebuild build -project tic.xcodeproj -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -1 | grep -q "BUILD SUCCEEDED"
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/0-tic-mvp/index.json`의 phase 1 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.
작업 중 사용자 개입이 반드시 필요한 상황이 발생하면 status를 `"blocked"`로, `"blocked_reason"` 필드에 사유를 기록하고 작업을 즉시 중단하라.

## 주의사항

- EventKit import 시 `import EventKit` 사용. UIKit은 import하지 마라.
- `@Observable`은 `import Observation`이 아닌 Swift 5.9 기본 제공. 별도 import 불필요.
- EKReminder의 dueDateComponents는 `DateComponents?`이므로 nil 체크 필수.
- `fetchReminders`의 completion handler를 `withCheckedContinuation`으로 async 래핑하라.
- SwiftData `@Model` 클래스에는 반드시 `init`을 명시적으로 작성하라.
- 시뮬레이터 이름이 `iPhone 16`이 아닐 수 있다. `xcrun simctl list devices available`로 확인하고 적절히 조정하라.
