# docs-diff: interaction-completion

Baseline: `6743e6c`

## `docs/adr.md`

```diff
diff --git a/docs/adr.md b/docs/adr.md
index 1b40724..300defe 100644
--- a/docs/adr.md
+++ b/docs/adr.md
@@ -83,3 +83,6 @@ cross-scope drag는 threshold와 상태 전이가 많아 SwiftUI에서 바로 
 
 ## ADR-028: Swift drag 포팅은 `ticTests`와 `draglab` 계약으로 검증
 SwiftUI gesture만으로 회귀를 잡으면 속도도 느리고 판단 기준도 흐려진다. 그래서 `DragSessionEngine`, geometry, hover hit-test는 `ticTests`의 순수 로직 XCTest로 먼저 검증한다. threshold와 최종 date/minute 계산 기준은 Python `draglab` fixture/score 계약과 일치해야 한다.
+
+## ADR-029: cross-scope drag path는 pinch scope bridge와 root coordinator 하나로 통일
+cross-day / cross-scope 이동은 여러 local fallback을 섞지 않고 단일 `root drag path`로 유지한다. `ContentView`가 `pinch scope transition` bridge owner이고, `CalendarDragCoordinator`가 session lifetime, overlay, cleanup을 맡는다. month/year drop이 성공하면 결과 날짜 기준으로 day scope로 복귀한다. legacy `edge-hover` timer fallback은 제거 대상이며, invalid drop 정책은 계속 `restore-first policy`를 따른다.
```

## `docs/code-architecture.md`

```diff
diff --git a/docs/code-architecture.md b/docs/code-architecture.md
index 376ae98..b60c4c1 100644
--- a/docs/code-architecture.md
+++ b/docs/code-architecture.md
@@ -52,17 +52,17 @@ tic/
 │   └── SearchViewModel.swift        // 검색어, 필터링, 기록
 │
 ├── Views/
-│   ├── ContentView.swift            // 루트: scope 전환, pinch, 내비바, LA 시작 로직
+│   ├── ContentView.swift            // 루트: scope pinch bridge owner, 내비바, LA 시작 로직
 │   ├── Calendar/
 │   │   ├── YearView.swift           // 12개월 그리드 + "올해" 버튼
 │   │   ├── MonthView.swift          // 캘린더 그리드 + "이번달" 버튼
-│   │   └── DayView.swift            // 주간 스트립 + 타임라인 + phantom block + 편집 모드 상태
+│   │   └── DayView.swift            // 주간 스트립 + 타임라인 + phantom block + 편집 모드 상태 (legacy edge-hover 상태는 제거 대상)
 │   ├── EventFormView.swift          // Segmented Control + 하루종일 토글 + 둥근 스타일
 │   ├── SearchView.swift
 │   ├── SettingsView.swift
 │   └── Components/
 │       ├── TimelineView.swift       // 24시간 타임라인 + 이벤트 블록 (기본 상태)
-│       ├── EditableEventBlock.swift  // 편집 모드 핸들 + 리사이즈 + 이동 + toolbar (500줄 초과 시 분리)
+│       ├── EditableEventBlock.swift  // 편집 모드 핸들 + 리사이즈 + pointer forwarding + toolbar
 │       ├── NextActionCard.swift
 │       └── ChecklistSheet.swift
 │
@@ -182,7 +182,9 @@ final class CalendarDragCoordinator {
 ```
 
 - `ContentView`가 `CalendarDragCoordinator`를 단일 owner로 가진다.
+- `ContentView`가 `pinch scope transition` bridge의 owner다.
 - `DayView`, `MonthView`, `YearView`는 owner가 아니라 geometry/frame reporting 역할만 가진다.
+- `DayView`의 legacy `edge-hover` timer/indicator 상태는 제거 대상이다.
 - scope가 바뀌어도 coordinator와 overlay는 유지된다.
 
 ## z-index / 제스처 우선순위
@@ -201,7 +203,7 @@ ZStack 순서 (아래 → 위):
 
 ## 날짜 간 블록 이동 (overlay 패턴)
 
