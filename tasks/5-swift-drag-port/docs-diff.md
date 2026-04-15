# docs-diff: swift-drag-port

Baseline: `2be29ed`

## `docs/adr.md`

```diff
diff --git a/docs/adr.md b/docs/adr.md
index d23ce36..1b40724 100644
--- a/docs/adr.md
+++ b/docs/adr.md
@@ -77,3 +77,9 @@ day timeline에서 시작된 drag session은 month/year scope 전환 중에도 
 
 ## ADR-026: Python draglab을 Swift 계약/튜닝 기준 환경으로 사용
 cross-scope drag는 threshold와 상태 전이가 많아 SwiftUI에서 바로 튜닝하기 비효율적이다. `experiments/draglab/`에서 JSON fixture 기반 replay, scoring, metric, parameter 탐색을 먼저 수행하고, 검증된 geometry/date/minute 규칙을 Swift로 이식한다. 병렬 실험은 세션 내부가 아니라 `config` 또는 `session chunk` 단위로만 수행한다.
+
+## ADR-027: Cross-scope drag session owner는 scope switch 위의 단일 coordinator
+`DayView`가 drag session owner이면 `ContentView.scopeView` 교체 시 session이 끊긴다. 그래서 실제 owner는 `ContentView` 수준의 `CalendarDragCoordinator` 하나로 둔다. `DayView`, `MonthView`, `YearView`는 pointer/frame/reporting만 담당하고, overlay와 session lifetime은 coordinator가 가진다.
+
+## ADR-028: Swift drag 포팅은 `ticTests`와 `draglab` 계약으로 검증
+SwiftUI gesture만으로 회귀를 잡으면 속도도 느리고 판단 기준도 흐려진다. 그래서 `DragSessionEngine`, geometry, hover hit-test는 `ticTests`의 순수 로직 XCTest로 먼저 검증한다. threshold와 최종 date/minute 계산 기준은 Python `draglab` fixture/score 계약과 일치해야 한다.
```

## `docs/code-architecture.md`

```diff
diff --git a/docs/code-architecture.md b/docs/code-architecture.md
index 05b14ae..376ae98 100644
--- a/docs/code-architecture.md
+++ b/docs/code-architecture.md
@@ -27,6 +27,12 @@ ViewModel → EventKitService → EventKit에 직접 쓰기
 tic/
 ├── ticApp.swift                     // @main, SwiftData, 딥링크 처리
 │
+├── DragSession/
+│   ├── CalendarDragCoordinator.swift // root overlay owner, drag session 수명 관리
+│   ├── DragSessionTypes.swift        // 상태, 컨텍스트, snapshot 계약
+│   ├── DragSessionGeometry.swift     // minute/date/frame 계산 규칙
+│   └── DragSessionEngine.swift       // 순수 상태 전이 엔진
+│
 ├── Models/
 │   ├── TicItem.swift                // 통합 뷰 모델 (struct, 인메모리)
 │   ├── TicActivityAttributes.swift  // ActivityAttributes + ContentState (다중 이벤트)
@@ -70,6 +76,10 @@ tic/
 │   ├── WidgetProvider.swift
 │   └── WidgetIntents.swift          // CompleteEventIntent, SnoozeEventIntent
 │
+├── ticTests/
+│   ├── DragSessionGeometryTests.swift
+│   └── DragSessionEngineTests.swift
+│
 └── TicLiveActivityView.swift        // Lock Screen + Dynamic Island (progress line UI)
 
 experiments/
@@ -140,14 +150,13 @@ class LiveActivityService {
 
 ## 편집 모드 상태 관리
 
-편집 모드는 트랜지언트 UI 상태 → **DayView @State**로 관리 (ViewModel 아님).
+편집 모드는 트랜지언트 UI 상태 → **DayView @State**로 관리한다. 다만 cross-scope drag session만큼은 `DayView`에 두지 않고 root owner로 올린다.
 
 ```swift
 // DayView @State
 @State var phantomBlock: PhantomBlock?       // {hour, minute, calendar}
 @State var editingItemId: String?            // 편집 중인 블록 ID
 @State var showPhantomSheet: Bool = false
-@State var crossDayDragState: CrossDayDragState?
 
 // TimelineView에 Binding으로 전달
 editingItemId: Binding<String?>
