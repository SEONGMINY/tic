# Phase 3: ui-root-claim-integration

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `docs/flow.md`
- `docs/prd.md`
- `docs/code-architecture.md`
- `docs/adr.md`
- `docs/testing.md`
- `docs/timeline-block-animation.md`
- `/tasks/8-drag-handoff/docs-diff.md`

그리고 이전 phase의 작업물을 반드시 확인하라:

- `tasks/8-drag-handoff/phase0.md`
- `tasks/8-drag-handoff/phase1.md`
- `tasks/8-drag-handoff/phase2.md`
- `tic/DragSession/CalendarDragCoordinator.swift`
- Phase 1에서 추가한 touch claim 관련 파일 전부
- `tic/Views/ContentView.swift`
- `tic/Views/Calendar/DayView.swift`
- `tic/Views/Components/TimelineView.swift`
- `tic/Views/Components/EditableEventBlock.swift`
- `tic/Views/Components/DragSessionTouchCaptureBridge.swift`
- `tic/Views/Components/DragSessionOverlayBlock.swift`

이전 phase에서 정리한 coordinator handoff state를 실제 View 계층과 bridge에 연결하라.

## 작업 내용

이번 phase의 목적은 **"즉시 lift + bounded async root claim" 흐름을 실제 UI에 연결하는 것**이다. 현재의 동기 `captureTouch` 성공 여부를 drag 시작 gate로 두는 구조는 제거하거나 우회해야 한다.

### 1. drag 시작 흐름 재구성

아래 순서를 코드로 반영하라.

1. `EditableEventBlock`에서 move gesture가 시작되면 local preview가 즉시 시작된다.
2. 같은 gesture에 대한 explicit token으로 root claim 요청이 발행된다.
3. claim pending 동안에는 drag가 deadlock 없이 최소한 local preview 기준으로 따라온다.
4. root claim이 성공하면 ownership이 coordinator/root path로 승격된다.
5. claim 실패나 timeout이면 즉시 restore한다.

### 2. synchronous capture deadlock 제거

현재처럼 `ContentView.beginCapturedMoveDrag(...) -> Bool` 같은 동기 반환값 하나로 시작 여부를 결정하지 마라.

반드시 아래를 만족하라.

- root recognizer가 첫 프레임에서 아직 touch를 모르는 경우에도 local preview는 시작된다.
- 늦게 들어온 root claim success는 token이 현재 세션과 일치할 때만 승격시킨다.
- claim pending 중 손을 떼면 세션이 정상 종료되며 floating overlay가 남지 않는다.

### 3. 좌표계 일관성 고정

`ContentView`, `DragSessionTouchCaptureBridge`, `EditableEventBlock`, `TimelineView` 사이를 오가는 좌표는 전부 global 기준으로 맞춰라.

- root boundary를 넘을 때 local/global 혼용을 허용하지 마라.
- scope 전환 후에도 overlay frame과 pointer update가 같은 좌표계에서 계산되어야 한다.

### 4. single owner / single overlay 보장

- claim pending 동안 local preview와 root overlay가 동시에 active owner가 되지 않게 하라.
- placeholder는 claim success 이후에만 보이게 하라.
- month/year scope로 넘어간 뒤 손을 떼더라도 세션 종료가 한 번만 일어나게 하라.

### 5. 기존 편집 affordance 보존

- non-drag 편집 상태에서 toolbar/resize handle 노출 계약을 깨뜨리지 마라.
- drag 중에는 기존 animation contract를 유지하되, pointer follow에 implicit animation을 섞지 마라.

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodegen generate && xcodebuild test -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' -only-testing:ticTests/CalendarDragCoordinatorTests -only-testing:ticTests/DragOverlayPresentationTests CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/8-drag-handoff/index.json`의 phase 3 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- `captureTouch(near:)`의 즉시 성공을 시작 조건으로 되돌리지 마라.
- root claim을 polling loop나 장시간 timer로 구현하지 마라. bounded window를 넘는 재시도는 금지다.
- double overlay, duplicate end handling, stale token mutation을 허용하지 마라.
