# Phase 0: docs-bounded-handoff

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `docs/flow.md`
- `docs/prd.md`
- `docs/code-architecture.md`
- `docs/adr.md`
- `docs/testing.md`
- `docs/timeline-block-animation.md`
- `/tasks/8-drag-handoff/docs-diff.md` (Phase 0 완료 후 runner가 자동 생성한다. 이 phase에서는 직접 만들지 마라.)

그리고 현재 drag 구현과 직전 task의 산출물을 반드시 확인하라:

- `tasks/7-timeline-block-animation/index.json`
- `tasks/7-timeline-block-animation/phase0.md`
- `tasks/7-timeline-block-animation/phase1.md`
- `tasks/7-timeline-block-animation/phase2.md`
- `tasks/7-timeline-block-animation/phase3.md`
- `tasks/7-timeline-block-animation/phase4.md`
- `tic/DragSession/CalendarDragCoordinator.swift`
- `tic/DragSession/DragSessionEngine.swift`
- `tic/DragSession/DragSessionGeometry.swift`
- `tic/Views/ContentView.swift`
- `tic/Views/Components/EditableEventBlock.swift`
- `tic/Views/Components/TimelineView.swift`
- `tic/Views/Calendar/DayView.swift`
- `tic/Views/Components/DragSessionTouchCaptureBridge.swift`

## 작업 내용

이번 phase의 목적은 **drag ownership handoff 계약을 문서로 먼저 고정하는 것**이다. Swift 코드 수정은 하지 말고, 관련 문서만 업데이트하라.

아래 내용을 문서에 명시하라.

### 1. 문제 원인과 금지 경로

- 기존 실패 경로를 명확히 기록하라.
- `source block -> placeholder` 전환이 root claim보다 먼저 일어나면 안 된다.
- local/global 좌표가 섞인 상태로 root handoff를 진행하면 안 된다.
- `captureTouch(near:)`의 동기 성공을 drag 시작 조건으로 두면, root recognizer가 아직 touch를 관측하지 못한 첫 프레임에서 drag가 아예 시작되지 않을 수 있음을 명시하라.

### 2. bounded handoff 계약

- drag 시작 직후에는 local preview가 즉시 lift된다.
- root ownership은 explicit touch claim 성공 후에만 전환된다.
- claim pending 동안에는 source placeholder를 켜지 마라.
- claim timeout은 최대 2 frame 수준의 bounded window로 유지하라. 문서에는 시간값 하드코딩 대신 "2 frame 이내의 매우 짧은 window"로 기록하라.
- claim 실패나 timeout이면 restore-first policy로 즉시 원위치 복구한다.
- stale claim success / stale end / stale cancel 이벤트는 현재 token과 맞지 않으면 무시한다.

### 3. 상태와 날짜 계약

- `selectedDate`는 commit 전까지 바꾸지 않는다.
- `activeDate`는 hover candidate이며 month/year scope에서만 의미를 가진다.
- month/year hover 계산은 root ownership 이후에만 활성화된다.
- single overlay / single active target 계약을 다시 확인하고, local preview와 root overlay가 동시에 활성 owner가 되지 않도록 문서화하라.

### 4. 관측성 계약

- 최소 아래 이벤트를 기록 대상으로 문서화하라.
  - `drag_start`
  - `root_claim_success`
  - `root_claim_timeout`
  - `restore_reason`
  - `claim_latency_ms`
- 이 관측성은 디버그와 회귀 재현을 위한 것이며, hot path마다 무거운 로깅을 추가하는 용도가 아님을 명시하라.

### 5. 문서 반영 위치

최소 아래 문서를 실제로 갱신하라.

- `docs/adr.md`
- `docs/flow.md`
- `docs/code-architecture.md`
- `docs/prd.md`
- `docs/timeline-block-animation.md`

필요하면 `docs/testing.md`에도 이번 task에서 기대하는 테스트 원칙을 한 단락 보강해도 된다. 다만 테스트 전략 자체를 뒤집지는 마라.

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && rg -n "bounded handoff|touch claim|selectedDate|activeDate|restore-first|claim_latency_ms" docs/adr.md docs/flow.md docs/code-architecture.md docs/prd.md docs/timeline-block-animation.md
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/8-drag-handoff/index.json`의 phase 0 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- 이 phase에서는 Swift 소스 파일을 수정하지 마라.
- `docs-diff.md`는 직접 만들지 마라. runner가 Phase 0 완료 후 자동 생성한다.
- 이전 세션의 임시 해결책을 문서 계약으로 승격시키지 마라. 이번 phase에서는 "왜 동기 캡처 게이트가 deadlock을 만든다"를 명확히 기록하는 것이 핵심이다.
