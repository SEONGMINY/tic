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
├── DragSession/
│   ├── CalendarDragCoordinator.swift // root overlay owner, drag session 수명 관리
│   ├── DragSessionTypes.swift        // 상태, 컨텍스트, snapshot 계약
│   ├── DragSessionGeometry.swift     // minute/date/frame 계산 규칙
│   └── DragSessionEngine.swift       // 순수 상태 전이 엔진
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
├── ticTests/
│   ├── DragSessionGeometryTests.swift
│   └── DragSessionEngineTests.swift
│
└── TicLiveActivityView.swift        // Lock Screen + Dynamic Island (progress line UI)

experiments/
└── draglab/
    ├── data/                        // sessions.json, events.json, expected.json
    ├── configs/                     // baseline/search-space
    ├── src/draglab/                 // models, contracts, geometry, state machine, scoring, cli
    └── tests/                       // 순수 Python 테스트
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

편집 모드는 트랜지언트 UI 상태 → **DayView @State**로 관리한다. 다만 cross-scope drag session만큼은 `DayView`에 두지 않고 root owner로 올린다.

```swift
// DayView @State
@State var phantomBlock: PhantomBlock?       // {hour, minute, calendar}
@State var editingItemId: String?            // 편집 중인 블록 ID
@State var showPhantomSheet: Bool = false

// TimelineView에 Binding으로 전달
editingItemId: Binding<String?>
onResizeStart: (String, Date) -> Void
onResizeEnd: (String, Date) -> Void
onMoveItem: (String, Date, Date) -> Void
onDuplicateItem: (String) -> Void
phantomBlock: PhantomBlock?
```

이유: UI 제스처 상태가 서비스 레이어와 혼재되면 책임 경계가 흐려짐.

단, cross-scope drag가 커지면 View의 임시 상태만으로는 상태 전이 규칙을 안전하게 유지하기 어렵다. 그래서 SwiftUI View가 모든 제스처 로직을 직접 품는 대신, 순수 로직을 담는 `DragSessionEngine` 계층을 별도로 둔다.

```swift
@Observable
final class CalendarDragCoordinator {
    var engine: DragSessionEngine
    var overlaySnapshot: DragSessionSnapshot?
    var registry: [CalendarScope: [DateCellFrame]]
    var timelineFrameGlobal: CGRect?
}
```

- `ContentView`가 `CalendarDragCoordinator`를 단일 owner로 가진다.
- `DayView`, `MonthView`, `YearView`는 owner가 아니라 geometry/frame reporting 역할만 가진다.
- scope가 바뀌어도 coordinator와 overlay는 유지된다.

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

드래그 중인 블록을 타임라인에서 분리 → `ContentView` 수준의 root overlay owner가 렌더링한다. 타임라인 전환 애니메이션과 drag session 수명을 분리하기 위함이다.

```swift
struct DateCellFrame {
    let date: Date
    let frameGlobal: CGRect
}
```

cross-scope drag는 아래 drag session 컨텍스트로 추적한다.

```swift
struct DragSessionContext {
    let itemId: String
    let sourceDate: Date
    let sourceStartMinute: Int
    let sourceEndMinute: Int
    let durationMinute: Int
    var currentScope: CalendarScope
    var pointerGlobal: CGPoint
    var fingerToBlockAnchor: CGSize
    var overlayFrameGlobal: CGRect
    var dateCandidate: Date?
    var minuteCandidate: Int?
    var activeDate: Date?
    var invalidReason: String?
}
```

핵심 규칙:

- drag session은 day → month/year 전환 중에도 유지된다.
- 원본 블록은 placeholder/ghost처럼 남고, 실제 이동 중 블록은 전역 overlay로만 렌더링한다.
- `droppable`은 독립 top-level state가 아니라, current state + candidate 유효성에서 계산되는 파생 판정이다.
- invalid drop, overflow, missing candidate는 clamp보다 `restore`를 우선한다.
- overlay와 날짜 셀 hit-test는 모두 `global coordinates`를 기준으로 계산한다.

## DragSessionEngine

SwiftUI View는 이벤트를 전달하고 결과를 렌더링만 한다. 상태 전이와 geometry 계산은 순수 로직 레이어가 담당한다.

```swift
enum DragState {
    case idle
    case pressing
    case dragReady
    case draggingTimeline
    case draggingCalendar
    case restoring
}

enum DragOutcome {
    case none
    case dropped
    case cancelled
}
```

- `DayView`, `TimelineView`, `MonthView`, `YearView`는 pointer/scope 이벤트를 모아 `DragSessionEngine`에 전달한다.
- 엔진은 `DragSessionContext`, `DragState`, 파생 `droppable`, overlay frame, drop candidate를 계산한다.
- Swift 구현 전에 동일한 규칙을 Python `draglab`에서 먼저 검증한다.

## CalendarDragCoordinator

`CalendarDragCoordinator`는 SwiftUI glue layer다.

- `ContentView`가 단일 인스턴스를 소유한다.
- `viewModel.scope` 변경을 감지해 엔진에 새 scope를 전달한다.
- timeline frame과 month/year 날짜 셀 frame registry를 유지한다.
- root overlay 렌더링에 필요한 `overlaySnapshot`을 제공한다.
- EventKit write는 최종 drop 확정 시에만 호출하고, 계산 로직은 여전히 엔진/geometry에 둔다.

## Swift / Python 공통 계약

Swift와 Python은 아래 계산 기준을 공유한다.

- 좌표계 단위: iOS point 기준 `global coordinates`
- `timelineLocalY = pointerGlobalY - timelineFrame.minY + scrollOffsetY`
- `rawMinute = timelineLocalY / hourHeight * 60`
- `minuteCandidate = snap(clamp(rawMinute, 0, 1439), snapStep)`
- `dateCandidate`는 month/year cell hit-test와 hover hysteresis 규칙으로 계산
- 최종 drop은 `dateCandidate + minuteCandidate + duration`으로 계산
- `minuteCandidate`가 없거나 overflow가 발생하면 drop을 막고 `restore`

이 계약은 `experiments/draglab/README.md`와 Python 코드에서 먼저 고정한 뒤 Swift로 이식한다.

## Python draglab

`experiments/draglab/`은 아래 역할을 가진다.

- JSON fixture 로드 및 계약 검증
- drag session 상태 머신 재생
- geometry/date/minute 계산 검증
- expected 기반 자동 채점
- 자연스러움 metric 측정
- threshold/config 탐색

병렬 실험 원칙:

- 세션 내부 이벤트 처리는 항상 순차
- 병렬화 단위는 `config` 또는 `session chunk`
- nested pool 금지
- deterministic seed 유지

## 테스트 전략

- `ticTests`를 추가해 `DragSessionEngine`, geometry, hover hit-test 같은 순수 로직을 XCTest로 검증한다.
- mock-heavy UI 테스트는 만들지 않는다.
- SwiftUI View는 coordinator/engine integration 수준까지만 빌드 검증한다.

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
