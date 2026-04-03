# Phase 3: day-view-timeline

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `/docs/prd.md` — 제품 요구사항 (일간 뷰, 다음 행동, 타임라인)
- `/docs/flow.md` — 사용자 흐름 (F3: 일간 뷰)
- `/docs/code-architecture.md` — 타임라인 레이아웃 알고리즘 (column-packing)
- `/docs/adr.md` — ADR-008 (column-packing), ADR-009 (ScrollView+ZStack)

그리고 이전 phase의 작업물을 반드시 확인하라:

- `/tic/Views/ContentView.swift` — 루트 뷰 (scope 전환, pinch, 네비바)
- `/tic/ViewModels/CalendarViewModel.swift` — CalendarScope, selectedDate
- `/tic/Models/TicItem.swift` — 통합 모델
- `/tic/Services/EventKitService.swift` — fetchAllItems, fetchReminders
- `/tic/Extensions/Date+Extensions.swift`
- `/tic/Views/Calendar/MonthView.swift` — 월간 뷰 (참고용)

이전 phase에서 만들어진 코드를 꼼꼼히 읽고, 설계 의도를 이해한 뒤 작업하라.

## 작업 내용

일간 뷰 전체를 구현한다: 다음 행동 카드 + 24시간 타임라인 + 리마인더 체크리스트 + 좌우 스와이프.

### 1. `/tic/ViewModels/DayViewModel.swift`

```swift
@Observable
class DayViewModel {
    var items: [TicItem] = []
    var timedItems: [TicItem] = []        // 캘린더 이벤트 + 시간 있는 리마인더
    var allDayItems: [TicItem] = []       // 종일 이벤트
    var timelessReminders: [TicItem] = [] // 시간 없는 리마인더 (체크리스트용)
    var nextAction: TicItem?              // 다음 행동 (오늘만)
    
    func loadItems(for date: Date, service: EventKitService) async
    func computeNextAction(for date: Date)
    func computeLayout(containerWidth: CGFloat) -> [String: LayoutAttributes]
}

struct LayoutAttributes {
    let widthFraction: CGFloat  // 0.0~1.0
    let xOffset: CGFloat        // 0.0~1.0
    let column: Int
    let totalColumns: Int
}
```

핵심 규칙:
- `loadItems`는 `EventKitService.fetchAllItems(for:)`를 호출하고 결과를 분류:
  - `timedItems`: `!isAllDay && hasTime` (타임라인에 표시)
  - `allDayItems`: `isAllDay` (타임라인 상단 별도 영역)
  - `timelessReminders`: `isReminder && !hasTime` (체크리스트)
- `nextAction`: 오늘인 경우만 계산. 현재 시각 이후 가장 가까운 `timedItems` 1개. 없으면 nil.
- `computeLayout`: column-packing 알고리즘 구현.
  1. `timedItems`를 startDate 기준 정렬
  2. 겹치는 시간대끼리 클러스터로 그룹화
  3. 각 클러스터 내에서 탐욕적으로 열 할당 (사용 가능한 첫 번째 열)
  4. 클러스터 내 총 열 수로 너비 균등 분할
  5. 결과를 `[TicItem.id: LayoutAttributes]` 딕셔너리로 반환

### 2. `/tic/Views/Calendar/DayView.swift`

일간 뷰 메인 화면.

```swift
struct DayView: View {
    var viewModel: CalendarViewModel
    var dayViewModel: DayViewModel
    var eventKitService: EventKitService
    var selectedDate: Date
    
    @State private var showChecklist = false
    
    var body: some View {
        // 구조:
        // 1. 오늘이면: NextActionCard (상단 고정)
        // 2. 종일 이벤트 영역 (있을 때만)
        // 3. TimelineView (24h 스크롤)
        // 4. 📋 FAB (우하단, overlay)
    }
}
```

좌우 스와이프 규칙:
- `TabView`의 `.tabViewStyle(.page(indexDisplayMode: .never))` 사용하거나
- `DragGesture`로 직접 구현
- 스와이프 시 `selectedDate`를 ±1일 변경하고 데이터 리로드

### 3. `/tic/Views/Components/TimelineView.swift`

24시간 타임라인. Apple Calendar 일간 뷰 스타일.

```swift
struct TimelineView: View {
    var timedItems: [TicItem]
    var layout: [String: LayoutAttributes]
    var onEventTap: (TicItem) -> Void
    var onTimeSlotLongPress: (Date) -> Void  // 타임라인 꾹 → 일정 생성
    
    let hourHeight: CGFloat = 60  // 1시간 높이
    
    var body: some View {
        // ScrollView + ZStack
        // 배경: 24개 시간 라인 (08:00, 09:00, ...)
        // 전경: 이벤트 블록 (absolute positioning)
    }
}
```

