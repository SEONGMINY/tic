# tic — 데이터 스키마

## 설계 원칙
> **EventKit이 Single Source of Truth.** 앱은 Apple Calendar과 Reminders에 직접 읽기/쓰기한다. SwiftData는 EventKit이 담을 수 없는 앱 고유 메타데이터만 저장한다.

이로써 동기화 로직이 완전히 제거된다. 앱이 이벤트를 쓰면 Apple이 iCloud 동기화, 다른 앱 간 가시성, 영속성을 처리한다.

## EventKit (Apple이 관리 — 별도 스키마 정의 불필요)
```
EKEvent:    title, notes, startDate, endDate, calendar, isAllDay, 
            recurrenceRules, eventIdentifier
EKReminder: title, notes, dueDateComponents, isCompleted, calendar,
            calendarItemIdentifier
```

## SwiftData 모델 (총 3개)

```swift
@Model
class SearchHistory {
    var query: String
    var searchedAt: Date
}

@Model
class CalendarSelection {
    @Attribute(.unique) var calendarIdentifier: String  // EKCalendar.calendarIdentifier
    var isEnabled: Bool  // 기본값: true
}

@Model
class NotificationMeta {
    @Attribute(.unique) var eventIdentifier: String  // EKEvent/EKReminder identifier
    var snoozedUntil: Date?
}
```

**왜 3개뿐인가:** 모든 캘린더/리마인더 데이터는 EventKit에 있다. SwiftData는 EventKit이 할 수 없는 것만 저장한다: 검색 기록(UX 기능), 캘린더 가시성 설정(앱 고유), 스누즈 상태(일시적, EventKit 개념 아님).

## 인메모리 뷰 모델 (영속화하지 않음)

```swift
struct TicItem: Identifiable, Hashable {
    let id: String              // EventKit identifier
    let title: String
    let notes: String?
    let startDate: Date?
    let endDate: Date?
    let isAllDay: Bool
    let isCompleted: Bool
    let isReminder: Bool
    let hasTime: Bool           // 시간 있는 리마인더 vs 시간 없는 리마인더
    let calendarTitle: String
    let calendarColor: CGColor
    let recurrenceRule: EKRecurrenceRule?
    let ekEvent: EKEvent?       // 수정/삭제 시 직접 참조
    let ekReminder: EKReminder?
}
```

**왜 통합 모델인가:** 앱은 캘린더 이벤트와 리마인더를 하나의 개념("할 일")으로 취급한다. UI는 완료 체크박스를 제외하면 동일하게 렌더링한다. 서비스 경계에서 변환하면 뷰가 단순해진다.

## 위젯 데이터 공유

```
메인 앱 ←→ App Group (UserDefaults) ←→ Widget Extension
```

공유 UserDefaults에 캐시:
- 다음 N개 일정 (제목, 시간, identifier, 캘린더 색상) JSON 형태
- EventKit 쓰기 + EKEventStoreChanged 노티피케이션마다 업데이트
- 위젯은 타임라인 생성 시 캐시 읽기, 변경 시 `WidgetCenter.shared.reloadAllTimelines()` 호출

**왜 공유 SwiftData가 아닌 UserDefaults인가:** 위젯은 타임라인 생성 시 빠르고 동기적인 읽기가 필요하다. UserDefaults가 더 단순하고 소량의 일정 캐시에 충분하다.

## Live Activity 데이터

```swift
struct TicActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var startDate: Date
        var endDate: Date
        var isReminder: Bool
        var calendarColorHex: String
    }
    var eventIdentifier: String
}
```
