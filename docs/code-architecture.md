# tic — 코드 아키텍처

## 패턴
**단순 MVVM + Service Layer.** Clean Architecture, VIPER, TCA 사용하지 않음. MVP 속도 > 아키텍처 순수성.

## 상태 관리
`@Observable` (Observation 프레임워크, iOS 17+). `@ObservableObject`/`@Published` 사용 안 함.

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

## 프로젝트 구조

```
tic/
├── ticApp.swift                     // @main, SwiftData, 딥링크 처리
│
├── Models/
│   ├── TicItem.swift                // 통합 뷰 모델 (struct, 인메모리)
│   ├── TicActivityAttributes.swift  // ActivityAttributes + ContentState (다중 이벤트)
│   ├── SearchHistory.swift          // SwiftData
│   ├── CalendarSelection.swift      // SwiftData
│   └── NotificationMeta.swift       // SwiftData
│
├── Services/
│   ├── EventKitService.swift        // EventKit CRUD, 변경 감지, duplicate(), moveToDate()
│   ├── NotificationService.swift    // UNUserNotificationCenter
│   └── LiveActivityService.swift    // ActivityKit (다중 이벤트 타임라인)
│
├── ViewModels/
│   ├── CalendarViewModel.swift      // scope 상태 (year/month/day), 날짜 선택
│   ├── DayViewModel.swift           // 일간 이벤트, 다음 행동, 타임라인 레이아웃
│   ├── EventFormViewModel.swift     // 폼 상태, 유효성, 저장/삭제, isAllDay
│   └── SearchViewModel.swift        // 검색어, 필터링, 기록
│
├── Views/
│   ├── ContentView.swift            // 루트: scope 전환, pinch, 내비바, LA 시작 로직
│   ├── Calendar/
│   │   ├── YearView.swift           // 12개월 그리드 + "올해" 버튼
│   │   ├── MonthView.swift          // 캘린더 그리드 + "이번달" 버튼
│   │   └── DayView.swift            // 주간 스트립 + 타임라인 + phantom block + 편집 모드 상태
│   ├── EventFormView.swift          // Segmented Control + 하루종일 토글 + 둥근 스타일
│   ├── SearchView.swift
│   ├── SettingsView.swift
│   └── Components/
│       ├── TimelineView.swift       // 24시간 타임라인 + 이벤트 블록 (기본 상태)
│       ├── EditableEventBlock.swift  // 편집 모드 핸들 + 리사이즈 + 이동 + toolbar (500줄 초과 시 분리)
│       ├── NextActionCard.swift
│       └── ChecklistSheet.swift
│
├── Extensions/
│   └── Date+Extensions.swift
│
├── ticWidgets/
│   ├── TicWidgetBundle.swift
│   ├── SmallWidget.swift
│   ├── MediumWidget.swift
│   ├── WidgetProvider.swift
│   └── WidgetIntents.swift          // CompleteEventIntent, SnoozeEventIntent
│
└── TicLiveActivityView.swift        // Lock Screen + Dynamic Island (progress line UI)
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
    func hasEvents(on date: Date) -> Bool
    
    // 쓰기
    func createEvent(title:notes:start:end:calendar:isAllDay:recurrence:alert:) throws -> String
    func createReminder(title:notes:dueDate:list:alert:) throws -> String
    func update(_ item: TicItem, ...) throws
    func delete(_ item: TicItem) throws
    func complete(_ item: TicItem) throws
    func duplicate(_ item: TicItem) throws -> String    // 같은 시간에 복제, 반복 규칙 제외
    func moveToDate(_ item: TicItem, newStart: Date, newEnd: Date) throws  // 날짜 간 이동
    
    // 캘린더 목록
    func availableCalendars() -> [EKCalendar]
    func availableReminderLists() -> [EKCalendar]
    
    // 변경 감지
    func startObservingChanges()
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
    func start(events: [TicItem]) throws          // 오늘의 전체 일정으로 시작
    func update(events: [TicItem])                // 상태 갱신 (currentIndex/nextIndex 재계산)
    func end(for identifier: String)
    func endAll()
    var isActivityActive: Bool { get }
}
```

## 편집 모드 상태 관리

편집 모드는 트랜지언트 UI 상태 → **DayView @State**로 관리 (ViewModel 아님).

```swift
// DayView @State
@State var phantomBlock: PhantomBlock?       // {hour, minute, calendar}
@State var editingItemId: String?            // 편집 중인 블록 ID
@State var showPhantomSheet: Bool = false
@State var crossDayDragState: CrossDayDragState?

// TimelineView에 Binding으로 전달
editingItemId: Binding<String?>
onResizeStart: (String, Date) -> Void
onResizeEnd: (String, Date) -> Void
onMoveItem: (String, Date, Date) -> Void
onDuplicateItem: (String) -> Void
onCrossDayDrag: (String, Edge) -> Void
phantomBlock: PhantomBlock?
```

이유: UI 제스처 상태가 서비스 레이어와 혼재되면 책임 경계가 흐려짐.

## z-index / 제스처 우선순위

```
ZStack 순서 (아래 → 위):
1. timeLines + 시간라벨 long press gesture
2. emptySlotGestures (빈 시간대 long press)
3. eventBlocks (zIndex: 1)
4. phantomBlock (zIndex: 0.5)
5. currentTimeLine (zIndex: 2)
6. editingOverlay — 핸들 + toolbar (zIndex: 3)
```

편집 모드 중: `editingItemId != nil` → 빈 시간대 long press 비활성화, 타임라인 좌우 스와이프 비활성화.

## 날짜 간 블록 이동 (overlay 패턴)

드래그 중인 블록을 타임라인에서 분리 → DayView 최상위 overlay로 렌더링. 타임라인 전환 애니메이션과 독립 동작.

```swift
struct CrossDayDragState {
    let item: TicItem
    var currentOffset: CGSize   // 손가락 위치
    var targetDate: Date        // 이동할 날짜
}
```

## 타임라인 레이아웃 알고리즘
column-packing: 시작 시간 정렬 → 충돌 클러스터 그룹화 → 탐욕적 열 할당 → 너비 균등 분할. 뷰 body 바깥에서 `LayoutAttributes` 미리 계산, 날짜별 캐시.

## 딥링킹
```swift
// URL: tic://day?date=2026-04-16
// ticApp.onOpenURL → selectedDate + scope = .day
```

## 네비게이션
```swift
enum CalendarScope { case year, month, day }
```
MagnifyGesture → scope 전환. matchedGeometryEffect → 줌 애니메이션.
