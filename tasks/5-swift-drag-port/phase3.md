# Phase 3: calendar-hover-bridge

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `docs/flow.md`
- `docs/prd.md`
- `docs/code-architecture.md`
- `docs/adr.md`
- `docs/testing.md`
- `/tasks/5-swift-drag-port/docs-diff.md`

그리고 이전 phase의 작업물을 반드시 확인하라:

- `tic/DragSession/DragSessionTypes.swift`
- `tic/DragSession/DragSessionGeometry.swift`
- `tic/DragSession/DragSessionEngine.swift`
- `tic/DragSession/CalendarDragCoordinator.swift`
- `tic/Views/ContentView.swift`
- `tic/Views/Calendar/DayView.swift`
- `tic/Views/Components/TimelineView.swift`
- `tic/Views/Components/EditableEventBlock.swift`

아래 파일도 읽어 month/year 구조를 파악하라:

- `tic/Views/Calendar/MonthView.swift`
- `tic/Views/Calendar/YearView.swift`
- `tic/ViewModels/CalendarViewModel.swift`

## 작업 내용

이번 phase의 목적은 **drag session을 month/year scope까지 끊기지 않게 연결**하는 것이다. 최종 commit은 아직 phase 4에서 한다.

### 1. 날짜 셀 frame reporting 추가

`MonthView.swift`와 `YearView.swift`에 날짜 셀 frame 수집 경로를 추가하라.

- 각 날짜 셀은 `global coordinates` 기준 frame과 `Date`를 상위로 보고해야 한다.
- Month/Year 각각 별도 구현을 하되, 최종적으로 coordinator가 공통 형식으로 소비할 수 있게 맞춰라.
- cell frame 수집은 SwiftUI layout jitter를 최소화하는 방향으로 구현하라. PreferenceKey 사용이 적합하면 사용하라.

### 2. `ContentView` scope bridge

`ContentView.swift`에서 아래를 보장하라.

- 현재 `viewModel.scope`가 바뀌면 coordinator가 새 scope를 인지한다.
- drag session이 active인 동안 root overlay는 유지된다.
- 현재 scope의 frame registry만 coordinator에 주입된다.

### 3. calendar hover hit-test 연결

coordinator/engine에 아래를 연결하라.

- month/year에서 pointer가 유효한 날짜 셀 위에 있으면 `activeDate` 갱신
- 유효한 셀이 없으면 `activeDate`를 nil로 둘 수 있어야 함
- calendar scope에서는 `minuteCandidate`를 새로 만들지 않고 유지
- day scope로 돌아오면 timeline geometry로 minute candidate가 다시 갱신됨

### 4. 순수 테스트 추가

새 순수 helper가 생기면 테스트를 바로 추가하라.

최소 아래 시나리오를 검증하라.

- overlapping or stale frame이 있어도 현재 pointer 포함 셀만 activeDate가 된다
- activeDate가 사라지면 droppable false로 전환된다
- scope change 후에도 session context의 duration/source date는 유지된다

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodegen generate && xcodebuild test -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16'
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/5-swift-drag-port/index.json`의 phase 3 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- 이 phase에서는 EventKit write를 하지 마라. hover candidate와 session continuity까지만 연결한다.
- month/year 렌더링 성능을 해치는 per-cell heavy state를 추가하지 마라.
- stale frame cache가 남아서 잘못된 activeDate가 잡히면 안 된다. scope 교체 시 registry 정리를 잊지 마라.