@@ -155,7 +164,6 @@ onResizeStart: (String, Date) -> Void
 onResizeEnd: (String, Date) -> Void
 onMoveItem: (String, Date, Date) -> Void
 onDuplicateItem: (String) -> Void
-onCrossDayDrag: (String, Edge) -> Void
 phantomBlock: PhantomBlock?
 ```
 
@@ -163,6 +171,20 @@ phantomBlock: PhantomBlock?
 
 단, cross-scope drag가 커지면 View의 임시 상태만으로는 상태 전이 규칙을 안전하게 유지하기 어렵다. 그래서 SwiftUI View가 모든 제스처 로직을 직접 품는 대신, 순수 로직을 담는 `DragSessionEngine` 계층을 별도로 둔다.
 
+```swift
+@Observable
+final class CalendarDragCoordinator {
+    var engine: DragSessionEngine
+    var overlaySnapshot: DragSessionSnapshot?
+    var registry: [CalendarScope: [DateCellFrame]]
+    var timelineFrameGlobal: CGRect?
+}
+```
+
+- `ContentView`가 `CalendarDragCoordinator`를 단일 owner로 가진다.
+- `DayView`, `MonthView`, `YearView`는 owner가 아니라 geometry/frame reporting 역할만 가진다.
+- scope가 바뀌어도 coordinator와 overlay는 유지된다.
+
 ## z-index / 제스처 우선순위
 
 ```
@@ -179,17 +201,16 @@ ZStack 순서 (아래 → 위):
 
 ## 날짜 간 블록 이동 (overlay 패턴)
 
-드래그 중인 블록을 타임라인에서 분리 → DayView 최상위 overlay로 렌더링. 타임라인 전환 애니메이션과 독립 동작.
+드래그 중인 블록을 타임라인에서 분리 → `ContentView` 수준의 root overlay owner가 렌더링한다. 타임라인 전환 애니메이션과 drag session 수명을 분리하기 위함이다.
 
 ```swift
-struct CrossDayDragState {
-    let item: TicItem
-    var currentOffset: CGSize   // 손가락 위치
-    var targetDate: Date        // 이동할 날짜
+struct DateCellFrame {
+    let date: Date
+    let frameGlobal: CGRect
 }
 ```
 
-cross-scope drag까지 확장할 때는 아래 정보를 별도 drag session 컨텍스트로 추적한다.
+cross-scope drag는 아래 drag session 컨텍스트로 추적한다.
 
 ```swift
 struct DragSessionContext {
@@ -215,6 +236,7 @@ struct DragSessionContext {
 - 원본 블록은 placeholder/ghost처럼 남고, 실제 이동 중 블록은 전역 overlay로만 렌더링한다.
 - `droppable`은 독립 top-level state가 아니라, current state + candidate 유효성에서 계산되는 파생 판정이다.
 - invalid drop, overflow, missing candidate는 clamp보다 `restore`를 우선한다.
+- overlay와 날짜 셀 hit-test는 모두 `global coordinates`를 기준으로 계산한다.
 
 ## DragSessionEngine
 
@@ -241,6 +263,16 @@ enum DragOutcome {
 - 엔진은 `DragSessionContext`, `DragState`, 파생 `droppable`, overlay frame, drop candidate를 계산한다.
 - Swift 구현 전에 동일한 규칙을 Python `draglab`에서 먼저 검증한다.
 
+## CalendarDragCoordinator
+
+`CalendarDragCoordinator`는 SwiftUI glue layer다.
+
+- `ContentView`가 단일 인스턴스를 소유한다.
+- `viewModel.scope` 변경을 감지해 엔진에 새 scope를 전달한다.
+- timeline frame과 month/year 날짜 셀 frame registry를 유지한다.
+- root overlay 렌더링에 필요한 `overlaySnapshot`을 제공한다.
+- EventKit write는 최종 drop 확정 시에만 호출하고, 계산 로직은 여전히 엔진/geometry에 둔다.
+
 ## Swift / Python 공통 계약
 
 Swift와 Python은 아래 계산 기준을 공유한다.
@@ -273,6 +305,12 @@ Swift와 Python은 아래 계산 기준을 공유한다.
 - nested pool 금지
 - deterministic seed 유지
 
+## 테스트 전략
+
+- `ticTests`를 추가해 `DragSessionEngine`, geometry, hover hit-test 같은 순수 로직을 XCTest로 검증한다.
+- mock-heavy UI 테스트는 만들지 않는다.
+- SwiftUI View는 coordinator/engine integration 수준까지만 빌드 검증한다.
+
 ## 타임라인 레이아웃 알고리즘
 column-packing: 시작 시간 정렬 → 충돌 클러스터 그룹화 → 탐욕적 열 할당 → 너비 균등 분할. 뷰 body 바깥에서 `LayoutAttributes` 미리 계산, 날짜별 캐시.
 
```

