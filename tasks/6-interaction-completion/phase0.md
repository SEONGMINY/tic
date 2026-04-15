# Phase 0: docs-alignment

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `docs/flow.md`
- `docs/prd.md`
- `docs/code-architecture.md`
- `docs/adr.md`
- `docs/testing.md`

그리고 이전 task의 관련 작업물을 반드시 확인하라:

- `tasks/5-swift-drag-port/phase0.md`
- `tasks/5-swift-drag-port/phase1.md`
- `tasks/5-swift-drag-port/phase2.md`
- `tasks/5-swift-drag-port/phase3.md`
- `tasks/5-swift-drag-port/phase4.md`

아래 현재 구현 파일들도 읽어 실제 코드 상태를 확인하라:

- `tic/Views/ContentView.swift`
- `tic/Views/Calendar/DayView.swift`
- `tic/Views/Calendar/MonthView.swift`
- `tic/Views/Calendar/YearView.swift`
- `tic/Views/Components/TimelineView.swift`
- `tic/Views/Components/EditableEventBlock.swift`
- `tic/DragSession/CalendarDragCoordinator.swift`
- `tic/DragSession/DragSessionEngine.swift`

## 작업 내용

이번 phase의 목적은 **interaction-completion 기준을 문서에서 먼저 고정**하는 것이다. Swift 소스 구현은 하지 말고 문서만 수정하라.

### 1. `docs/flow.md` 업데이트

아래 내용을 F2/F3/F7 흐름에 반영하라.

- normal 상태와 drag session 중 모두 `pinch in/out`으로 scope 전환이 가능해야 한다.
- drag session 중 scope 전환은 `CalendarDragCoordinator` 세션을 유지한 채 이루어져야 한다.
- month/year drop이 성공하면 결과 날짜 기준으로 `day` scope로 복귀한다.
- 기존 edge-hover timer 기반 인접 날짜 이동은 더 이상 핵심 경로가 아니며 제거 대상임을 명시하라.

### 2. `docs/prd.md` 업데이트

타임라인 편집 모드와 인터랙션 섹션에 아래 내용을 추가/정정하라.

- `pinch`는 문서상의 제스처가 아니라 실제 구현 대상이다.
- cross-day / cross-scope move는 단일 root drag path만 사용한다.
- legacy edge-hover fallback은 제거하고 `restore-first policy`를 유지한다.
- drop 성공 후 `selectedDate`와 화면 scope는 결과 날짜의 `day` 기준으로 맞춘다.

### 3. `docs/code-architecture.md` 업데이트

아래 구조를 문서에 명확히 반영하라.

- `ContentView`가 scope pinch bridge의 owner다.
- `DayView`의 edge-hover timer/indicator 상태는 제거 대상이다.
- `EditableEventBlock`은 local move completion owner가 아니며 pointer forwarding 역할만 가진다.
- session cleanup은 `CalendarDragCoordinator`와 root scope에서 일관되게 수행한다.

### 4. `docs/adr.md` 업데이트

기존 마지막 번호 다음으로 새 ADR을 추가하라.

- `ADR-029`: cross-scope drag path는 pinch scope bridge와 root coordinator 하나로 통일한다.

용어는 아래 표현으로 통일하라.

- `CalendarDragCoordinator`
- `DragSessionEngine`
- `pinch scope transition`
- `root drag path`
- `restore-first policy`

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && rg -n "pinch|edge-hover|CalendarDragCoordinator|root drag path|restore-first policy|ADR-029|day scope로 복귀|day scope로 돌아" docs/flow.md docs/prd.md docs/code-architecture.md docs/adr.md
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/6-interaction-completion/index.json`의 phase 0 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- 이 phase에서는 문서만 수정하라. Swift 소스, `project.yml`, 테스트 파일은 건드리지 마라.
- `docs-diff.md`는 runner가 생성한다. 직접 만들지 마라.
- 새 UX를 문서에 추가할 때 기존 draglab 계약과 충돌시키지 마라.
- 기존 테스트를 깨뜨리지 마라.
