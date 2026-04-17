# Phase 1: touch-claim-token

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `docs/flow.md`
- `docs/prd.md`
- `docs/code-architecture.md`
- `docs/adr.md`
- `docs/testing.md`
- `docs/timeline-block-animation.md`
- `/tasks/8-drag-handoff/docs-diff.md`

그리고 이전 phase의 작업물과 현재 관련 코드를 반드시 확인하라:

- `tasks/8-drag-handoff/phase0.md`
- `docs/adr.md`
- `docs/flow.md`
- `docs/code-architecture.md`
- `docs/prd.md`
- `docs/timeline-block-animation.md`
- `tic/DragSession/DragSessionTypes.swift`
- `tic/DragSession/CalendarDragCoordinator.swift`
- `tic/Views/Components/DragSessionTouchCaptureBridge.swift`
- `tic/Views/ContentView.swift`
- `ticTests/CalendarDragCoordinatorTests.swift`
- `ticTests/DragOverlayPresentationTests.swift`

이전 phase에서 합의된 bounded handoff 문서 계약을 코드의 순수 타입으로 옮겨라.

## 작업 내용

이번 phase의 목적은 **touch claim handoff를 순수 모델로 분리해 테스트 가능한 토대를 만드는 것**이다. 아직 `View` 계층의 실제 drag 동작은 바꾸지 마라.

### 1. 순수 touch claim 타입 추가

`tic/DragSession/` 아래에 순수 helper/type을 추가하라. 파일명과 타입명은 달라도 되지만 아래 개념은 반드시 표현해야 한다.

- gesture마다 유일한 claim token
- local preview 시작 시점
- pending claim 상태
- root claim 성공 상태
- timeout / cancel / stale event 무시 규칙
- bounded window 판정

구현은 UIKit 객체나 `DispatchQueue`에 직접 의존하지 마라. 시간/프레임 window 판정은 주입 가능한 값으로 계산 가능해야 한다.

### 2. 상태 전이 규칙 고정

아래 규칙을 순수 helper 수준에서 보장하라.

- 새로운 token이 시작되면 이전 token의 늦은 성공/종료 이벤트는 stale로 간주한다.
- pending claim 중에는 root owner로 승격되지 않는다.
- claim 성공 전에는 placeholder를 켜면 안 되는 상태임을 표현할 수 있어야 한다.
- timeout은 hard fail이 아니라 restore reason으로 분류 가능해야 한다.
- cancel과 timeout을 구분할 수 있어야 한다.

### 3. bridge 연동을 위한 최소 인터페이스 정리

다음 phase에서 `CalendarDragCoordinator`와 `DragSessionTouchCaptureBridge`가 붙을 수 있도록, 순수 helper가 기대하는 최소 입력/출력 인터페이스를 정리하라.

- token 발급
- claim 요청 시작
- claim 성공/실패 보고
- timeout 판정
- 현재 owner 여부 조회

이 phase에서는 실제 UIKit bridge 로직을 과하게 수정하지 마라. 필요한 경우 protocol 또는 작은 adapter 형태의 얇은 경계만 추가하라.

### 4. 순수 테스트 추가

새로운 XCTest를 추가해 아래 시나리오를 검증하라.

- 새 token 시작 후 pending claim이 생성된다.
- 같은 token의 claim success만 유효하다.
- 이전 token의 늦은 success/end/cancel은 stale로 무시된다.
- timeout window를 넘기면 restore reason이 timeout으로 분류된다.
- claim 성공 전에는 placeholder/root-owner 진입 판단이 false다.

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodegen generate && xcodebuild test -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' -only-testing:ticTests/CalendarDragCoordinatorTests -only-testing:ticTests/DragOverlayPresentationTests CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/8-drag-handoff/index.json`의 phase 1 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- 이 phase에서는 `EditableEventBlock`, `TimelineView`, `DayView`의 gesture 흐름을 직접 바꾸지 마라.
- helper를 UIKit 전용 타입으로 만들지 마라. 테스트 가능성이 우선이다.
- timeout을 타이머 객체로 박아 넣지 마라. 다음 phase에서 coordinator가 기존 animation/cleanup 흐름과 함께 관리할 수 있어야 한다.