-드래그 중인 블록을 타임라인에서 분리 → `ContentView` 수준의 root overlay owner가 렌더링한다. 타임라인 전환 애니메이션과 drag session 수명을 분리하기 위함이다.
+드래그 중인 블록을 타임라인에서 분리 → `ContentView` 수준의 root overlay owner가 렌더링한다. 타임라인 전환 애니메이션과 drag session 수명을 분리하기 위함이다. 이 경로가 cross-day / cross-scope 이동의 단일 `root drag path`다.
 
 ```swift
 struct DateCellFrame {
@@ -233,7 +235,9 @@ struct DragSessionContext {
 핵심 규칙:
 
 - drag session은 day → month/year 전환 중에도 유지된다.
+- `pinch scope transition`은 `ContentView`가 owner인 bridge를 통해 같은 session 위에서 처리한다.
 - 원본 블록은 placeholder/ghost처럼 남고, 실제 이동 중 블록은 전역 overlay로만 렌더링한다.
+- `EditableEventBlock`은 local move completion owner가 아니라 pointer forwarding 역할만 가진다.
 - `droppable`은 독립 top-level state가 아니라, current state + candidate 유효성에서 계산되는 파생 판정이다.
 - invalid drop, overflow, missing candidate는 clamp보다 `restore`를 우선한다.
 - overlay와 날짜 셀 hit-test는 모두 `global coordinates`를 기준으로 계산한다.
@@ -268,10 +272,11 @@ enum DragOutcome {
 `CalendarDragCoordinator`는 SwiftUI glue layer다.
 
 - `ContentView`가 단일 인스턴스를 소유한다.
-- `viewModel.scope` 변경을 감지해 엔진에 새 scope를 전달한다.
+- `viewModel.scope` 변경과 `pinch scope transition`을 감지해 엔진에 새 scope를 전달한다.
 - timeline frame과 month/year 날짜 셀 frame registry를 유지한다.
 - root overlay 렌더링에 필요한 `overlaySnapshot`을 제공한다.
 - EventKit write는 최종 drop 확정 시에만 호출하고, 계산 로직은 여전히 엔진/geometry에 둔다.
+- session cleanup은 `CalendarDragCoordinator`와 root scope에서 commit/cancel/restore 이후 일관되게 수행한다.
 
 ## Swift / Python 공통 계약
 
```

## `docs/flow.md`

```diff
diff --git a/docs/flow.md b/docs/flow.md
index e2768f1..a77caea 100644
--- a/docs/flow.md
+++ b/docs/flow.md
@@ -17,6 +17,7 @@
  왼쪽 하단: "이번달" floating 버튼 (Capsule, .ultraThinMaterial)
  
  날짜 탭 → F3 (해당 날짜 일간 뷰)
+ Pinch in → F3 (selectedDate 기준 일간 뷰)
  Pinch out → F7 (년간 뷰)
  "2026년" 탭 → 오늘로 이동
  "이번달" 탭 → 올해의 이번달로 스크롤
@@ -25,12 +26,13 @@
  ⚙️ 탭 → F8 (설정)
 
  drag session 중:
-  month scope는 전환 대상이 될 수 있음
-  전환 뒤에도 drag session 유지
+  pinch scope transition으로 day/year scope 전환 가능
+  `CalendarDragCoordinator` session을 유지한 채 scope만 교체
   overlay는 root scope 위에서 계속 유지
   각 날짜 셀 hover → activeDate 갱신
   날짜 셀 판정은 global coordinates 기준 hit-test
   drop 시 activeDate + minuteCandidate로 최종 확정
+  month drop 성공 시 결과 날짜 기준으로 day scope로 복귀
 ```
 
 ## F3: 일간 뷰
@@ -82,13 +84,14 @@
  조작:
   꼭짓점 드래그 → 리사이즈 (15분 스냅, 최소 30분)
   블록 본체 y축 드래그 → 같은 날 이동 (15분 스냅, 자동 스크롤)
-  블록 본체 좌우 드래그 → 날짜 전환 slide + 새 날짜 배치 (손가락 위치 기준)
-  drag session 중 `viewModel.scope` 변경 경로(예: pinch out)로 month/year scope로 전환 가능
+  블록 본체 이동은 단일 root drag path로만 처리
+  drag session 중 pinch scope transition으로 day/month/year scope 전환 가능
   drag session 중 원본 블록은 placeholder/ghost처럼 남고, 실제 이동 중 블록은 전역 overlay로 유지
   overlay owner는 DayView가 아니라 root `CalendarDragCoordinator`
   day timeline에서는 `dateCandidate`, `minuteCandidate`를 둘 다 갱신
   month/year에서는 `activeDate`만 갱신하고 `minuteCandidate`는 drag session이 유지
   drop 시 `dateCandidate + minuteCandidate + duration`으로 확정
