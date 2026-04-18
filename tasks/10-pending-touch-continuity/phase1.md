# Phase 1: pending-touch-relay

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `docs/flow.md`
- `docs/prd.md`
- `docs/code-architecture.md`
- `docs/adr.md`
- `docs/testing.md`
- `docs/timeline-block-animation.md`
- `/tasks/10-pending-touch-continuity/docs-diff.md`

그리고 이전 phase의 작업물과 현재 관련 코드를 반드시 확인하라:

- `tasks/10-pending-touch-continuity/phase0.md`
- `docs/flow.md`
- `docs/code-architecture.md`
- `docs/adr.md`
- `docs/timeline-block-animation.md`
- `tic/DragSession/CalendarDragCoordinator.swift`
- `tic/DragSession/DragTouchClaim.swift`
- `tic/Views/ContentView.swift`
- `tic/Views/Components/DragSessionTouchCaptureBridge.swift`
- `tic/Views/Components/EditableEventBlock.swift`
- `ticTests/CalendarDragCoordinatorTests.swift`

## 작업 내용

이번 phase의 목적은 **`rootClaimPending + non-day`에서 continuity overlay가 손가락을 계속 따라오도록 `touch tracking relay`를 복구하는 것**이다. ownership contract는 그대로 두고, 입력 추적 경로만 보강하라.

### 1. tracking relay 경로 추가

`ContentView`, `DragSessionTouchCaptureBridge`, `CalendarDragCoordinator`를 조정해 아래를 만족하라.

- root claim 성공 전이어도 현재 pending token의 move/end stream을 coordinator가 받을 수 있어야 한다.
- 이 입력 경로는 `tracking relay`다. `shouldHandleDragGlobally`나 `dropOwner`를 우회하는 새로운 ownership 경로가 아니어야 한다.
- stale token move/end/cancel은 계속 무시하라.
- claim 성공 뒤에는 기존 root global drag 경로와 자연스럽게 이어져야 한다.

### 2. pending non-day follow 복구

아래 동작을 구현하라.

- `rootClaimPending + visibleScope != .day`에서 move 입력이 들어오면 continuity overlay frame이 계속 갱신된다.
- 이 상태에서도 `allowsCalendarHover`, `shouldHandleDragGlobally`, `showsPlaceholder`는 false를 유지한다.
- `activeDate`는 claim 성공 전까지 nil이어야 한다.
- `pending + non-day` 상태의 touch up은 commit을 만들지 않고 restore로 정리하라.

### 3. coordinator API 정리

- 가능하면 `global drag`와 `tracking relay`를 구분하는 이름을 사용하라.
- pending 상태용 입력 갱신 함수는 ownership이 아니라 tracking만 열어 준다는 의도가 드러나야 한다.
- UIKit recognizer 세부사항이 coordinator로 새어 나오지 않게 유지하라.

### 4. 테스트를 같은 phase에서 바로 추가

`docs/testing.md` 원칙대로 coordinator 중심 테스트를 이 phase에서 바로 보강하라.

최소 아래를 검증하라.

- pending 상태에서 month/year 전환 후에도 relay move가 overlay frame을 계속 갱신한다.
- 같은 상태에서 `shouldHandleDragGlobally == false`가 유지된다.
- 같은 상태에서 `activeDate == nil` 이다.
- pending non-day touch up은 restore다.
- claim 성공 후에는 기존 root-owned 경로로 자연스럽게 이어진다.

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodegen generate && xcodebuild test -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' -only-testing:ticTests/CalendarDragCoordinatorTests CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/10-pending-touch-continuity/index.json`의 phase 1 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- ownership gate를 풀어서 문제를 해결하지 마라.
- claim 전에는 month/year hover를 열지 마라.
- `pending + day`의 local drop 경로를 깨뜨리지 마라.
- `DragSessionTouchCaptureBridge`가 session token을 무시한 채 아무 move나 전달하게 만들지 마라.
