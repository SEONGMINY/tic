# Phase 2: coordinator-handoff-state

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `docs/flow.md`
- `docs/prd.md`
- `docs/code-architecture.md`
- `docs/adr.md`
- `docs/testing.md`
- `docs/timeline-block-animation.md`
- `/tasks/8-drag-handoff/docs-diff.md`

그리고 이전 phase의 작업물을 반드시 확인하라:

- `tasks/8-drag-handoff/phase0.md`
- `tasks/8-drag-handoff/phase1.md`
- `tic/DragSession/CalendarDragCoordinator.swift`
- `tic/DragSession/DragSessionEngine.swift`
- `tic/DragSession/DragSessionGeometry.swift`
- `tic/DragSession/DragSessionTypes.swift`
- Phase 1에서 추가한 touch claim 관련 파일 전부
- `ticTests/CalendarDragCoordinatorTests.swift`

이전 phase에서 만든 순수 touch claim 규칙을 `CalendarDragCoordinator`의 실제 상태기계에 반영하라.

## 작업 내용

이번 phase의 목적은 **drag ownership을 coordinator 내부의 bounded handoff state machine으로 일원화하는 것**이다. 아직 SwiftUI view wiring 전체를 바꾸는 것이 아니라, coordinator가 정확한 상태 전이를 표현하도록 만드는 데 집중하라.

### 1. coordinator owner state 정리

`CalendarDragCoordinator`가 아래 개념을 직접 소유하도록 정리하라.

- local preview active
- root claim pending
- root claim acquired
- restoring / landing / idle

타입명은 달라도 되지만, `dropOwner`의 단순 2값만으로는 설명되지 않는 pending 상태가 분명히 표현되어야 한다.

### 2. explicit API 추가

다음 phase에서 View 계층이 붙을 수 있도록, coordinator에 명시적 handoff API를 추가하라. 이름은 달라도 되지만 아래 역할은 있어야 한다.

- local preview drag 시작
- root claim 요청 시작
- root claim 성공 반영
- root claim 실패 또는 timeout 반영
- stale token/end/cancel 무시
- 현재 세션의 token/owner 조회

핵심 규칙:

- local preview는 즉시 시작될 수 있다.
- placeholder와 root overlay owner는 claim success 이후에만 활성화된다.
- claim pending 중에는 month/year hover를 본격 활성화하지 마라.
- `selectedDate`는 commit 전까지 바꾸지 마라.
- restore-first policy를 유지하라.

### 3. presentation 연동 보강

기존 `overlayPresentation`과 충돌하지 않게, claim pending 중에 어떤 visual phase가 보여야 하는지 coordinator에서 일관되게 결정하라.

- local preview 직후에는 `liftPreparing` 또는 이에 준하는 준비 phase가 필요하다.
- root claim 성공 전에는 "root overlay가 이미 모든 것을 소유하는 것처럼" 상태를 노출하지 마라.
- pending에서 timeout/fail로 떨어질 때 restore animation 경로가 끊기지 않게 하라.

### 4. coordinator 테스트 확장

`ticTests/CalendarDragCoordinatorTests.swift`를 확장해 최소 아래를 검증하라.

- local preview 시작 시 즉시 drag deadlock 없이 pending 상태가 만들어진다.
- claim success 후에만 root owner / placeholder가 켜진다.
- claim timeout이면 세션이 restore 경로로 정리된다.
- stale token success는 현재 세션을 오염시키지 않는다.
- month/year hover는 claim success 이전에는 활성화되지 않는다.

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodegen generate && xcodebuild test -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' -only-testing:ticTests/CalendarDragCoordinatorTests CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/8-drag-handoff/index.json`의 phase 2 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- coordinator가 UIKit recognizer를 직접 알게 만들지 마라.
- 기존 `DragSessionEngine`의 시간 계산/geometry 책임을 coordinator가 중복 구현하지 마라.
- pending 상태를 boolean 몇 개로 흩뿌리지 마라. 다음 phase에서 View 계층이 읽을 수 있는 단일한 source of truth가 필요하다.