+  month/year drop 성공 시 결과 날짜 기준으로 day scope로 복귀
   삭제 탭 → 확인 alert → EventKit 삭제
   복제 탭 → 같은 시간에 즉시 배치 (반복 규칙 제외, sheet 없음)
 
@@ -97,6 +100,7 @@
   편집 블록 탭 → toolbar만 닫힘, 편집 모드 유지
   다른 블록 long press → 현재 해제 → 새 블록 편집 모드
   invalid drop / overflow / hover 미확정 / cancel → restore 후 종료
+  legacy edge-hover timer 기반 인접 날짜 이동은 핵심 경로가 아니며 제거 대상
 
  비활성화:
   타임라인 좌우 스와이프 (블록 드래그와 충돌 방지)
@@ -165,10 +169,12 @@
  "올해" 탭 → 올해로 스크롤
 
  drag session 중:
-  year scope도 전환 대상이 될 수 있음
+  pinch scope transition으로 month scope 전환 가능
+  `CalendarDragCoordinator` session을 유지한 채 scope만 교체
   pointer가 날짜 셀 위에서 안정적으로 머물면 activeDate 갱신
   overlay는 root scope 위에서 유지되고, scope 교체만으로는 종료되지 않음
   drop은 activeDate가 있고 minuteCandidate가 유지된 경우에만 허용
+  year drop 성공 시 결과 날짜 기준으로 day scope로 복귀
   invalid drop은 확정하지 않고 restore
 ```
 
```

## `docs/prd.md`

