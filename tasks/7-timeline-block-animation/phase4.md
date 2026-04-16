# Phase 4: landing-restore-and-performance

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `docs/flow.md`
- `docs/prd.md`
- `docs/code-architecture.md`
- `docs/adr.md`
- `docs/testing.md`
- `docs/timeline-block-animation.md`
- `/tasks/7-timeline-block-animation/docs-diff.md`

그리고 이전 phase의 작업물을 반드시 확인하라:

- `tasks/7-timeline-block-animation/phase0.md`
- `tasks/7-timeline-block-animation/phase1.md`
- `tasks/7-timeline-block-animation/phase2.md`
- `tasks/7-timeline-block-animation/phase3.md`
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
- `ticTests/DragSessionEngineTests.swift`
- `ticTests/CalendarScopeTransitionTests.swift`
- `ticTests/CalendarDragCoordinatorTests.swift`

## 작업 내용

이번 phase의 목적은 **touch up drop, landing, restore, 편집 모드 종료 규칙, 성능 가드레일까지 실제 동작으로 완성**하는 것이다.

### 1. drop / landing 완료

아래 규칙을 구현하라.

- drop은 손을 떼는 `touch up` 한 번으로만 확정된다.
- valid drop이면 current session의 minute candidate와 duration을 유지한 채 결과 날짜 기준으로 commit한다.
- month/year drop 성공 후에는 결과 날짜의 `day` scope로 복귀하고, 같은 overlay가 day timeline slot으로 landing한 뒤 정리된다.
- landing은 짧고 분명해야 한다. 권장 범위는 0.14초 ~ 0.22초 spring이다.

### 2. 편집 모드 종료 규칙 고정

아래를 반드시 지켜라.

- 성공 commit 시에만 편집 모드를 종료한다.
- invalid drop / cancel / restore에서는 commit 없이 session만 정리하고 편집 모드는 유지한다.
- successful commit과 cancel/restore가 같은 세션에서 동시에 일어나지 않게 race를 막아라.

### 3. restore 경로 완성

아래를 보장하라.

- invalid drop은 가장 가까운 valid target으로 clamp하지 않는다.
- target이 없거나 hover가 불안정하면 source 위치로 restore한다.
- restore animation 후 overlay, placeholder, active target, stale frame registry가 모두 정리된다.
- 다음 세션이 이전 session의 `activeDate` 또는 frame cache를 재사용하지 않게 하라.

### 4. 성능 가드레일 반영

구글 시니어 수준의 보수적 구현 원칙으로 아래를 반영하라.

- moving overlay는 하나만 유지한다.
- highlight는 active target 하나만 유지한다.
- drag follow는 direct update로 처리하고, spring은 phase change에서만 쓴다.
- scope별 frame registry와 presentation 계산은 필요한 순간에만 갱신한다.
- root body 전체가 drag 매 프레임 다시 계산되지 않도록 상태 분리를 점검하라.
- `matchedGeometryEffect`가 필요하더라도 landing/restore 같은 bounded transition에만 한정하라.

### 5. 테스트와 검증 보강

최소 아래 시나리오를 XCTest로 검증하라.

- valid month/year drop은 결과 날짜의 day scope 상태를 반환한다.
- successful commit은 편집 모드를 종료한다.
- invalid drop / cancel은 commit 없이 restore되고 편집 모드를 유지한다.
- stale frame registry와 active target이 다음 세션에 누수되지 않는다.
- landing 또는 restore가 끝난 뒤 placeholder와 overlay가 모두 정리된다.

작업 후 수동 점검도 수행하라.

- day에서 lift 후 same-day drop
- day -> month 또는 year 전환 후 hover
- month/year에서 valid drop
- month/year에서 invalid release
- restore 직후 다시 편집 모드 진입

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodegen generate && xcodebuild test -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/7-timeline-block-animation/index.json`의 phase 4 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- `commit`과 `편집 모드 종료`를 cancel 경로에 섞지 마라.
- invalid drop을 보정 저장하지 마라. `restore-first policy`를 유지하라.
- 성능 문제를 감추려고 drag follow를 과한 animation으로 덮지 마라.
- 기존 일정 편집 기능, same-day 이동, 삭제/복제 등 주변 기능을 깨뜨리지 마라.
