# Phase 0: docs-pending-continuity

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `docs/flow.md`
- `docs/prd.md`
- `docs/code-architecture.md`
- `docs/adr.md`
- `docs/testing.md`
- `docs/timeline-block-animation.md`
- `/tasks/9-scope-transition-continuity/docs-diff.md` (Phase 0 완료 후 runner가 자동 생성한다. 이 phase에서는 직접 만들지 마라.)

그리고 직전 drag 관련 task와 현재 구현을 반드시 확인하라:

- `tasks/7-timeline-block-animation/index.json`
- `tasks/7-timeline-block-animation/phase0.md`
- `tasks/7-timeline-block-animation/phase1.md`
- `tasks/7-timeline-block-animation/phase2.md`
- `tasks/7-timeline-block-animation/phase3.md`
- `tasks/7-timeline-block-animation/phase4.md`
- `tasks/8-drag-handoff/index.json`
- `tasks/8-drag-handoff/phase0.md`
- `tasks/8-drag-handoff/phase1.md`
- `tasks/8-drag-handoff/phase2.md`
- `tasks/8-drag-handoff/phase3.md`
- `tasks/8-drag-handoff/phase4.md`
- `tic/DragSession/CalendarDragCoordinator.swift`
- `tic/DragSession/DragSessionTypes.swift`
- `tic/Views/ContentView.swift`
- `tic/Views/Components/EditableEventBlock.swift`
- `tic/Views/Components/TimelineView.swift`
- `tic/Views/Components/DragSessionTouchCaptureBridge.swift`

## 작업 내용

이번 phase의 목적은 **`rootClaimPending` 상태의 scope transition continuity 계약을 문서로 먼저 고정하는 것**이다. Swift 소스는 수정하지 말고 문서만 업데이트하라.

아래 내용을 문서에 반영하라.

### 1. 회귀 원인과 계약 분리 명시

- 이번 회귀의 원인이 `ownership`과 `presentation continuity`를 같이 잠근 데 있음을 기록하라.
- `rootClaimPending` 동안 `hover`, `placeholder`, `global drop ownership`을 막는 것은 맞지만, scope transition 중 객체 연속성 표현까지 끄면 안 된다는 점을 명시하라.
- `day` 내부 local preview와 `non-day` continuity overlay는 같은 책임이 아니라는 점을 적어라.

### 2. pending scope transition continuity 계약 추가

- `rootClaimPending` 상태에서 `day -> month/year`로 전환되면 블록은 사라지지 않고 `holding card`로 유지된다고 명시하라.
- 이 `holding card`는 마지막으로 확인된 day overlay frame에 잠깐 고정된다고 적어라.
- claim 성공 전에는 `calendarPill`로 바꾸지 않는다.
- claim 성공 전에는 month/year `activeDate` hover를 켜지 않는다.
- claim 성공 전에는 source placeholder를 켜지 않는다.
- claim 성공 전에는 global drag/drop ownership을 root로 승격하지 않는다.
- `pending + non-day` 상태에서 touch up 하면 commit이 아니라 `restore-first policy`로 복귀한다고 명시하라.

### 3. 문서 반영 위치

최소 아래 문서를 실제로 갱신하라.

- `docs/timeline-block-animation.md`
- `docs/flow.md`
- `docs/adr.md`
- `docs/code-architecture.md`

필요하면 `docs/prd.md`에도 사용성 계약을 한 단락 보강해도 된다. 다만 기존 drag 문맥을 뒤집지는 마라.

### 4. ADR 보강

기존 `bounded handoff` ADR 또는 인접 ADR에 아래를 명시하라.

- claim pending 중에도 scope transition continuity는 유지될 수 있다.
- 다만 이것은 `render continuity`이지 `ownership transfer`가 아니다.
- `render visibility`와 `interaction ownership`은 별도 정책으로 분리한다.

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && rg -n "rootClaimPending|holding card|presentation continuity|render visibility|interaction ownership|restore-first policy|calendarPill|activeDate|placeholder|global drop ownership" docs/flow.md docs/prd.md docs/code-architecture.md docs/adr.md docs/timeline-block-animation.md
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/9-scope-transition-continuity/index.json`의 phase 0 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- 이 phase에서는 Swift 소스, 테스트, `project.yml`을 수정하지 마라.
- `docs-diff.md`는 직접 만들지 마라. runner가 Phase 0 완료 후 자동 생성한다.
- `claim pending인데도 보인다`를 `root ownership 획득`으로 잘못 문서화하지 마라.
- 이전 freeze 이슈를 만든 조기 ownership 전환을 정당화하지 마라.
