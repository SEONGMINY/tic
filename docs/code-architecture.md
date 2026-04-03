# tic — 코드 아키텍처

## 패턴
**단순 MVVM + Service Layer.** Clean Architecture, VIPER, TCA 사용하지 않음. MVP 속도 > 아키텍처 순수성.

## 상태 관리
`@Observable` (Observation 프레임워크, iOS 17+). `@ObservableObject`/`@Published` 사용 안 함 — 보일러플레이트 적고, 성능 좋고, 세밀한 뷰 업데이트 가능.

## 데이터 흐름
```
EventKit (Apple)
  ↓ fetch / EKEventStoreChanged 감지
EventKitService (@Observable, 싱글턴)
  ↓ [TicItem]으로 변환
ViewModel (@Observable, 화면별)
  ↓ SwiftUI 바인딩
View
  ↓ 사용자 액션
ViewModel → EventKitService → EventKit에 직접 쓰기
  ↓ EKEventStoreChanged 발생
자동 리프레시 사이클
```

커스텀 동기화 없음. 중간 캐시 없음 (위젯 UserDefaults 제외). EventKit 노티피케이션이 반응성을 담당.

## 프로젝트 구조 (~25개 파일)

```
tic/
├── ticApp.swift                     // @main, SwiftData ModelContainer, 딥링크 처리
│
├── Models/
│   ├── TicItem.swift                // 통합 뷰 모델 (struct, 인메모리)
│   ├── SearchHistory.swift          // SwiftData
│   ├── CalendarSelection.swift      // SwiftData
│   └── NotificationMeta.swift       // SwiftData
│
├── Services/
│   ├── EventKitService.swift        // EventKit CRUD, EKEvent↔TicItem 변환, 변경 감지
│   ├── NotificationService.swift    // UNUserNotificationCenter 스케줄링, 스누즈, 액션 처리
│   └── LiveActivityService.swift    // ActivityKit 시작/업데이트/종료/전환
│
├── ViewModels/
│   ├── CalendarViewModel.swift      // 월간/년간 뷰 데이터, scope 상태 (year/month/day)
│   ├── DayViewModel.swift           // 일간 이벤트, 다음 행동 로직, 타임라인 레이아웃
│   ├── EventFormViewModel.swift     // 생성/수정 폼 상태, 유효성 검사, 저장/삭제
│   └── SearchViewModel.swift        // 검색어, 필터링, 기록 관리
│
├── Views/
│   ├── ContentView.swift            // 루트: scope 전환 (year/month/day), pinch 제스처, 내비바
│   ├── Calendar/
│   │   ├── YearView.swift           // 12개월 미니 그리드
│   │   ├── MonthView.swift          // 캘린더 그리드 + 점 표시
│   │   └── DayView.swift            // 다음 행동 + 타임라인 + 체크리스트 FAB
│   ├── EventFormView.swift          // 추가/수정 bottom sheet
│   ├── SearchView.swift             // 검색 화면
│   ├── SettingsView.swift           // 캘린더 토글 bottom sheet
│   └── Components/
│       ├── TimelineView.swift       // 24시간 스크롤 가능 타임라인 + 이벤트 블록
│       ├── NextActionCard.swift     // "다음 행동" 카드 컴포넌트
│       └── ChecklistSheet.swift     // 시간 없는 리마인더 bottom sheet
│
├── Extensions/
│   └── Date+Extensions.swift        // startOfDay, endOfDay, 캘린더 연산
│
├── ticWidgets/                      // Widget Extension 타겟
│   ├── TicWidgetBundle.swift
│   ├── SmallWidget.swift
│   ├── MediumWidget.swift
│   ├── WidgetProvider.swift         // 공유 TimelineProvider
│   └── WidgetIntents.swift          // CompleteEventIntent, SnoozeEventIntent
│
└── ticLiveActivity/                 // 메인 타겟 내 (ActivityKit)
    ├── TicActivityAttributes.swift  // ActivityAttributes 정의
    └── TicLiveActivityView.swift    // 잠금화면 / Dynamic Island UI
```

## 서비스 계약

### EventKitService
```swift
@Observable class EventKitService {
    // 권한
    func requestCalendarAccess() async -> Bool
    func requestReminderAccess() async -> Bool
    
    // 읽기
    func fetchEvents(from: Date, to: Date) -> [TicItem]
    func fetchReminders(from: Date?, to: Date?) async -> [TicItem]
    func fetchAllItems(for date: Date) async -> [TicItem]
    func hasEvents(on date: Date) -> Bool  // 월간/년간 뷰 점 표시용
    
    // 쓰기
    func createEvent(title:notes:start:end:calendar:recurrence:alert:) throws -> String
    func createReminder(title:notes:dueDate:list:alert:) throws -> String
    func update(_ item: TicItem, ...) throws
    func delete(_ item: TicItem) throws
    func complete(_ item: TicItem) throws
    
    // 캘린더 목록
    func availableCalendars() -> [EKCalendar]
    func availableReminderLists() -> [EKCalendar]
    
    // 변경 감지
    func startObservingChanges()  // EKEventStoreChanged 구독
}
```

### NotificationService
```swift
class NotificationService {
    func requestPermission() async -> Bool
    func schedule(for item: TicItem, alert: AlertTiming)
    func scheduleSnooze(for identifier: String, minutes: Int)
    func cancel(for identifier: String)
}

enum AlertTiming: Int, CaseIterable {
    case none = 0, fiveMin = 5, fifteenMin = 15, thirtyMin = 30, oneHour = 60
}
```

### LiveActivityService
```swift
class LiveActivityService {
    func start(for item: TicItem) throws
    func update(for item: TicItem)
    func end(for identifier: String)
    func transition(to next: TicItem) throws  // 현재 종료 → 다음 시작
}
```

## App Intents (위젯 + Live Activity)
```swift
struct CompleteEventIntent: AppIntent {
    @Parameter var eventIdentifier: String
    // → EventKitService.complete() → LiveActivityService.end() → 위젯 리로드
}

struct SnoozeEventIntent: AppIntent {
    @Parameter var eventIdentifier: String
    // → NotificationService.scheduleSnooze(10분) → LiveActivity 업데이트
}
```

## 네비게이션
```swift
enum CalendarScope { case year, month, day }
```
- `MagnifyGesture`로 pinch 감지 → scope 전환
- `.matchedGeometryEffect`로 줌 애니메이션
- `@State var selectedDate: Date`가 표시할 날짜/월 결정
- 날짜 레이블 탭 → `selectedDate = .now`

## 타임라인 레이아웃 알고리즘
겹치는 일정을 위한 column-packing:
1. 시작 시간 기준 이벤트 정렬
2. 충돌 클러스터로 그룹화 (겹치는 시간 범위)
3. 클러스터 내에서 탐욕적으로 열 할당 (사용 가능한 첫 번째 열)
4. 열 수에 따라 너비 균등 분할

구현: 뷰 body 바깥에서 `LayoutAttributes` (widthFraction, xOffset) 미리 계산, 날짜별 캐시.

## 딥링킹 (위젯 → 앱)
```swift
// URL 스킴: tic://day?date=2026-04-16
// ticApp에서 .onOpenURL 처리 → selectedDate 설정 + scope = .day
```
