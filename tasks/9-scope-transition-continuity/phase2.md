# Phase 2: view-transition-continuity

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `docs/flow.md`
- `docs/prd.md`
- `docs/code-architecture.md`
- `docs/adr.md`
- `docs/testing.md`
- `docs/timeline-block-animation.md`
- `/tasks/9-scope-transition-continuity/docs-diff.md`

그리고 이전 phase의 작업물을 반드시 확인하라:

- `tasks/9-scope-transition-continuity/phase0.md`
- `tasks/9-scope-transition-continuity/phase1.md`
- `tic/DragSession/CalendarDragCoordinator.swift`
- `tic/DragSession/DragOverlayPresentation.swift`
- `tic/Views/ContentView.swift`
- `tic/Views/Components/EditableEventBlock.swift`
- `tic/Views/Components/TimelineView.swift`
- `tic/Views/Calendar/DayView.swift`
- `tic/Views/Calendar/MonthView.swift`
- `tic/Views/Calendar/YearView.swift`
- `ticTests/CalendarDragCoordinatorTests.swift`

이전 phase에서 coordinator가 노출한 continuity semantics를 실제 SwiftUI 렌더 경로에 연결하라.

## 작업 내용

이번 phase의 목적은 **day local preview에서 month/year continuity overlay로 끊김 없이 넘어가도록 view wiring을 정리하고, 중복 렌더 없이 회귀를 닫는 것**이다.

### 1. local preview와 continuity overlay 중복 제거

아래를 보장하라.

- `pending + day`에서는 기존 local preview가 보인다.
- `pending + non-day`로 넘어가면 local preview는 더 이상 렌더 주체가 아니어야 한다.
- 대신 root 쪽 continuity overlay가 `holding card`로 유지된다.
- 두 표현이 동시에 활성 owner처럼 보이지 않게 하라.

### 2. scope transition continuity 연결

`ContentView`, `EditableEventBlock`, `TimelineView`를 정리해 아래를 만족하라.

- day -> month/year 전환 순간 블록이 사라지지 않는다.
- claim 성공 전에는 card 모양을 유지한다.
- claim 성공 후에만 기존 `holding -> calendarPill` 애니메이션이 이어진다.
- month/year에서 hover target 강조는 claim 성공 전까지 켜지지 않는다.

### 3. 기존 drag 경로 보존

아래 경로를 깨뜨리지 마라.

- day 내부 same-day local drop
- claim 성공 후 global drag/drop
- invalid drop restore
- 이전 fix의 drag freeze 방지 경로

### 4. 최종 테스트와 빌드 검증

이 phase에서 필요한 회귀 테스트를 정리하고 실행하라.

최소 확인 항목:

- pending 상태에서 scope 전환 시 continuity overlay가 유지된다.
- pending 상태에서 local preview와 root continuity overlay가 이중 렌더되지 않는다.
- claim 성공 후 pill 전환과 month/year active target이 정상 동작한다.
- 전체 테스트 스위트가 통과한다.

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodegen generate && xcodebuild test -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/9-scope-transition-continuity/index.json`의 phase 2 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- overlay를 둘로 나누지 마라. continuity 표현은 여전히 single overlay 계약 안에서 풀어야 한다.
- claim 전 `calendarPill`을 먼저 켜지 마라.
- `rootClaimPending` 문제를 해결하려고 scope 전환 자체를 막지 마라.
- hot path에 무거운 로깅이나 디버그 코드를 추가하지 마라.
