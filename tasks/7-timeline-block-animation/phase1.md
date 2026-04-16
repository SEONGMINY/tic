# Phase 1: overlay-visual-phase

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
- `tic/DragSession/DragSessionTypes.swift`
- `tic/DragSession/DragSessionEngine.swift`
- `tic/DragSession/CalendarDragCoordinator.swift`
- `tic/Views/ContentView.swift`
- `tic/Views/Components/DragSessionOverlayBlock.swift`
- `tic/Views/Components/EditableEventBlock.swift`
- `ticTests/DragSessionEngineTests.swift`
- `ticTests/CalendarDragCoordinatorTests.swift`

이전 phase에서 만든 문서 계약을 코드에서 그대로 반영하라.

## 작업 내용

이번 phase의 목적은 **gesture state와 display state를 분리하고, overlay가 표현 phase를 이해하도록 만드는 것**이다. month/year pill 전환의 실제 동작은 다음 phase에서 고도화한다.

### 1. overlay presentation model 도입

`CalendarDragCoordinator` 주변에 테스트 가능한 presentation model을 추가하라. 이름은 달라도 되지만 아래 개념을 표현할 수 있어야 한다.

- overlay style: `timelineCard` 또는 `calendarPill`
- visual phase: anchored, lifted, floating, holding, restoring, landing
- source placeholder visibility 강도
- handle / toolbar / title 노출 여부
- overlay shadow / scale / opacity / zIndex에 필요한 파생값

핵심 규칙은 아래와 같다.

- gesture 입력값과 좌표 계산은 기존 drag/session 계층이 담당한다.
- overlay style 결정은 presentation model이 담당한다.
- `DragSessionOverlayBlock`은 coordinator의 raw boolean 여러 개를 직접 해석하지 말고, presentation model 하나를 받아 그리도록 정리하라.

### 2. `timelineCard` / `calendarPill` 렌더링 경계 분리

`DragSessionOverlayBlock.swift`를 정리해 아래를 만족하라.

- full card 렌더링과 anonymous capsule 렌더링을 분리한다.
- 이 phase에서는 실제 표시 경로가 대부분 `timelineCard`여도 괜찮다.
- 다음 phase에서 `calendarPill`을 바로 활성화할 수 있게 구조를 먼저 잡아라.
- pill은 텍스트 없는 capsule 전용 렌더링 경로를 가져야 한다.

### 3. 전환 애니메이션 책임 경계 고정

아래 원칙을 코드에 반영하라.

- drag 중 매 프레임 위치 추적은 implicit animation 없이 즉시 반영한다.
- 상태 전환 애니메이션만 명시적으로 준다.
- `withAnimation`과 `transaction` 사용 위치를 분리해, drag follow와 phase change가 서로 충돌하지 않게 하라.
- `matchedGeometryEffect`는 이 phase에서 필수로 쓰지 마라. 필요해도 landing/restore 전용 후보로 남겨라.

### 4. 순수 테스트 추가

presentation model이 순수 값 타입 또는 순수 helper로 검증 가능하도록 만들고 XCTest를 추가하라.

최소 아래 시나리오를 검증하라.

- 편집 가능 상태에서는 source block이 그대로 보이고 overlay는 inactive다.
- drag 진입 직후 presentation은 `timelineCard` lift phase로 바뀐다.
- floating timeline phase에서는 handle / toolbar / title visibility가 계약에 맞게 바뀐다.
- month/year 전환 로직을 아직 붙이지 않았더라도 `calendarPill` style 계산 경로는 테스트 가능해야 한다.
- drag follow 업데이트가 presentation phase를 불필요하게 재설정하지 않는다.

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodegen generate && xcodebuild test -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' -only-testing:ticTests CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/7-timeline-block-animation/index.json`의 phase 1 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- 이 phase에서는 month/year hover 정책을 과하게 구현하지 마라. 구조 분리까지만 우선한다.
- overlay를 두 개 띄우지 마라. `single overlay` 계약을 깨뜨리면 안 된다.
- raw gesture state를 View 코드 여러 곳에서 중복 해석하지 마라.
- 기존 drag/drop 테스트를 깨뜨리지 마라.
