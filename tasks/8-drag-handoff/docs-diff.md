# docs-diff: drag-handoff

Baseline: `7387a7c`

## `docs/adr.md`

```diff
diff --git a/docs/adr.md b/docs/adr.md
index 06830cc..d9fe14a 100644
--- a/docs/adr.md
+++ b/docs/adr.md
@@ -89,3 +89,16 @@ cross-day / cross-scope 이동은 여러 local fallback을 섞지 않고 단일
 
 ## ADR-030: cross-scope 동안 타임블록은 하나의 session identity를 유지하고 presentation만 바꾼다
 cross-scope drag의 핵심은 블록이 사라졌다가 새로 생기는 것처럼 보이지 않는 것이다. 따라서 블록 identity는 drag session 전체에서 하나로 유지하고, 표현만 `timelineCard`와 `calendarPill` 사이에서 바꾼다. 실제 이동 객체는 항상 하나의 `single overlay`만 유지한다. month/year 날짜 강조도 하나의 `single active target`만 허용한다. `selectedDate`는 확정 전까지 유지하고, `activeDate`는 hover candidate로만 사용한다. 최종 확정은 `drop on touch up`만 허용하고, invalid drop은 계속 `restore-first policy`를 따른다. 성공 commit 시에만 편집 모드 종료다.
+
+## ADR-031: drag ownership handoff는 bounded `touch claim` 계약으로 고정한다
+이번 drag 고장의 핵심은 소유권 전환 순서가 느슨했다는 점이다. `source block -> placeholder` 전환이 root claim보다 먼저 일어나면 local preview와 root overlay가 동시에 owner처럼 보인다. local/global 좌표가 섞인 상태로 handoff를 진행하면 첫 프레임 점프와 잘못된 hit-test가 겹친다. `captureTouch(near:)`의 동기 성공을 drag 시작 조건으로 두면 root recognizer가 아직 touch를 관측하지 못한 첫 프레임에서 drag가 시작되지 않을 수 있다.
+
+결정:
+
+- `bounded handoff`는 local preview 즉시 lift → explicit `touch claim` 성공 → root ownership 전환 순서로만 진행한다.
+- claim pending 동안에는 source placeholder, root overlay, month/year `activeDate` hover를 켜지 않는다.
+- claim window는 `2 frame 이내의 매우 짧은 window`로 유지한다. 실패나 timeout이면 `restore-first policy`로 즉시 복구한다.
+- `selectedDate`는 commit 전까지 바꾸지 않는다. `activeDate`는 root ownership 이후 month/year hover candidate로만 사용한다.
+- stale claim success / stale end / stale cancel은 현재 token과 맞지 않으면 무시한다.
+- 최소 관측성 이벤트는 `drag_start`, `root_claim_success`, `root_claim_timeout`, `restore_reason`, `claim_latency_ms`다.
+- 이 관측성은 디버그와 회귀 재현용이다. hot path마다 무거운 로깅을 추가하는 목적이 아니다.
```

## `docs/code-architecture.md`

```diff
diff --git a/docs/code-architecture.md b/docs/code-architecture.md
index 68d7854..c45a145 100644
--- a/docs/code-architecture.md
+++ b/docs/code-architecture.md
@@ -176,6 +176,12 @@ phantomBlock: PhantomBlock?
 - gesture state: pointer 위치, finger anchor, hover hit-test 입력
 - display state: `timelineCard`/`calendarPill`, opacity, shadow, scale, restore/landing phase
 
+cross-scope drag는 여기에 ownership handoff state를 하나 더 둔다.
+
+- local preview owner: source block 안에서 즉시 lift되는 미리보기
+- root owner: explicit `touch claim` 성공 뒤 `CalendarDragCoordinator`가 소유하는 `single overlay`
+- handoff token: claim success, end, cancel이 현재 session과 같은지 확인하는 식별자
+
 display state는 raw gesture 분기에서 직접 결정하지 않고, coordinator 또는 인접 순수 helper가 계산한 presentation phase를 따른다.
 
 ```swift
