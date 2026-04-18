# Phase 0: docs-pending-tracking

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `docs/flow.md`
- `docs/prd.md`
- `docs/code-architecture.md`
- `docs/adr.md`
- `docs/testing.md`
- `docs/timeline-block-animation.md`
- `/tasks/10-pending-touch-continuity/docs-diff.md` (Phase 0 완료 후 runner가 자동 생성한다. 이 phase에서는 직접 만들지 마라.)

그리고 직전 drag 관련 task와 현재 구현을 반드시 확인하라:

- `tasks/8-drag-handoff/index.json`
- `tasks/8-drag-handoff/phase0.md`
- `tasks/8-drag-handoff/phase1.md`
- `tasks/8-drag-handoff/phase2.md`
- `tasks/8-drag-handoff/phase3.md`
- `tasks/8-drag-handoff/phase4.md`
- `tasks/9-scope-transition-continuity/index.json`
- `tasks/9-scope-transition-continuity/phase0.md`
- `tasks/9-scope-transition-continuity/phase1.md`
- `tasks/9-scope-transition-continuity/phase2.md`
- `tic/DragSession/CalendarDragCoordinator.swift`
- `tic/Views/ContentView.swift`
- `tic/Views/Components/EditableEventBlock.swift`
- `tic/Views/Components/TimelineView.swift`
- `tic/Views/Components/DragSessionTouchCaptureBridge.swift`

## 작업 내용

이번 phase의 목적은 **`rootClaimPending + non-day` 경로에서 `ownership`, `touch tracking`, `presentation`을 분리하는 계약을 문서로 먼저 고정하는 것**이다. Swift 소스는 수정하지 말고 문서만 업데이트하라.

아래 내용을 문서에 반영하라.

### 1. 회귀 원인 명시

- 이번 회귀의 핵심 원인이 `render continuity`만 복구하고 `touch tracking continuity`는 복구하지 않은 데 있음을 적어라.
- `rootClaimPending` 상태에서 블록이 보이기만 하고 더 이상 움직이지 않는 것은 `tracking relay`가 비어 있기 때문이라고 기록하라.
- `claim 후 morph` 정책을 명시하라. claim 성공 전에는 full card를 유지하고, claim 성공 뒤에만 `calendarPill` morph를 시작한다고 적어라.

### 2. pending non-day tracking 계약 추가

- `rootClaimPending` 상태에서 `day -> month/year`로 전환되면 continuity overlay는 손가락을 계속 따라가야 한다고 명시하라.
- 이 follow는 `tracking continuity`이지 `root ownership`이 아니라고 적어라.
- claim 성공 전에는 여전히 month/year `activeDate` hover, source placeholder, global drag/drop ownership을 열지 않는다고 명시하라.
- `pending + non-day` 상태의 touch up은 commit이 아니라 `restore-first policy`라고 다시 적어라.

### 3. 문서 반영 위치

최소 아래 문서를 실제로 갱신하라.

- `docs/flow.md`
- `docs/code-architecture.md`
- `docs/adr.md`
- `docs/timeline-block-animation.md`

필요하면 `docs/prd.md`에도 한 단락 보강해도 된다. 다만 기존 bounded handoff 계약을 뒤집지 마라.

### 4. 아키텍처 분리 명시

문서에서 아래 세 축을 분리해 적어라.

- `interaction ownership`
- `touch tracking relay`
- `presentation continuity`

그리고 `rootClaimPending + non-day`는 아래 규칙을 따른다고 명시하라.

- tracking relay는 열린다
- ownership은 여전히 local preview 쪽 계약을 유지한다
- presentation은 full `timelineCard` holding 상태를 유지한다
- `calendarPill` morph는 claim 성공 뒤에만 시작된다

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && rg -n "tracking continuity|touch tracking relay|claim 후 morph|calendarPill|render continuity|interaction ownership|restore-first policy|rootClaimPending|holding|activeDate|placeholder|global drag|global drop ownership" docs/flow.md docs/prd.md docs/code-architecture.md docs/adr.md docs/timeline-block-animation.md
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/10-pending-touch-continuity/index.json`의 phase 0 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- 이 phase에서는 Swift 소스, 테스트, `project.yml`을 수정하지 마라.
- `docs-diff.md`는 직접 만들지 마라. runner가 Phase 0 완료 후 자동 생성한다.
- `tracking relay`를 `root ownership 획득`으로 잘못 문서화하지 마라.
- claim 전 조기 hover나 placeholder 허용을 정당화하지 마라.