```diff
diff --git a/docs/prd.md b/docs/prd.md
index ce10efe..89485e6 100644
--- a/docs/prd.md
+++ b/docs/prd.md
@@ -33,10 +33,10 @@ Apple Calendar 이벤트와 Apple Reminders를 하나의 미니멀 인터페이
 |------|------|
 | 꼭짓점 리사이즈 | 상단-우측(시작시간), 하단-좌측(종료시간) 핸들. 15분 단위 스냅. 최소 30분. 핸들 옆 tooltip으로 시간 실시간 표시 |
 | 블록 이동 (같은 날) | 블록 본체 y축 드래그. 15분 단위 스냅. 자동 스크롤 지원 |
-| 블록 이동 (날짜 간) | 블록 본체 좌우 드래그 → 타임라인 slide 전환 → 새 날짜에 배치. 손가락 위치 기준. overlay 패턴으로 구현 |
-| 블록 이동 (scope 간) | drag session은 day → month/year 전환 중에도 유지. root `CalendarDragCoordinator`가 전역 overlay를 소유하고, 원본 블록은 placeholder/ghost처럼 남는다. |
-| drop 계산 | day timeline은 `dateCandidate`, `minuteCandidate`를 둘 다 갱신. month/year는 `activeDate`만 갱신하고 `minuteCandidate`는 drag session이 유지. 최종 drop은 `dateCandidate + minuteCandidate + duration`으로 계산한다. Swift와 Python이 동일한 규칙을 사용한다. |
-| 오류 처리 | invalid drop, overflow, hover 미확정, cancel은 clamp보다 `restore-first policy`를 우선한다. |
+| 블록 이동 (날짜 간) | cross-day move도 별도 local fallback 없이 단일 `root drag path`로 처리한다. 원본 블록은 placeholder/ghost처럼 남고, 실제 이동 블록은 root overlay로만 렌더링한다. |
+| 블록 이동 (scope 간) | `pinch scope transition`은 문서상의 제스처가 아니라 실제 구현 대상이다. drag session은 day → month/year 전환 중에도 유지되며, root `CalendarDragCoordinator`가 전역 overlay와 session lifetime을 소유한다. |
+| drop 계산 | day timeline은 `dateCandidate`, `minuteCandidate`를 둘 다 갱신한다. month/year는 `activeDate`만 갱신하고 `minuteCandidate`는 drag session이 유지한다. 최종 drop은 `dateCandidate + minuteCandidate + duration`으로 계산하며, 성공 후 `selectedDate`와 화면 scope는 결과 날짜의 day 기준으로 맞춘다. Swift와 Python이 동일한 규칙을 사용한다. |
+| 오류 처리 | invalid drop, overflow, hover 미확정, cancel은 clamp보다 `restore-first policy`를 우선한다. legacy `edge-hover` fallback은 제거 대상이다. |
 | Floating toolbar | [삭제 \| 복제]. 블록 아래 (공간 부족 시 위). `.ultraThinMaterial` + cornerRadius(12) |
 | 해제 | 빈 영역 탭. 편집 중 블록 탭 → toolbar만 닫힘. 다른 블록 long press → 전환 |
 
@@ -45,6 +45,7 @@ Apple Calendar 이벤트와 Apple Reminders를 하나의 미니멀 인터페이
 - 입력은 `sessions.json`, `events.json`, `expected.json` 세 파일을 사용한다.
 - 목적은 threshold, 상태 전이, geometry 계약, 채점 규칙을 빠르게 반복 검증하고, Swift에 동일한 계산 기준을 옮기는 것이다.
 - Swift 포팅은 `CalendarDragCoordinator`, `DragSessionEngine`, `ticTests` 기반으로 진행한다.
+- cross-day / cross-scope move는 SwiftUI local completion 경로를 섞지 않고 단일 `root drag path`만 사용한다.
 - `minuteCandidate`, `activeDate`, drop validity, restore 정책은 Python `draglab` 계약과 동일해야 한다.
 - 테스트는 mock-heavy UI 테스트보다 순수 로직 XCTest를 우선한다.
 - 병렬 실험은 세션 내부가 아니라 `config` 또는 `session chunk` 단위로만 수행한다.
@@ -112,17 +113,17 @@ Apple Calendar 이벤트와 Apple Reminders를 하나의 미니멀 인터페이
 | 제스처 | 컨텍스트 | 동작 |
 |--------|----------|------|
 | 날짜 탭 | 월간 뷰 | → 일간 뷰 |
-| Pinch out | 일→월→년 | scope 확대 |
-| Pinch in | 년→월→일 | scope 축소 |
+| pinch out | 일→월→년 | scope 확대. drag session 중에도 같은 `pinch scope transition` 경로를 사용한다. |
+| pinch in | 년→월→일 | scope 축소. month/year drop 성공 후에는 결과 날짜 기준으로 day scope로 복귀한다. |
 | 이벤트 탭 | 일간 뷰 (기본 상태) | → 수정 bottom sheet |
 | 이벤트 long press | 일간 뷰 | → 편집 모드 (핸들 + toolbar) |
 | 빈 타임라인 long press | 일간 뷰 | → phantom block + 생성 sheet |
 | 시간 라벨 long press | 일간 뷰 | → phantom block + 생성 sheet (빈 타임라인과 동일) |
 | 좌우 스와이프 | 일간 뷰 (기본 상태) | 날짜 이동 |
-| 블록 좌우 드래그 | 일간 뷰 (편집 모드) | 날짜 간 블록 이동 |
-| drag session 유지 | 일간 뷰 (편집 모드) | Pinch out 또는 scope 전환 뒤에도 drag session 유지 |
+| 블록 좌우 드래그 | 일간 뷰 (편집 모드) | 같은 session 안에서 `root drag path`를 시작한다. legacy `edge-hover` timer fallback은 제거 대상이다. |
+| drag session 유지 | 일간 뷰 (편집 모드) | pinch 또는 다른 scope 전환 뒤에도 `CalendarDragCoordinator` session을 유지한다. |
 | 날짜 셀 hover | 월간/년간 뷰 (drag session 중) | `activeDate` 갱신 |
-| drop | 월간/년간 뷰 (drag session 중) | `activeDate + minuteCandidate + duration`이 유효할 때만 확정, 아니면 restore |
+| drop | 월간/년간 뷰 (drag session 중) | `activeDate + minuteCandidate + duration`이 유효할 때만 확정, 아니면 restore. 성공 후 `selectedDate`와 화면 scope는 결과 날짜의 day 기준으로 맞춘다. |
 | 빈 영역 탭 | 일간 뷰 (편집 모드) | 편집 모드 해제 |
 | "이번달" 탭 | 월간 뷰 | 이번 달로 스크롤 |
 | "올해" 탭 | 년간 뷰 | 올해로 스크롤 |
```