@@ -247,15 +253,21 @@ struct DragSessionContext {
 
 - drag session은 day → month/year 전환 중에도 유지된다.
 - `pinch scope transition`은 `ContentView`가 owner인 bridge를 통해 같은 session 위에서 처리한다.
-- 원본 블록은 placeholder/ghost처럼 남고, 실제 이동 중 블록은 전역 overlay로만 렌더링한다.
+- `bounded handoff`는 source local preview → explicit `touch claim` → root `single overlay` 순서를 지킨다.
+- `captureTouch(near:)`의 동기 성공을 drag 시작 조건으로 두지 않는다. root recognizer가 첫 프레임에 아직 touch를 관측하지 못했을 수 있기 때문이다.
+- root ownership이 오기 전에는 source placeholder, root overlay, month/year `activeDate` hover를 켜지 않는다.
+- 원본 블록은 root claim 성공 뒤에만 placeholder/ghost처럼 남고, 실제 이동 중 블록은 전역 overlay로만 렌더링한다.
 - `EditableEventBlock`은 local move completion owner가 아니라 pointer forwarding 역할만 가진다.
 - drag 중 실시간 추적은 per-frame animation이 아니라 직접 position 업데이트로 처리한다.
 - 상태 전환 애니메이션만 명시적으로 `withAnimation` 또는 spring을 사용한다.
 - `matchedGeometryEffect`는 cross-scope 전체를 억지로 묶는 용도가 아니라, landing 또는 restore 같은 bounded transition에서만 제한적으로 검토한다.
-- month/year에서는 `selectedDate`를 즉시 바꾸지 않고 `activeDate`만 hover candidate로 유지한다.
+- root handoff에 쓰는 frame과 pointer는 모두 `global coordinates`로 정규화한다. local/global 좌표를 섞은 handoff는 금지한다.
+- month/year에서는 `selectedDate`를 commit 전까지 바꾸지 않고 `activeDate`만 hover candidate로 유지한다.
+- month/year hover 계산은 root ownership 이후에만 활성화된다.
 - 최종 확정은 `drop on touch up`만 허용한다.
 - `droppable`은 독립 top-level state가 아니라, current state + candidate 유효성에서 계산되는 파생 판정이다.
-- invalid drop, overflow, missing candidate는 clamp보다 `restore`를 우선한다.
+- `touch claim` pending은 `2 frame 이내의 매우 짧은 window`로 제한한다. 실패나 timeout이면 clamp보다 `restore-first policy`를 우선한다.
+- stale claim success / stale end / stale cancel은 현재 token과 맞지 않으면 무시한다.
 - overlay와 날짜 셀 hit-test는 모두 `global coordinates`를 기준으로 계산한다.
 
 ## DragSessionEngine
@@ -291,7 +303,10 @@ enum DragOutcome {
 - `viewModel.scope` 변경과 `pinch scope transition`을 감지해 엔진에 새 scope를 전달한다.
 - timeline frame과 month/year 날짜 셀 frame registry를 유지한다.
 - root overlay 렌더링에 필요한 `overlaySnapshot`을 제공한다.
+- `touch claim` handoff token과 claim pending window를 관리한다.
 - EventKit write는 최종 drop 확정 시에만 호출하고, 계산 로직은 여전히 엔진/geometry에 둔다.
+- `drag_start`, `root_claim_success`, `root_claim_timeout`, `restore_reason`, `claim_latency_ms`를 최소 관측성 이벤트로 남긴다.
+- 이 기록은 디버그와 회귀 재현용이다. drag hot path를 무거운 로그로 채우지 않는다.
 - session cleanup은 `CalendarDragCoordinator`와 root scope에서 commit/cancel/restore 이후 일관되게 수행한다.
 
 ## Swift / Python 공통 계약
```

## `docs/flow.md`

```diff
diff --git a/docs/flow.md b/docs/flow.md
index 505563c..9eca448 100644
--- a/docs/flow.md
+++ b/docs/flow.md
@@ -26,10 +26,12 @@
  ⚙️ 탭 → F8 (설정)
 
  drag session 중:
+  `bounded handoff`로 day source의 local preview lift 이후 explicit `touch claim`이 성공해야만 root `single overlay`로 전환
   pinch scope transition으로 day/year scope 전환 가능
   `CalendarDragCoordinator` session을 유지한 채 scope만 교체
   lift 이후 overlay는 root scope 위에서 계속 유지되는 `single overlay`
   scope 전환 중에도 같은 블록을 계속 조작한다고 느껴야 함
+  month/year hover 계산은 root `touch claim` 성공 이후에만 활성화
   각 날짜 셀 hover → `activeDate`만 갱신, `selectedDate`는 즉시 바뀌지 않음
   날짜 강조는 항상 하나의 `single active target`만 유지
   날짜 셀 판정은 global coordinates 기준 hit-test
@@ -90,6 +92,14 @@
   블록 본체 y축 드래그 → 같은 날 이동 (15분 스냅, 자동 스크롤)
   블록 본체 이동은 단일 root drag path로만 처리
   drag 시작 직후 `liftPreparing` 단계에서 블록이 붙어 있는 요소에서 떠다니는 조작 대상으로 바뀜
+  `bounded handoff`: drag 시작 직후에는 source 내부 local preview만 즉시 lift된다
+  root ownership은 explicit `touch claim` 성공 후에만 root `single overlay`로 전환된다
+  claim pending 동안에는 source placeholder를 켜지 않고, month/year `activeDate` hover도 시작하지 않는다
+  `source block -> placeholder` 전환이 root claim보다 먼저 일어나면 안 된다
+  local/global 좌표가 섞인 상태로 root handoff를 진행하면 안 된다
+  `captureTouch(near:)`의 동기 성공을 drag 시작 조건으로 두지 않는다. root recognizer가 첫 프레임에 아직 touch를 못 본 상태면 drag가 아예 시작되지 않을 수 있다
+  claim window는 `2 frame 이내의 매우 짧은 window`로 제한하고, 실패나 timeout이면 `restore-first policy`로 즉시 복원한다
+  stale claim success / stale end / stale cancel은 현재 token과 맞지 않으면 무시한다
   drag session 중 pinch scope transition으로 day/month/year scope 전환 가능
   drag session 중 원본 블록은 placeholder/ghost처럼 남고, 실제 이동 중 블록은 전역 `single overlay`로 유지
   overlay owner는 DayView가 아니라 root `CalendarDragCoordinator`
@@ -180,6 +190,7 @@
  drag session 중:
   pinch scope transition으로 month scope 전환 가능
   `CalendarDragCoordinator` session을 유지한 채 scope만 교체
+  month/year hover 계산은 root `touch claim` 성공 이후에만 활성화
   pointer가 날짜 셀 위에서 안정적으로 머물면 `activeDate`만 갱신
   overlay는 root scope 위의 `single overlay`로 유지되고, scope 교체만으로는 종료되지 않음
   year scope에서는 익명 `calendarPill`과 `single active target`만 보임
```

## `docs/prd.md`

```diff
diff --git a/docs/prd.md b/docs/prd.md
index fa5620e..1a4dba9 100644
--- a/docs/prd.md
+++ b/docs/prd.md
@@ -31,20 +31,34 @@ Apple Calendar 이벤트와 Apple Reminders를 하나의 미니멀 인터페이
 
 애니메이션은 미관이 아니라 상태 이해를 위한 피드백 수단이다. 사용자는 블록이 붙어 있는 요소에서 떠다니는 조작 대상으로 바뀌는 순간과, scope 전환 뒤에도 같은 객체를 계속 잡고 있다는 점을 즉시 이해해야 한다.
 
+cross-scope move의 시작은 `bounded handoff`다.
+
+- drag 시작 직후 source 내부 local preview는 즉시 lift된다.
+- root ownership은 explicit `touch claim` 성공 후에만 넘어간다.
+- `source block -> placeholder` 전환이 root claim보다 먼저 일어나면 안 된다. local preview와 root overlay가 동시에 active owner가 되면 안 된다.
+- root handoff는 `global coordinates`로 정규화된 frame과 pointer만 사용한다. local/global 좌표 혼용은 금지한다.
+- `captureTouch(near:)`의 동기 성공을 drag 시작 게이트로 두면 root recognizer가 아직 touch를 관측하지 못한 첫 프레임에서 drag가 시작조차 안 될 수 있다.
+
 | 기능 | 상세 |
 |------|------|
 | 꼭짓점 리사이즈 | 상단-우측(시작시간), 하단-좌측(종료시간) 핸들. 15분 단위 스냅. 최소 30분. 핸들 옆 tooltip으로 시간 실시간 표시 |
 | 블록 이동 (같은 날) | 블록 본체 y축 드래그. 15분 단위 스냅. 자동 스크롤 지원 |
-| 블록 이동 (날짜 간) | cross-day move도 별도 local fallback 없이 단일 `root drag path`로 처리한다. drag 시작 직후 lift 단계가 있고, 원본 블록은 placeholder/ghost처럼 남고 실제 이동 블록은 root `single overlay`로만 렌더링한다. |
-| 블록 이동 (scope 간) | `pinch scope transition`은 문서상의 제스처가 아니라 실제 구현 대상이다. drag session은 day → month/year 전환 중에도 유지되며, root `CalendarDragCoordinator`가 전역 overlay와 session lifetime을 소유한다. full card는 `timelineCard`로 남아 있다가 scope transition 시작 시점에 익명 `calendarPill`로 단순화된다. |
-| drag 피드백 | pointer 이동과 overlay 이동은 drag 중 거의 즉시 일치해야 한다. 연속 drag follow와 hover update는 빠르게 지나가야 하고, per-frame animation으로 손가락을 늦게 따라가게 만들지 않는다. |
-| drop 계산 | day timeline은 `dateCandidate`, `minuteCandidate`를 둘 다 갱신한다. month/year는 `selectedDate`를 유지하고 `activeDate`만 갱신하며 `minuteCandidate`는 drag session이 유지한다. 최종 drop은 `drop on touch up`으로만 끝나고 `dateCandidate + minuteCandidate + duration`으로 계산한다. 성공 후 `selectedDate`와 화면 scope는 결과 날짜의 day 기준으로 맞춘다. Swift와 Python이 동일한 규칙을 사용한다. |
+| 블록 이동 (날짜 간) | cross-day move도 별도 local fallback 없이 단일 `root drag path`로 처리한다. drag 시작 직후 local preview가 lift되고, explicit `touch claim` 성공 후에만 원본 블록이 placeholder/ghost로 남고 실제 이동 블록이 root `single overlay`로 넘어간다. claim pending 동안에는 placeholder를 켜지 않는다. |
+| 블록 이동 (scope 간) | `pinch scope transition`은 문서상의 제스처가 아니라 실제 구현 대상이다. drag session은 day → month/year 전환 중에도 유지되며, root `CalendarDragCoordinator`가 전역 overlay와 session lifetime을 소유한다. full card는 `timelineCard`로 남아 있다가 scope transition 시작 시점에 익명 `calendarPill`로 단순화된다. month/year hover 계산은 root ownership 이후에만 활성화된다. |
+| drag 피드백 | pointer 이동과 overlay 이동은 drag 중 거의 즉시 일치해야 한다. 연속 drag follow와 hover update는 빠르게 지나가야 하고, per-frame animation으로 손가락을 늦게 따라가게 만들지 않는다. `touch claim` pending은 `2 frame 이내의 매우 짧은 window`로만 허용한다. |
+| drop 계산 | day timeline은 `dateCandidate`, `minuteCandidate`를 둘 다 갱신한다. month/year는 `selectedDate`를 commit 전까지 유지하고 `activeDate`만 갱신하며 `minuteCandidate`는 drag session이 유지한다. 최종 drop은 `drop on touch up`으로만 끝나고 `dateCandidate + minuteCandidate + duration`으로 계산한다. 성공 후 `selectedDate`와 화면 scope는 결과 날짜의 day 기준으로 맞춘다. Swift와 Python이 동일한 규칙을 사용한다. |
 | 표현 단순화 | full card는 lift와 landing에서는 충분히 보이되, month/year 탐색 중에는 제목 텍스트와 핸들을 제거한 익명 capsule만 보여준다. month와 year 모두 `same pill length`를 유지해 같은 객체처럼 인지되게 한다. |
 | 강조 타이밍 | 강조가 필요한 구간은 `lift`, `scope transition 시작`, `landing`, `restore`다. 반대로 hover update와 drag follow는 눈에 띄지 않을 정도로 빠르게 지나가야 한다. |
-| 오류 처리 | invalid drop, overflow, hover 미확정, cancel은 clamp보다 `restore-first policy`를 우선한다. 성공 commit 시에만 편집 모드 종료. cancel / invalid drop / restore에서는 편집 모드를 강제로 종료하지 않는다. legacy `edge-hover` fallback은 제거 대상이다. |
+| 오류 처리 | invalid drop, overflow, hover 미확정, cancel, `touch claim` 실패/timeout은 clamp보다 `restore-first policy`를 우선한다. 성공 commit 시에만 편집 모드 종료. cancel / invalid drop / restore에서는 편집 모드를 강제로 종료하지 않는다. legacy `edge-hover` fallback은 제거 대상이다. |
 | Floating toolbar | [삭제 \| 복제]. 블록 아래 (공간 부족 시 위). `.ultraThinMaterial` + cornerRadius(12) |
 | 해제 | 빈 영역 탭. 편집 중 블록 탭 → toolbar만 닫힘. 다른 블록 long press → 전환 |
 
+### bounded handoff 관측성
+
+- 기록 대상: `drag_start`, `root_claim_success`, `root_claim_timeout`, `restore_reason`, `claim_latency_ms`
+- stale claim success / stale end / stale cancel은 현재 token과 맞지 않으면 무시한다.
+- 이 관측성은 디버그와 회귀 재현을 위한 것이다. hot path마다 무거운 로깅을 추가하는 용도가 아니다.
+
 ### Drag 실험기
 - `experiments/draglab/`에서 Python CLI 기반 drag 실험기를 운영한다.
 - 입력은 `sessions.json`, `events.json`, `expected.json` 세 파일을 사용한다.
```

## `docs/timeline-block-animation.md`

```diff
diff --git a/docs/timeline-block-animation.md b/docs/timeline-block-animation.md
index dc13b04..7adc4d4 100644
--- a/docs/timeline-block-animation.md
+++ b/docs/timeline-block-animation.md
@@ -19,6 +19,8 @@
 - `single overlay`: 실제 이동 중 블록 overlay는 항상 하나만 유지한다
 - `single active target`: month/year에서 강조되는 날짜 target도 항상 하나만 유지한다
 - `restore-first policy`: invalid drop은 억지 확정 대신 원위치 복원을 우선한다
+- `bounded handoff`: drag 시작 직후 local preview가 먼저 lift되고, root owner 전환은 explicit `touch claim` 이후에만 일어난다
+- `touch claim`: root recognizer가 현재 touch를 현재 session token으로 명시적으로 인수했다는 신호다
 
 ## 레퍼런스 영상 관찰
 
@@ -72,18 +74,37 @@
 - `restoring` → `editModeReady`: cancel / invalid drop / restore에서는 편집 모드를 종료하지 않는다
 - `committed` → `idle`: 저장과 함께 편집 모드 종료
 
+## bounded handoff
+
+기존 실패 경로:
+
+- `source block -> placeholder` 전환이 root claim보다 먼저 일어나면 local preview와 root overlay가 동시에 owner처럼 보여 split-brain이 된다.
+- local/global 좌표가 섞인 상태로 root handoff를 진행하면 overlay 첫 프레임 점프와 잘못된 hit-test가 같이 발생한다.
+- `captureTouch(near:)`의 동기 성공을 drag 시작 조건으로 두면 root recognizer가 아직 touch를 관측하지 못한 첫 프레임에서 drag가 아예 시작되지 않을 수 있다.
+
+계약:
+
+- drag 시작 직후 source 내부의 local preview는 즉시 lift된다.
+- root ownership은 explicit `touch claim` 성공 후에만 전환된다.
+- claim pending 동안에는 source placeholder, root overlay, month/year `activeDate` hover를 켜지 않는다.
+- claim window는 `2 frame 이내의 매우 짧은 window`로 유지한다. 실패나 timeout이면 `restore-first policy`로 즉시 원위치 복구한다.
+- stale claim success, stale end, stale cancel은 현재 token과 맞지 않으면 무시한다.
+
 ## 역할 분리
 
 원본과 overlay 역할:
 
 - lift 전: 원본 블록이 실제 조작 대상처럼 보인다.
-- lift 후: 원본 블록은 placeholder/ghost로 남고, 실제 이동 표현은 `single overlay`만 담당한다.
+- lift 직후 claim pending 동안에는 source 내부 local preview만 활성 owner다.
+- root claim 성공 후: 원본 블록은 placeholder/ghost로 남고, 실제 이동 표현은 `single overlay`만 담당한다.
 - month/year에서는 `single active target`만 강조한다. 여러 날짜를 동시에 강조하지 않는다.
+- local preview와 root overlay가 동시에 활성 owner가 되면 안 된다.
 
 날짜 역할:
 
-- `selectedDate`는 확정 화면 기준이다. hover만으로 즉시 바뀌지 않는다.
-- `activeDate`는 month/year에서 hover candidate만 표현한다.
+- `selectedDate`는 확정 화면 기준이다. commit 전까지 바뀌지 않는다.
+- `activeDate`는 month/year에서만 의미가 있는 hover candidate다.
+- month/year hover 계산은 root ownership 이후에만 활성화된다.
 - day timeline에서는 `minuteCandidate`를 유지하고, month/year에서는 `activeDate`만 갱신한다.
 
 drop 규칙:
@@ -120,6 +141,17 @@ drop 규칙:
 ## 구현 가드레일
 
 - cross-scope 전체 경로를 여러 overlay로 나누지 않는다.
+- `bounded handoff`는 local preview → explicit `touch claim` → root `single overlay` 순서를 지킨다.
 - `single overlay`와 `single active target` 원칙을 유지한다.
 - day 복귀 전까지 `selectedDate`를 섣불리 바꾸지 않는다.
 - invalid drop은 `restore-first policy`를 유지한다.
+
+## 관측성
+
+- `drag_start`
+- `root_claim_success`
+- `root_claim_timeout`
+- `restore_reason`
+- `claim_latency_ms`
+
+이 관측성은 디버그와 회귀 재현을 위한 최소 기록이다. hot path마다 무거운 로깅을 추가하는 용도가 아니다.
```
