# Phase 2: pending-animation-continuity

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `docs/flow.md`
- `docs/prd.md`
- `docs/code-architecture.md`
- `docs/adr.md`
- `docs/testing.md`
- `docs/timeline-block-animation.md`
- `/tasks/10-pending-touch-continuity/docs-diff.md`

그리고 이전 phase의 작업물과 현재 관련 코드를 반드시 확인하라:

- `tasks/10-pending-touch-continuity/phase0.md`
- `tasks/10-pending-touch-continuity/phase1.md`
- `tic/DragSession/CalendarDragCoordinator.swift`
- `tic/DragSession/DragOverlayPresentation.swift`
- `tic/Views/ContentView.swift`
- `tic/Views/Components/TimelineView.swift`
- `tic/Views/Components/EditableEventBlock.swift`
- `ticTests/CalendarDragCoordinatorTests.swift`
- `ticTests/DragOverlayPresentationTests.swift`

이전 phase에서 복구한 tracking relay 위에서, 이번 phase는 animation contract만 정리하라.

## 작업 내용

이번 phase의 목적은 **`claim 후 morph` 정책에 맞춰 pending non-day의 시각 연속성을 복구하는 것**이다. `tracking continuity`는 이미 살아 있다고 가정하고, animation/presentation contract를 정리하라.

### 1. pending non-day presentation 유지

아래 정책을 구현하라.

- `rootClaimPending + non-day`에서는 overlay가 full `timelineCard` holding 상태를 유지한다.
- move를 따라가더라도 claim 성공 전에는 `calendarPill`로 바꾸지 않는다.
- 이 상태에서 inline source block, local preview, root overlay가 split-brain처럼 동시에 활성 owner로 보이지 않게 유지하라.

### 2. claim 후 morph 경로 복구

아래 전환을 구현하라.

- pending non-day 상태에서 `rootClaimSuccess`가 들어오면 그 시점에만 `timelineCard -> calendarPill` morph를 시작한다.
- claim 성공 뒤에만 month/year hover와 pill frame 이동이 열린다.
- month/year 내부 follow는 손가락을 늦게 따라가게 하지 말고, morph만 짧게 보여 주되 follow 자체는 즉각적으로 유지하라.

### 3. restore / landing 경로 점검

- pending non-day에서 cancel 또는 touch up restore 시 continuity overlay가 부자연스럽게 사라지지 않게 하라.
- claim 후 pill 상태에서 restore/landing으로 들어가는 기존 경로도 깨뜨리지 마라.

### 4. 테스트를 같은 phase에서 바로 추가

최소 아래를 검증하라.

- pending non-day에서는 `overlayPresentation.style == .timelineCard`를 유지한다.
- claim 성공 전에는 pill morph가 시작되지 않는다.
- claim 성공 후에만 `calendarPill` style과 hover 경로가 열린다.
- restore 경로가 animation 회귀 없이 끝난다.

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodegen generate && xcodebuild test -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' -only-testing:ticTests/CalendarDragCoordinatorTests CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
cd /Users/leesm/work/side/tic && xcodebuild test -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/10-pending-touch-continuity/index.json`의 phase 2 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- `claim 후 morph` 정책을 어기지 마라.
- pill morph를 위해 follow 자체를 느리게 만들지 마라.
- hover/placeholder/global drop ownership을 claim 전에 열지 마라.
- 이전 task에서 복구한 continuity overlay 자체를 다시 제거하지 마라.
