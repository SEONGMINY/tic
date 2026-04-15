# Phase 4: drop-restore-integration

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
- `tic/Views/Calendar/MonthView.swift`
- `tic/Views/Calendar/YearView.swift`
- `ticTests/`

추가로 아래 서비스/모델 파일도 읽어라:

- `tic/Services/EventKitService.swift`
- `tic/Models/TicItem.swift`
- `tic/ViewModels/DayViewModel.swift`

## 작업 내용

이번 phase의 목적은 **실제 drop, cancel, restore, EventKit commit까지 완성**하는 것이다.

### 1. drop commit 연결

valid drop일 때 아래 규칙으로 최종 start/end를 계산하고 `EventKitService.moveToDate`로 반영하라.

- day timeline drop: `dateCandidate + minuteCandidate + duration`
- month/year drop: `activeDate + preserved minuteCandidate + duration`
- duration은 source session 기준 유지
- invalid candidate면 commit하지 않는다

### 2. restore/cancel 경로 완성

invalid drop, cancel, hover 미확정, overflow 상황에서 아래를 보장하라.

- 잘못된 일정 확정이 일어나지 않는다
- overlay는 restore 애니메이션 후 정리된다
- placeholder/editing state가 정상 해제된다
- session 종료 후 UI가 idle 상태로 복귀한다

### 3. 기존 임시 cross-day 로직 제거

기존 edge-hover timer 기반 날짜 이동 로직이 더 이상 핵심 경로가 아니면 제거하라.

- `DayView`의 edge hover timer 상태
- `EditableEventBlock`의 edge hover 콜백
- 불필요해진 pending 상태

단, 삭제 전에 새 coordinator 경로가 완전히 대체하는지 확인하라.

### 4. 후속 정리

필요하면 아래를 함께 정리하라.

- drag 종료 후 day data refresh 타이밍
- 동일 날짜 drop 시 중복 애니메이션 방지
- toolbar 재노출/숨김 조건
- session cleanup race 방지

### 5. 테스트 보강

순수 로직 테스트를 보강하라.

최소 아래 시나리오를 검증하라.

- month/year activeDate + minuteCandidate 조합으로 최종 Date가 계산된다
- invalid drop은 restore outcome으로 끝난다
- cancel은 commit 없이 종료된다
- overflow candidate는 clamp되지 않고 restore된다

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodegen generate && xcodebuild test -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16'
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/5-swift-drag-port/index.json`의 phase 4 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- invalid drop을 가까운 시간으로 강제 저장하지 마라. `restore-first policy`를 지켜라.
- EventKit write는 drop 확정 시점 한 번만 일어나야 한다.
- month/year frame registry와 overlay cleanup이 남아서 이후 편집 모드에 누수되면 안 된다.
- 기존 기능인 resize, delete, duplicate, normal tap-to-edit가 유지되어야 한다.