## `docs/flow.md`

```diff
diff --git a/docs/flow.md b/docs/flow.md
index 0a3129b..e2768f1 100644
--- a/docs/flow.md
+++ b/docs/flow.md
@@ -27,7 +27,9 @@
  drag session 중:
   month scope는 전환 대상이 될 수 있음
   전환 뒤에도 drag session 유지
+  overlay는 root scope 위에서 계속 유지
   각 날짜 셀 hover → activeDate 갱신
+  날짜 셀 판정은 global coordinates 기준 hit-test
   drop 시 activeDate + minuteCandidate로 최종 확정
 ```
 
@@ -81,8 +83,9 @@
   꼭짓점 드래그 → 리사이즈 (15분 스냅, 최소 30분)
   블록 본체 y축 드래그 → 같은 날 이동 (15분 스냅, 자동 스크롤)
   블록 본체 좌우 드래그 → 날짜 전환 slide + 새 날짜 배치 (손가락 위치 기준)
-  drag session 중 Pinch out → month/year scope로 전환 가능
+  drag session 중 `viewModel.scope` 변경 경로(예: pinch out)로 month/year scope로 전환 가능
   drag session 중 원본 블록은 placeholder/ghost처럼 남고, 실제 이동 중 블록은 전역 overlay로 유지
+  overlay owner는 DayView가 아니라 root `CalendarDragCoordinator`
   day timeline에서는 `dateCandidate`, `minuteCandidate`를 둘 다 갱신
   month/year에서는 `activeDate`만 갱신하고 `minuteCandidate`는 drag session이 유지
   drop 시 `dateCandidate + minuteCandidate + duration`으로 확정
@@ -164,6 +167,7 @@
  drag session 중:
   year scope도 전환 대상이 될 수 있음
   pointer가 날짜 셀 위에서 안정적으로 머물면 activeDate 갱신
+  overlay는 root scope 위에서 유지되고, scope 교체만으로는 종료되지 않음
   drop은 activeDate가 있고 minuteCandidate가 유지된 경우에만 허용
   invalid drop은 확정하지 않고 restore
 ```
```

## `docs/prd.md`