구현 규칙 (ADR-009 준수):
- `ScrollView(.vertical)` 안에 `ZStack(alignment: .topLeading)` 사용.
- 배경 시간 라인: `ForEach(0..<24)` → 각 시간의 `HStack { Text("09:00") Divider() }` 를 `.offset(y: hour * hourHeight)`로 배치.
- 이벤트 블록: 각 `TicItem`에 대해:
  - y 위치 = `startDate`의 분을 기준으로 계산 (예: 9:30 → `9.5 * hourHeight`)
  - 높이 = `(endDate - startDate)의 분 / 60 * hourHeight`
  - x 위치 = `layout[item.id].xOffset * containerWidth`
  - 너비 = `layout[item.id].widthFraction * containerWidth`
- 이벤트 블록 디자인:
  - 둥근 모서리 직사각형, 배경색 = 캘린더 고유 색상 (opacity 0.8)
  - 텍스트: 제목 (흰색 또는 검은색, 배경 밝기에 따라)
  - 탭 → `onEventTap(item)`
  - 꾹 누르기 → context menu (Phase 4에서 구현, 여기서는 탭만)
- **GeometryReader는 TimelineView 최상위에서 1번만 사용**하여 containerWidth를 구하라.
- 현재 시간 표시: 오늘인 경우, 현재 시각 위치에 빨간 가로선 + 빨간 원 표시 (Apple Calendar 스타일).
- 초기 스크롤 위치: 현재 시각 근처로 자동 스크롤.

타임라인 꾹 누르기:
- 빈 시간대를 꾹 누르면 해당 시간으로 `onTimeSlotLongPress(date)` 호출.
- 날짜 + 눌린 y 좌표 → 시간 계산: `hour = Int(yPosition / hourHeight)`, `minute = Int((yPosition.truncatingRemainder(dividingBy: hourHeight)) / hourHeight * 60)`

### 4. `/tic/Views/Components/NextActionCard.swift`

```swift
struct NextActionCard: View {
    var item: TicItem
    var onComplete: () -> Void  // 리마인더 완료용
    
    var body: some View {
        // 카드 디자인:
        // - 오렌지 좌측 바 (또는 상단 바)
        // - 제목, 시간 (HH:mm), "N분 후 시작" 또는 "진행 중"
        // - 리마인더인 경우: 체크 버튼
    }
}
```

디자인 규칙:
- 카드 배경: 시스템 `.secondarySystemBackground`
- 좌측에 오렌지 세로 바 (4pt 너비)
- 제목: `.headline` 폰트
- 시간 정보: `.subheadline` 폰트, 회색
- 오늘이 아닌 날짜에서는 이 카드를 표시하지 않음 (DayView에서 조건 처리)
- 남은 일정이 없으면 카드를 표시하지 않음

### 5. `/tic/Views/Components/ChecklistSheet.swift`

시간 없는 리마인더 체크리스트 bottom sheet.

```swift
struct ChecklistSheet: View {
    var reminders: [TicItem]
    var onToggle: (TicItem) -> Void
    
    var body: some View {
        // NavigationStack 또는 단순 VStack
        // 제목: "체크리스트"
        // 리스트: 각 리마인더 - 체크박스 + 제목
        // 체크 탭 → onToggle(item) → EventKitService.complete()
    }
}
```

### 6. ContentView에서 DayView 연결

ContentView의 scope == .day일 때 DayView를 표시하도록 이전 phase의 placeholder를 교체하라.
- DayViewModel을 @State로 생성
- selectedDate 변경 시 dayViewModel.loadItems 호출

### 7. xcodegen 재생성

파일 추가 후 `xcodegen generate` 실행.

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodegen generate && xcodebuild build -project tic.xcodeproj -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -1 | grep -q "BUILD SUCCEEDED"
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/0-tic-mvp/index.json`의 phase 3 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.
작업 중 사용자 개입이 반드시 필요한 상황이 발생하면 status를 `"blocked"`로, `"blocked_reason"` 필드에 사유를 기록하고 작업을 즉시 중단하라.

## 주의사항

- EventFormView는 아직 없다. `onEventTap`과 `onTimeSlotLongPress`는 콜백만 연결하고, 실제 sheet은 Phase 4에서 구현. 빈 sheet이나 print문으로 placeholder 처리.
- Context menu (꾹 누르기 → 수정/삭제/완료)도 Phase 4에서 구현. 이 phase에서는 탭만 동작하면 됨.
- `Color(cgColor:)` 초기화 시 CGColor가 nil일 수 있으므로 기본 색상(gray) fallback 처리.
- 타임라인의 hourHeight는 상수 (60pt 권장). 너무 작으면 이벤트 블록 텍스트가 안 보이고, 너무 크면 스크롤이 과해짐.
- column-packing 알고리즘에서 timedItems가 0개면 빈 딕셔너리를 반환하라 (크래시 방지).
- 시뮬레이터 이름이 `iPhone 16`이 아닐 수 있다. `xcrun simctl list devices available`로 확인하고 적절히 조정하라.
