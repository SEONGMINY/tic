# Phase 1: coordinator-pending-overlay

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `docs/flow.md`
- `docs/prd.md`
- `docs/code-architecture.md`
- `docs/adr.md`
- `docs/testing.md`
- `docs/timeline-block-animation.md`
- `/tasks/9-scope-transition-continuity/docs-diff.md`

그리고 이전 phase의 작업물과 현재 관련 코드를 반드시 확인하라:

- `tasks/9-scope-transition-continuity/phase0.md`
- `docs/flow.md`
- `docs/prd.md`
- `docs/code-architecture.md`
- `docs/adr.md`
- `docs/timeline-block-animation.md`
- `tic/DragSession/CalendarDragCoordinator.swift`
- `tic/DragSession/DragSessionTypes.swift`
- `tic/DragSession/DragOverlayPresentation.swift`
- `tic/DragSession/DragSessionEngine.swift`
- `tic/Views/ContentView.swift`
- `ticTests/CalendarDragCoordinatorTests.swift`
- `ticTests/DragOverlayPresentationTests.swift`

이전 task의 bounded handoff 계약을 유지한 채, pending scope transition continuity만 coordinator 계층에서 복구하라.

## 작업 내용

이번 phase의 목적은 **coordinator가 `render continuity`와 `interaction ownership`을 분리해서 `rootClaimPending + non-day` 경로를 정확히 표현하도록 만드는 것**이다. SwiftUI view wiring 전체를 바꾸는 것이 아니라, coordinator와 순수 테스트를 먼저 고정하라.

### 1. pending non-day continuity 상태 반영

`CalendarDragCoordinator`와 인접 타입을 정리해 아래를 만족하라.

- `rootClaimPending` 상태에서 `visibleScope != .day` 이면 continuity overlay가 유지될 수 있어야 한다.
- 이 visibility는 root ownership 획득과 동일한 뜻이 아니어야 한다.
- claim pending 동안 `dropOwner`, `shouldHandleDragGlobally`, `allowsCalendarHover`, `showsPlaceholder`는 계속 보수적으로 유지하라.
- `isRootOverlayVisible` 또는 동등 책임의 계산은 `render continuity`까지 표현할 수 있게 보강하라.

### 2. holding card 정책 고정

아래 정책을 코드에 반영하라.

- `pending + non-day`에서는 `holding` phase의 `timelineCard`를 유지한다.
- 위치는 마지막 day overlay frame에 고정한다.
- claim 성공 전에는 `calendarPill`로 전환하지 않는다.
- claim 성공 후에만 기존 `holding -> floating calendarPill` 경로를 탄다.

### 3. pending touch up은 restore

아래 종료 규칙을 coordinator 수준에서 고정하라.

- `pending + day`에서는 기존 same-day local drop 경로를 유지한다.
- `pending + non-day`에서 touch up 하면 commit을 만들지 말고 restore 경로로 정리하라.
- stale token / late success / late end 처리 규칙은 기존 handoff 계약을 깨뜨리지 마라.

### 4. 순수 테스트를 이 phase에서 바로 추가

`docs/testing.md` 원칙대로 coordinator 테스트를 같은 phase에서 바로 보강하라.

최소 아래를 검증하라.

- pending 상태에서 month 전환 시 overlay는 보이지만 placeholder는 보이지 않는다.
- pending 상태에서 month/year `activeDate`는 여전히 nil이다.
- pending 상태에서 `shouldHandleDragGlobally`는 false다.
- pending non-day 상태에서 touch up 하면 commit이 아니라 restore로 끝난다.
- claim 성공 후에만 `holding card -> calendarPill` 경로가 활성화된다.

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodegen generate && xcodebuild test -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' -only-testing:ticTests/CalendarDragCoordinatorTests CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/9-scope-transition-continuity/index.json`의 phase 1 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- `rootClaimPending`을 새로운 owner 상태처럼 과도하게 퍼뜨리지 마라. ownership contract는 기존 handoff 타입의 source of truth를 유지하라.
- coordinator가 UIKit recognizer를 직접 알게 만들지 마라.
- `pending + non-day` 경로를 위해 hover나 drop 권한을 먼저 열지 마라.
- local same-day drop 경로를 깨뜨리지 마라.
