# tic — 데이터 스키마

## 설계 원칙
> **EventKit이 Single Source of Truth.** 앱은 Apple Calendar과 Reminders에 직접 읽기/쓰기한다. SwiftData는 EventKit이 담을 수 없는 앱 고유 메타데이터만 저장한다.

## EventKit (Apple이 관리 — 별도 스키마 정의 불필요)
```
EKEvent:    title, notes, startDate, endDate, calendar, isAllDay, 
            recurrenceRules, eventIdentifier
EKReminder: title, notes, dueDateComponents, isCompleted, calendar,
            calendarItemIdentifier
```

## SwiftData 모델 (총 3개)

```swift
@Model class SearchHistory {
    var query: String
    var searchedAt: Date
}

@Model class CalendarSelection {
    @Attribute(.unique) var calendarIdentifier: String
    var isEnabled: Bool  // 기본값: true
}

@Model class NotificationMeta {
    @Attribute(.unique) var eventIdentifier: String
    var snoozedUntil: Date?
}
```

3개뿐인 이유: 모든 캘린더/리마인더 데이터는 EventKit에 있다. SwiftData는 검색 기록(UX), 캘린더 가시성(앱 고유), 스누즈 상태(일시적)만 저장.

## 인메모리 뷰 모델

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
    let hasTime: Bool           // 시간 있는 리마인더 vs 없는 리마인더
    let calendarTitle: String
    let calendarColor: CGColor
    let recurrenceRule: EKRecurrenceRule?
    let ekEvent: EKEvent?
    let ekReminder: EKReminder?
}
```

통합 모델 이유: 캘린더 이벤트와 리마인더를 하나의 "할 일"로 취급. 완료 체크박스 외 동일 렌더링. 서비스 경계에서 변환하면 뷰가 단순.

## 위젯 데이터 공유

```
메인 앱 ←→ App Group (UserDefaults) ←→ Widget Extension
```

공유 UserDefaults에 다음 N개 일정 JSON 캐시. EventKit 쓰기 + `EKEventStoreChanged` 마다 업데이트. 위젯은 타임라인 생성 시 캐시 읽기.

UserDefaults 선택 이유: 위젯은 빠르고 동기적인 읽기 필요. 소량 데이터에 공유 SwiftData보다 단순.

## Live Activity 데이터

```swift
struct TicActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var events: [ActivityEvent]  // 오늘의 전체 일정 (최대 10개)
        var currentIndex: Int?       // 현재 진행 중 일정 index
        var nextIndex: Int?          // 다음 일정 index
    }
}

struct ActivityEvent: Codable, Hashable {
    var title: String
    var startDate: Date
    var endDate: Date
    var colorHex: String          // 캘린더 고유 색상 (#RRGGBB)
}
```

다중 이벤트 이유: 전체 일정 타임라인을 progress line으로 표시. 4KB 제한 내에서 `ActivityEvent` 하나 ≈ 200 bytes × 10개 = 2KB로 충분. `currentIndex`/`nextIndex`로 "지금/다음" 라벨과 카운트다운 대상 결정.
