# Phase 0: docs-animation-contract

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `docs/flow.md`
- `docs/prd.md`
- `docs/code-architecture.md`
- `docs/adr.md`
- `docs/testing.md`

그리고 바로 이전 drag 관련 task의 작업물을 반드시 확인하라:

- `tasks/5-swift-drag-port/phase0.md`
- `tasks/5-swift-drag-port/phase1.md`
- `tasks/5-swift-drag-port/phase2.md`
- `tasks/5-swift-drag-port/phase3.md`
- `tasks/5-swift-drag-port/phase4.md`
- `tasks/6-interaction-completion/phase0.md`
- `tasks/6-interaction-completion/phase1.md`
- `tasks/6-interaction-completion/phase2.md`
- `tasks/6-interaction-completion/phase3.md`

아래 레퍼런스 자산과 현재 구현 파일들도 읽어 실제 상태를 확인하라:

- `videos/animation.json`
- `videos/block-animation.MP4`
- `tic/Views/ContentView.swift`
- `tic/Views/Calendar/DayView.swift`
- `tic/Views/Calendar/MonthView.swift`
- `tic/Views/Calendar/YearView.swift`
- `tic/Views/Components/TimelineView.swift`
- `tic/Views/Components/EditableEventBlock.swift`
- `tic/Views/Components/DragSessionOverlayBlock.swift`
- `tic/DragSession/CalendarDragCoordinator.swift`
- `tic/DragSession/DragSessionEngine.swift`
- `tic/ViewModels/CalendarScopeTransition.swift`

필요하면 `ffprobe` 또는 프레임 추출로 영상을 직접 확인하라. `animation.json`의 핵심 timecode는 약 60fps 기준으로 읽어야 한다.

## 작업 내용

이번 phase의 목적은 **타임라인 블록 애니메이션 계약을 문서에서 먼저 고정**하는 것이다. Swift 소스 구현은 하지 말고 문서만 수정하라.

### 1. 전용 설계 문서 추가

새 문서 `docs/timeline-block-animation.md`를 만들고 아래를 반드시 포함하라.

- 레퍼런스 영상 관찰 요약
- `animation.json` timecode 해석
- `00:00:02:17` 편집 가능 상태 진입
- `00:00:03:35` 년/월 전환 입력 발생
- `00:00:04:15` scope transition 시작
- `00:00:04:16` ~ `00:00:04:26` full card가 anonymous capsule로 압축되는 핵심 구간
- 이 영상은 약 60fps 소스이며 timecode를 30fps로 오해하지 않는다는 점
- 상태 머신 정의
- 최소 상태는 `idle`, `editModeReady`, `liftPreparing`, `floatingTimeline`, `transitionHoldingCard`, `floatingCalendarPill`, `returningToTimeline`, `dropping`, `restoring`, `committed`
- `selectedDate`와 `activeDate`의 역할 분리
- drop은 `touch up` 한 번으로만 끝난다는 규칙
- 성공 commit 시에만 편집 모드를 종료한다는 규칙
- cancel / invalid drop / restore에서는 편집 모드를 강제로 종료하지 않는다는 규칙
- overlay는 항상 하나만 유지하고, calendar target highlight도 항상 하나만 유지한다는 규칙
- month와 year에서 같은 pill 길이를 유지한다는 규칙
- capsule은 익명 pill이다. 제목 텍스트, resize handle, 툴바를 넣지 마라.

### 2. `docs/flow.md` 업데이트

아래 흐름을 F2/F3/F7 또는 drag 관련 흐름에 반영하라.

- day 편집 모드에서 블록이 `붙어 있는 요소`에서 `떠다니는 조작 대상`으로 바뀌는 lift 단계가 존재한다.
- lift 직후에는 원본 블록과 overlay 역할이 분리된다.
- scope 전환 중에도 사용자는 같은 블록을 계속 조작한다고 느껴야 한다.
- month/year에서는 `selectedDate`가 즉시 바뀌지 않고 `activeDate`만 hover candidate로 바뀐다.
- valid drop을 `touch up` 하면 결과 날짜 기준 `day` scope로 복귀하고 그 뒤 commit한다.
- invalid drop / cancel은 `restore-first policy`로 원위치 복원한다.

### 3. `docs/prd.md` 업데이트

타임라인 편집 UX와 cross-scope drag UX를 아래 기준으로 보강하라.

- 애니메이션은 미관이 아니라 상태 이해를 위한 피드백 수단이다.
- full card는 lift와 landing에서는 충분히 보이되, month/year 탐색 중에는 capsule로 단순화한다.
- pointer 이동과 overlay 이동은 drag 중에 거의 즉시 일치해야 한다.
- 강조가 필요한 구간은 `lift`, `scope transition 시작`, `landing`, `restore`다.
- 빠르게 지나가야 하는 구간은 연속 drag follow와 hover update다.
- pill 길이는 고정하되 위치만 바뀌어야 사용자가 `같은 객체`라고 인지하기 쉽다는 점을 명시하라.

### 4. `docs/code-architecture.md` 업데이트

아래 구조를 문서에 명확히 반영하라.

- gesture state와 display state를 분리한다.
- `CalendarDragCoordinator` 또는 인접 순수 helper가 presentation phase를 계산한다.
- `DragSessionOverlayBlock`은 raw gesture 분기 대신 presentation model을 입력받는다.
- drag 중 실시간 추적은 per-frame animation이 아니라 직접 position 업데이트로 처리한다.
- 상태 전환 애니메이션만 명시적으로 `withAnimation` 또는 spring을 사용한다.
- `matchedGeometryEffect`는 cross-scope 전체를 억지로 묶는 용도가 아니라, landing 또는 restore 같은 bounded transition에만 제한적으로 검토한다.

### 5. `docs/adr.md` 업데이트

기존 마지막 번호 다음으로 새 ADR을 추가하라.

- `ADR-030`: cross-scope 동안 타임블록은 하나의 session identity를 유지하고 presentation만 `timelineCard`와 `calendarPill` 사이에서 바꾼다.

아래 용어를 그대로 사용하라.

- `timelineCard`
- `calendarPill`
- `selectedDate`
- `activeDate`
- `drop on touch up`
- `single overlay`
- `single active target`
- `restore-first policy`

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && rg -n "timelineCard|calendarPill|selectedDate|activeDate|drop on touch up|single overlay|single active target|restore-first policy|same pill length|60fps|ADR-030|commit.*편집 모드 종료|cancel.*편집 모드" docs/flow.md docs/prd.md docs/code-architecture.md docs/adr.md docs/timeline-block-animation.md
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/7-timeline-block-animation/index.json`의 phase 0 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- 이 phase에서는 문서만 수정하라. Swift 소스, `project.yml`, 테스트 파일은 건드리지 마라.
- `docs-diff.md`는 runner가 생성한다. 직접 만들지 마라.
- 영상 해석이 불확실한 부분은 추정이라고 문서에 명시하라.
- 30fps 전제로 timecode를 해석하지 마라.
- 기존 drag session 계약과 충돌시키지 마라.
