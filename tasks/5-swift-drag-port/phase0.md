# Phase 0: docs-alignment

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `docs/flow.md`
- `docs/prd.md`
- `docs/code-architecture.md`
- `docs/adr.md`
- `docs/testing.md`

그리고 아래 소스 파일들을 읽어 현재 SwiftUI 구조를 파악하라:

- `tic/Views/ContentView.swift`
- `tic/Views/Calendar/DayView.swift`
- `tic/Views/Components/TimelineView.swift`
- `tic/Views/Components/EditableEventBlock.swift`
- `tic/Views/Calendar/MonthView.swift`
- `tic/Views/Calendar/YearView.swift`
- `tic/ViewModels/CalendarViewModel.swift`
- `project.yml`

기존 task의 관련 작업물을 반드시 확인하라:

- `tasks/4-draglab/phase0.md`
- `tasks/4-draglab/phase1.md`
- `tasks/4-draglab/phase2.md`

## 작업 내용

이번 phase의 목적은 **Swift 포팅 기준을 문서에서 먼저 고정**하는 것이다. Swift 소스 구현은 하지 말고 문서만 수정하라.

### 1. `docs/code-architecture.md` 업데이트

아래 내용을 반영하라.

- cross-scope drag session owner는 `DayView`가 아니라 `ContentView` 또는 scope 전환 위에 있는 단일 coordinator가 가진다.
- `DayView`, `MonthView`, `YearView`는 session owner가 아니며, geometry/frame/reporting 역할만 가진다.
- month/year 날짜 셀은 `global coordinates` 기준 frame을 상위 owner에 보고한다.
- Swift 포팅 구조에 `CalendarDragCoordinator`와 `DragSessionEngine`를 명시하고 책임을 분리한다.
- `ticTests` XCTest target을 추가해 순수 drag 로직을 검증한다는 방침을 넣는다.
- 기존 `DayView 최상위 overlay` 표현이 남아 있다면 `root overlay owner` 기준으로 정정한다.

### 2. `docs/flow.md` 업데이트

F2/F3/F7 흐름에 아래 내용을 명시하라.

- drag session은 현재 scope 뷰가 교체되어도 종료되지 않는다.
- overlay는 root scope 위에서 계속 보인다.
- month/year 날짜 셀은 hover hit-test를 통해 `activeDate`를 갱신한다.
- scope 전환 트리거는 pinch에 한정하지 않고, `viewModel.scope`가 변경되는 모든 경로에서 session 보존이 가능해야 한다.

### 3. `docs/prd.md` 업데이트

타임라인 편집 모드와 drag 실험기 섹션에 아래 내용을 추가하라.

- Swift 포팅은 Python `draglab` 계약을 그대로 사용한다.
- `minuteCandidate`, `activeDate`, drop validity, restore 정책은 Swift와 Python이 동일해야 한다.
- 테스트는 mock-heavy UI 테스트가 아니라 순수 로직 XCTest 위주로 간다.

### 4. `docs/adr.md` 업데이트

새 ADR 두 개를 추가하라. 기존 마지막 번호 다음을 사용한다.

- `ADR-027`: cross-scope drag session owner는 scope switch 위의 단일 coordinator가 가진다.
- `ADR-028`: Swift drag 포팅은 `ticTests`의 순수 로직 테스트와 `draglab` 계약을 기준으로 검증한다.

### 5. 용어 통일

아래 표현을 문서 전반에서 일관되게 사용하라.

- `CalendarDragCoordinator`
- `DragSessionEngine`
- `activeDate`
- `minuteCandidate`
- `global coordinates`
- `restore-first policy`

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && rg -n "CalendarDragCoordinator|DragSessionEngine|ticTests|ADR-027|ADR-028|global coordinates|restore-first policy" docs/flow.md docs/prd.md docs/code-architecture.md docs/adr.md
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/5-swift-drag-port/index.json`의 phase 0 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- 이 phase에서는 문서만 수정하라. `project.yml`, `tic.xcodeproj`, Swift 소스는 건드리지 마라.
- 기존 `draglab` 문서와 충돌하지 마라. Swift 포팅은 Python 계약을 소비하는 단계라는 점을 유지하라.
- scope 전환 입력 방식은 이 phase에서 확정하지 않는다. 핵심은 `scope change` 자체보다 session continuity다.
- `docs-diff.md`는 runner가 생성한다. 직접 만들지 마라.
