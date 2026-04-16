# Phase 1: scope-gesture-bridge

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `docs/flow.md`
- `docs/prd.md`
- `docs/code-architecture.md`
- `docs/adr.md`
- `docs/testing.md`
- `/tasks/6-interaction-completion/docs-diff.md`

그리고 이전 phase의 작업물을 반드시 확인하라:

- `tasks/6-interaction-completion/phase0.md`
- `tic/Views/ContentView.swift`
- `tic/ViewModels/CalendarViewModel.swift`
- `tic/DragSession/CalendarDragCoordinator.swift`
- `tic/Views/Calendar/DayView.swift`
- `tic/Views/Calendar/MonthView.swift`
- `tic/Views/Calendar/YearView.swift`

이전 task의 drag 포팅 기반 파일도 다시 읽어라:

- `tic/DragSession/DragSessionTypes.swift`
- `tic/DragSession/DragSessionGeometry.swift`
- `tic/DragSession/DragSessionEngine.swift`
- `ticTests/DragSessionEngineTests.swift`

## 작업 내용

이번 phase의 목적은 **scope pinch 전환을 실제 코드에 연결**하는 것이다. legacy edge-hover 제거는 다음 phase에서 한다.

### 1. pinch scope transition 구현

아래 요구를 충족하라.

- `ContentView` 또는 root scope owner에서 `pinch in/out` 제스처를 해석한다.
- idle 상태에서도 `day ↔ month ↔ year` 전환이 실제 동작해야 한다.
- active drag session 중에도 `viewModel.scope`가 바뀌어도 세션이 유지되어야 한다.
- scope 전환 시 overlay frame continuity를 깨뜨리지 마라.

### 2. scope 전환 규칙을 순수 helper로 분리

테스트 가능한 순수 규칙을 만든 뒤 그 helper를 사용하라.

예시 범위:

- 현재 scope와 pinch 방향으로 다음 scope를 결정
- 더 이상 확대/축소할 수 없는 끝 scope에서는 no-op
- drag session 중에도 기존 `dragCoordinator.updateVisibleScope` 흐름을 그대로 활용

helper의 위치는 테스트하기 쉬운 곳으로 두고, SwiftUI gesture 내부에 분기 로직을 직접 중복하지 마라.

### 3. 순수 테스트 추가

이 phase에서 추가한 helper는 같은 phase에서 바로 XCTest를 작성하라.

최소 아래 시나리오를 검증하라.

- day에서 pinch out → month
- month에서 pinch out → year
- year에서 pinch out → no-op
- year에서 pinch in → month
- month에서 pinch in → day
- active drag 상태에서 scope를 바꿔도 source/duration/session visibility는 유지됨

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodegen generate && xcodebuild test -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' -only-testing:ticTests CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/6-interaction-completion/index.json`의 phase 1 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- 이 phase에서는 edge-hover timer를 제거하지 마라. 다음 phase에서 제거한다.
- pinch 로직 때문에 기존 탭/스와이프 gesture가 죽지 않도록 우선순위를 조정하라.
- scope 전환 규칙을 View 코드 여러 곳에 복붙하지 마라.
- 기존 테스트를 깨뜨리지 마라.
