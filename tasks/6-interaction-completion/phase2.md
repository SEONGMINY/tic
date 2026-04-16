# Phase 2: root-path-cleanup

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `docs/flow.md`
- `docs/prd.md`
- `docs/code-architecture.md`
- `docs/adr.md`
- `docs/testing.md`
- `/tasks/6-interaction-completion/docs-diff.md`

그리고 이전 phase의 작업물을 반드시 확인하라:

- `tasks/6-interaction-completion/phase0.md`
- `tasks/6-interaction-completion/phase1.md`
- `tic/Views/ContentView.swift`
- `tic/Views/Calendar/DayView.swift`
- `tic/Views/Components/TimelineView.swift`
- `tic/Views/Components/EditableEventBlock.swift`
- `tic/DragSession/CalendarDragCoordinator.swift`
- `ticTests/`

## 작업 내용

이번 phase의 목적은 **legacy edge-hover 경로를 제거하고 root drag path만 남기는 것**이다.

### 1. `DayView` legacy edge-hover 제거

아래 상태와 로직을 제거하라.

- `edgeHoverDirection`
- `edgeHoverItemId`
- `edgeHoverTimer`
- `edgeHoverProgress`
- `startEdgeHover`
- `cancelEdgeHover`
- `performEdgeTransition`
- `edgeHoverIndicator`

이 제거 후에도 cross-scope drag는 root overlay + scope transition 경로로 동작해야 한다.

### 2. `EditableEventBlock` / `TimelineView` 정리

아래를 정리하라.

- `onEdgeHover`, `onEdgeClear` 같은 legacy callback 제거
- move gesture는 pointer forwarding만 수행하고 local cross-day completion 로직을 더 이상 갖지 않는다
- drop owner는 root `CalendarDragCoordinator` 또는 local same-day drop path 둘 중 하나로만 남아야 한다

### 3. root/local ownership 경계 고정

아래 규칙을 코드에 명확히 반영하라.

- same-day timeline drop은 local path로 끝날 수 있다
- scope가 month/year로 넘어간 순간부터는 root path만 drop owner다
- global drop success/failure가 중복 commit을 만들면 안 된다

필요하면 coordinator에 작은 순수 helper를 추가하고 테스트하라.

### 4. 테스트 추가

최소 아래 시나리오를 XCTest로 검증하라.

- root owner로 전환된 뒤 local drop path는 commit하지 않는다
- same-day drop은 기존 day move commit이 유지된다
- placeholder visible 상태가 session 종료 후 정상 해제된다

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodegen generate && xcodebuild test -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' -only-testing:ticTests CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/6-interaction-completion/index.json`의 phase 2 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- phase 2에서는 root path 정리만 하라. scene phase cancellation까지 과하게 확장하지 마라.
- 제거한 legacy 코드 때문에 동일 날짜 이동 UX가 깨지면 안 된다.
- 기존 테스트를 깨뜨리지 마라.
