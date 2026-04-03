# Phase 2: month-year-views

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `/docs/prd.md` — 제품 요구사항 (캘린더 뷰, 인터랙션, 네비게이션 바)
- `/docs/flow.md` — 사용자 흐름 (F2: 월간 뷰, F7: 년간 뷰)
- `/docs/code-architecture.md` — 코드 아키텍처 (네비게이션, CalendarScope)
- `/docs/adr.md` — ADR-006 (주간 뷰 제외), ADR-014 (Pinch 제스처)

그리고 이전 phase의 작업물을 반드시 확인하라:

- `/tic/Models/TicItem.swift`
- `/tic/Services/EventKitService.swift`
- `/tic/Extensions/Date+Extensions.swift`
- `/tic/ticApp.swift`
- `project.yml`

이전 phase에서 만들어진 코드를 꼼꼼히 읽고, 설계 의도를 이해한 뒤 작업하라.

## 작업 내용

월간 뷰(기본 화면), 년간 뷰, 그리고 이들을 연결하는 ContentView를 구현한다.

### 1. `/tic/ViewModels/CalendarViewModel.swift`

```swift
@Observable
class CalendarViewModel {
    var scope: CalendarScope = .month
    var selectedDate: Date = .now
    var displayedMonth: Date = .now  // 현재 표시 중인 월 (월간 뷰용)
    var displayedYear: Int = Calendar.current.component(.year, from: .now)
    
    // 월간 뷰 데이터
    func daysInMonth(for date: Date) -> [Date?]  // nil = 빈 칸 (이전 달 날짜)
    func hasEvents(on date: Date, service: EventKitService) -> Bool
    
    // 년간 뷰 데이터
    func monthsInYear() -> [Date]  // 12개월의 1일 배열
    
    // 네비게이션
    func goToToday()
    func selectDate(_ date: Date)
    func goToMonth(_ date: Date)
}

enum CalendarScope {
    case year, month, day
}
```

핵심 규칙:
- `daysInMonth`는 해당 월의 1일이 시작하는 요일에 맞춰 앞쪽에 nil을 채워라. 일요일 시작 기준.
- `selectDate`는 `selectedDate`를 변경하고 `scope`를 `.day`로 전환.
- `goToToday`는 `selectedDate = .now`, `displayedMonth = .now`, `scope`는 현재 유지.

### 2. `/tic/Views/ContentView.swift` (전면 재작성)

루트 뷰. scope에 따라 YearView, MonthView, DayView를 전환.

```swift
struct ContentView: View {
    @State private var viewModel = CalendarViewModel()
    @State private var eventKitService = EventKitService()
    @State private var showSettings = false
    @State private var showSearch = false
    @State private var showEventForm = false
    
    var body: some View {
        // 네비게이션 바: 좌 = 년/월 레이블(탭→오늘), 우 = ⚙️ 🔍 +
        // scope에 따른 뷰 전환
        // MagnifyGesture로 pinch 감지
    }
}
```

네비게이션 바 규칙:
- 좌상단 레이블:
  - `.year` scope → 년도 (예: "2026년")
  - `.month` scope → 년도 (예: "2026년")
  - `.day` scope → "← N월" (탭하면 .month로 복귀)
- 우상단: ⚙️ 🔍 + 아이콘 버튼 3개
- 년/월 레이블 탭 → `viewModel.goToToday()` (일간 뷰의 ← 버튼은 월간으로 복귀)

Pinch 제스처 규칙:
- `MagnifyGesture`를 사용.
- `onEnded`에서 scale 값 확인:
  - scale < 0.7 → zoom out (day→month→year)
  - scale > 1.5 → zoom in (year→month→day)
- scope 전환 시 `.animation(.easeInOut(duration: 0.3))` 적용.
- `matchedGeometryEffect`는 구현이 복잡하므로 MVP에서는 단순 전환 애니메이션으로 대체해도 됨.

### 3. `/tic/Views/Calendar/MonthView.swift`

월간 캘린더 그리드.

```swift
struct MonthView: View {
    var viewModel: CalendarViewModel
    var eventKitService: EventKitService
    // 7열 그리드 (일~토)
    // 각 날짜 셀: 숫자 + 일정 있으면 오렌지 점
    // 오늘 날짜: 오렌지 원 배경
    // 날짜 탭 → viewModel.selectDate(date)
}
```

디자인 규칙:
- `LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 7))` 사용.
- 요일 헤더: 일 월 화 수 목 금 토 (회색, 작은 폰트).
- 날짜 숫자: 기본 무채색. 오늘만 오렌지 원 배경에 흰색 텍스트.
- 일정 유무 점: 숫자 아래 작은 오렌지 원 (직경 ~4pt).
- 이전/다음 달 스와이프: `TabView(.page)` 또는 직접 swipe gesture.
- 금융 앱 톤: 얇은 폰트, 넉넉한 여백, 군더더기 없이.

### 4. `/tic/Views/Calendar/YearView.swift`

년간 뷰. 12개월 미니 캘린더.

```swift
struct YearView: View {
    var viewModel: CalendarViewModel
    var eventKitService: EventKitService
    // 3열 또는 4열 그리드로 12개월 표시
    // 각 월: 월 이름 + 미니 캘린더 (숫자만, 작은 폰트)
    // 일정 있는 날에 작은 점
    // 월 탭 → viewModel.goToMonth(date)
}
```

디자인 규칙:
- `LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 3))` — 3열 4행.
- 각 월 셀: 월 이름 (1월, 2월, ...) + 미니 7열 그리드 (숫자만, ~8pt 폰트).
- 일정 있는 날: 숫자 아래 작은 점 (2pt).
- 월 탭 → `viewModel.goToMonth(해당 월의 1일)` → scope를 `.month`로.

### 5. 첫 실행 시 권한 요청

ContentView의 `.onAppear` 또는 `.task`에서:
1. `eventKitService.requestCalendarAccess()`
2. `eventKitService.requestReminderAccess()`
3. `eventKitService.startObservingChanges()`

권한 거부 시 별도 처리 없음 — 빈 캘린더가 보일 뿐.

### 6. xcodegen 재생성

파일 추가 후 `xcodegen generate` 실행.

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodegen generate && xcodebuild build -project tic.xcodeproj -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -1 | grep -q "BUILD SUCCEEDED"
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/0-tic-mvp/index.json`의 phase 2 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.
작업 중 사용자 개입이 반드시 필요한 상황이 발생하면 status를 `"blocked"`로, `"blocked_reason"` 필드에 사유를 기록하고 작업을 즉시 중단하라.

## 주의사항

- DayView는 이 phase에서 구현하지 않는다. scope가 `.day`일 때는 placeholder 뷰(예: "일간 뷰 — Phase 3에서 구현")를 표시하라.
- SearchView, SettingsView, EventFormView도 아직 없다. 해당 sheet/navigation은 빈 뷰로 placeholder 처리.
- `hasEvents` 호출은 전체 월의 모든 날짜에 대해 반복 호출될 수 있으므로, EventKitService에서 한 달치 이벤트를 한 번에 fetch하고 캐시하는 것을 권장.
- 월간 뷰에서 이전/다음 달로 스와이프 시 `displayedMonth`를 업데이트하라.
- 시뮬레이터 이름이 `iPhone 16`이 아닐 수 있다. `xcrun simctl list devices available`로 확인하고 적절히 조정하라.