```diff
diff --git a/docs/prd.md b/docs/prd.md
index e05ae22..ce10efe 100644
--- a/docs/prd.md
+++ b/docs/prd.md
@@ -13,8 +13,8 @@ Apple Calendar 이벤트와 Apple Reminders를 하나의 미니멀 인터페이
 ## 핵심 기능
 
 ### 캘린더 뷰
-- **월간 뷰** (기본): 그리드에 일정 있는 날 오렌지 점 표시. 오늘은 오렌지 원. 날짜 탭 → 일간 뷰. Pinch out → 년간 뷰. 왼쪽 하단 "이번달" floating 버튼 → 이번 달로 스크롤. drag session 중에도 month scope는 유지될 수 있으며, 날짜 셀 hover로 `activeDate`를 갱신한다.
-- **년간 뷰**: 12개월 미니 그리드. 월 탭 → 월간 뷰. Pinch in → 월간 뷰. 왼쪽 하단 "올해" floating 버튼. drag session 중에는 year scope에서도 날짜 hover와 drop 후보 계산을 지원한다.
+- **월간 뷰** (기본): 그리드에 일정 있는 날 오렌지 점 표시. 오늘은 오렌지 원. 날짜 탭 → 일간 뷰. Pinch out → 년간 뷰. 왼쪽 하단 "이번달" floating 버튼 → 이번 달로 스크롤. drag session 중에도 month scope는 유지될 수 있으며, 날짜 셀 hover로 `activeDate`를 갱신한다. hover 판정은 `global coordinates` 기준 frame hit-test를 사용한다.
+- **년간 뷰**: 12개월 미니 그리드. 월 탭 → 월간 뷰. Pinch in → 월간 뷰. 왼쪽 하단 "올해" floating 버튼. drag session 중에는 year scope에서도 날짜 hover와 drop 후보 계산을 지원한다. scope 교체 중에도 root overlay는 유지된다.
 - **일간 뷰**: "다음 행동" 카드 (오늘만) + 주간 스트립 + 24시간 타임라인 + 리마인더 체크리스트 FAB. 좌우 스와이프로 날짜 이동 (주간 스트립 + 타임라인 독립 slide 애니메이션). Pinch out → 월간 뷰.
 - **MVP에서 주간 뷰 제외.**
 
@@ -34,8 +34,8 @@ Apple Calendar 이벤트와 Apple Reminders를 하나의 미니멀 인터페이
 | 꼭짓점 리사이즈 | 상단-우측(시작시간), 하단-좌측(종료시간) 핸들. 15분 단위 스냅. 최소 30분. 핸들 옆 tooltip으로 시간 실시간 표시 |
 | 블록 이동 (같은 날) | 블록 본체 y축 드래그. 15분 단위 스냅. 자동 스크롤 지원 |
 | 블록 이동 (날짜 간) | 블록 본체 좌우 드래그 → 타임라인 slide 전환 → 새 날짜에 배치. 손가락 위치 기준. overlay 패턴으로 구현 |
-| 블록 이동 (scope 간) | drag session은 day → month/year 전환 중에도 유지. 전역 overlay가 손가락과 함께 이동하고, 원본 블록은 placeholder/ghost처럼 남는다. |
-| drop 계산 | day timeline은 `dateCandidate`, `minuteCandidate`를 둘 다 갱신. month/year는 `activeDate`만 갱신하고 `minuteCandidate`는 drag session이 유지. 최종 drop은 `dateCandidate + minuteCandidate + duration`으로 계산한다. |
+| 블록 이동 (scope 간) | drag session은 day → month/year 전환 중에도 유지. root `CalendarDragCoordinator`가 전역 overlay를 소유하고, 원본 블록은 placeholder/ghost처럼 남는다. |
+| drop 계산 | day timeline은 `dateCandidate`, `minuteCandidate`를 둘 다 갱신. month/year는 `activeDate`만 갱신하고 `minuteCandidate`는 drag session이 유지. 최종 drop은 `dateCandidate + minuteCandidate + duration`으로 계산한다. Swift와 Python이 동일한 규칙을 사용한다. |
 | 오류 처리 | invalid drop, overflow, hover 미확정, cancel은 clamp보다 `restore-first policy`를 우선한다. |
 | Floating toolbar | [삭제 \| 복제]. 블록 아래 (공간 부족 시 위). `.ultraThinMaterial` + cornerRadius(12) |
 | 해제 | 빈 영역 탭. 편집 중 블록 탭 → toolbar만 닫힘. 다른 블록 long press → 전환 |
@@ -44,6 +44,9 @@ Apple Calendar 이벤트와 Apple Reminders를 하나의 미니멀 인터페이
 - `experiments/draglab/`에서 Python CLI 기반 drag 실험기를 운영한다.
 - 입력은 `sessions.json`, `events.json`, `expected.json` 세 파일을 사용한다.
 - 목적은 threshold, 상태 전이, geometry 계약, 채점 규칙을 빠르게 반복 검증하고, Swift에 동일한 계산 기준을 옮기는 것이다.
+- Swift 포팅은 `CalendarDragCoordinator`, `DragSessionEngine`, `ticTests` 기반으로 진행한다.
+- `minuteCandidate`, `activeDate`, drop validity, restore 정책은 Python `draglab` 계약과 동일해야 한다.
+- 테스트는 mock-heavy UI 테스트보다 순수 로직 XCTest를 우선한다.
 - 병렬 실험은 세션 내부가 아니라 `config` 또는 `session chunk` 단위로만 수행한다.
 
 ### 일정 추가 폼
```
