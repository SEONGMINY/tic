# Phase 4: observability-regression

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
- `tasks/8-drag-handoff/phase2.md`
- `tasks/8-drag-handoff/phase3.md`
- `tic/DragSession/CalendarDragCoordinator.swift`
- `tic/DragSession/DragOverlayPresentation.swift`
- `tic/Views/ContentView.swift`
- `tic/Views/Calendar/DayView.swift`
- `tic/Views/Components/TimelineView.swift`
- `tic/Views/Components/EditableEventBlock.swift`
- `tic/Views/Components/DragSessionTouchCaptureBridge.swift`
- `ticTests/CalendarDragCoordinatorTests.swift`
- `ticTests/DragOverlayPresentationTests.swift`

이전 phase에서 만든 bounded handoff 흐름이 회귀 없이 유지되도록 관측성과 테스트를 보강하라.

## 작업 내용

이번 phase의 목적은 **회귀 재현이 가능한 lightweight observability와 핵심 regression test를 추가하는 것**이다.

### 1. 경량 observability 추가

아래 이벤트를 저비용으로 추적할 수 있는 구조를 추가하라.

- `drag_start`
- `root_claim_success`
- `root_claim_timeout`
- `restore_reason`
- `claim_latency_ms`

구현 방식은 debug logger, trace sink, in-memory recorder 중 무엇이든 가능하다. 다만 아래 규칙을 지켜라.

- 기본값은 no-op에 가깝게 유지하라.
- pointer follow hot path마다 문자열 조합/무거운 로그를 하지 마라.
- 테스트에서 검증 가능한 주입 지점을 남겨라.

### 2. 회귀 테스트 추가

최소 아래 시나리오를 자동화하라.

- root recognizer가 첫 프레임에서 claim을 놓쳐도 local preview deadlock이 발생하지 않는다.
- claim timeout 후 세션이 restore되고 floating overlay가 남지 않는다.
- month/year round-trip 뒤 touch up 시 종료가 한 번만 처리된다.
- stale claim success가 cancel 이후 세션을 다시 살리지 않는다.
- presentation phase가 pointer follow 중 불필요하게 churn하지 않는다.

필요하면 테스트 대상을 더 순수한 helper로 분리하라. mock-heavy UI test 대신 unit-level deterministic test를 우선하라.

### 3. 성능 가드레일 점검

코드에서 아래를 확인하고 필요하면 정리하라.

- pending claim을 위해 per-frame allocation 또는 불필요한 animation restart가 생기지 않는지
- pointer update path가 기존보다 더 많은 geometry recomputation을 강제하지 않는지
- debug instrumentation이 release 동작 경로를 오염시키지 않는지

성능을 이유로 구조를 다시 복잡하게 만들지 마라. 단순하고 검증 가능한 경로가 우선이다.

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodegen generate && xcodebuild test -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/8-drag-handoff/index.json`의 phase 4 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- analytics SDK 같은 외부 의존성을 추가하지 마라.
- UI test로 문제를 덮으려 하지 마라. 이 task의 핵심은 state machine과 handoff contract의 회귀 방지다.
- 단순히 로그만 추가하고 테스트를 빼먹지 마라.
