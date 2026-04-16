# Phase 2: timeline-lift-and-float

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
- `tic/Views/ContentView.swift`
- `tic/Views/Components/TimelineView.swift`
- `tic/Views/Components/EditableEventBlock.swift`
- `tic/Views/Components/DragSessionOverlayBlock.swift`
- `tic/Views/Components/DragSessionTouchCaptureBridge.swift`
- `tic/DragSession/CalendarDragCoordinator.swift`
- `tic/DragSession/DragSessionEngine.swift`
- `ticTests/CalendarDragCoordinatorTests.swift`

## 작업 내용

이번 phase의 목적은 **day timeline 안에서 블록이 붙어 있는 요소에서 떠다니는 조작 대상으로 자연스럽게 분리되는 순간을 구현**하는 것이다.

### 1. lift 단계 구현

아래 흐름을 구현하라.

- 편집 모드에서 drag를 시작하면 source block은 즉시 사라지지 말고 약한 placeholder로 남는다.
- overlay는 짧은 lift transition 뒤 floating `timelineCard`가 된다.
- lift는 짧고 명확해야 한다. 권장 범위는 0.12초 ~ 0.18초 spring이다.
- scale은 과하지 않게 1.02 ~ 1.04 범위에서만 사용하라.
- shadow / elevation은 lift 시점에만 한 단계 올리고, drag follow 중에는 계속 흔들리지 않게 하라.

### 2. drag follow는 즉시 추적

아래 원칙을 지켜라.

- pointer 이동과 overlay 이동은 drag 중 거의 즉시 일치해야 한다.
- drag follow 구간에는 per-frame spring을 걸지 마라.
- `transaction` 또는 동등한 방식으로 drag update의 implicit animation을 끄고, 상태 전환 시점만 명시적으로 animate하라.
- overlay frame은 가능한 한 하나의 절대 좌표 경로로 유지하라.

### 3. source / overlay 역할 분리

`TimelineView`와 `EditableEventBlock`에서 아래를 보장하라.

- source block은 placeholder 역할만 남는다.
- floating 상태에 들어간 뒤에는 resize handle, toolbar, 부가 affordance가 overlay에 남지 않는다.
- overlay는 title이 보이는 full card로 유지하되, interaction affordance는 최소화한다.
- same-day drop local path는 유지하되, visual ownership은 overlay 하나로 고정한다.

### 4. 테스트 보강

최소 아래 시나리오를 XCTest로 검증하라.

- drag 시작 직후 placeholder는 보이지만 source와 overlay가 완전히 겹쳐서 이중 블록처럼 보이지 않는다.
- floating timeline phase에서 overlay는 `timelineCard` 스타일을 유지한다.
- drag follow 업데이트가 offset만 바꾸고 lift animation을 다시 트리거하지 않는다.
- same-day local drop 경로는 여전히 commit을 생성한다.

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodegen generate && xcodebuild test -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' -only-testing:ticTests CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/7-timeline-block-animation/index.json`의 phase 2 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- lift를 과하게 키워 점프처럼 보이게 만들지 마라.
- drag follow에 spring을 걸어 손가락과 block이 따로 노는 느낌을 만들지 마라.
- placeholder가 session 종료 후 남지 않게 하라.
- month/year capsule 압축은 다음 phase에서 구현하라.
