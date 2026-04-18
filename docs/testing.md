# tic — Testing Strategy

## 원칙

- 순수 로직을 먼저 검증한다.
- drag 회귀는 계산 테스트와 실제 simulator 테스트를 둘 다 둔다.
- mock-heavy UI 테스트는 늘리지 않는다.
- 구현 직후 관련 테스트를 같이 추가한다.

## 테스트 계층

1. `ticTests`

- 대상: `DragSessionEngine`, `DragSessionGeometry`, `CalendarDragCoordinator`, `DayViewModel`
- 목적: 상태 전이, geometry 계약, hover 판정, pending move projection, restore 정책 검증
- 특징: 빠르고 결정적이다. drag 회귀를 가장 먼저 잡는다.

2. `ticUITests`

- 대상: 실제 iOS Simulator 위의 drag 제스처
- 목적: 접근성 id로 실제 타임블록을 잡고, drag 후 시간 값이 바뀌는지 검증
- 특징: 시각적 픽셀 추정보다 실제 앱 상태와 접근성 값을 본다.

## drag 회귀 기준

- day 같은 날짜 안에서 시간 이동 후 drop이 commit돼야 한다.
- day 좌우 edge-hover로 날짜를 넘긴 뒤에도 같은 session이 유지돼야 한다.
- day 좌우 edge-hover 뒤 drop은 `restore`가 아니라 유효 drop이면 commit돼야 한다.
- month/year 전환 뒤 hover 후 drop도 `selectedDate`와 `activeDate` 규칙을 지켜야 한다.
- `minuteCandidate`는 raw finger가 아니라 overlay probe 기준으로 계산돼야 한다.

## 현재 고정된 회귀 테스트

### 순수 로직

- `ticTests/DragSessionGeometryTests.swift`
  - timeline drop zone 안쪽 snap
  - timeline 밖 pointer reject
  - overlay top probe로 same-day drop 유지
  - overlay midX probe로 day edge-hover 경로 유지

- `ticTests/CalendarDragCoordinatorTests.swift`
  - pending relay와 root claim handoff
  - local day drop과 global drop 분기
  - cancellation/drop termination policy
  - day edge-hover resolver
  - `DayViewModel` pending timed move projection

### 실제 simulator

- `ticUITests/DirectDragUITests.swift`
  - 오늘 날짜의 `00:00` timed block을 찾는다.
  - 편집 모드로 진입한다.
  - 실제 drag gesture를 보낸다.
  - drag 전후 `accessibilityValue`가 달라졌는지 확인한다.
  - `drag-debug-overlay`로 종료 상태가 `committed`인지 확인할 수 있다.

## 디버그 계약

- `TIC_DRAG_DEBUG=1`
  - drag debug 로그와 overlay 텍스트를 켠다.

- `timeline-event-<item.id>`
  - timed block 접근성 식별자다.
  - UI test에서 실제 이벤트 블록을 안정적으로 찾는 기준이다.

- `drag-debug-overlay`
  - 현재 scope, pointer, minute, termination을 화면에 노출한다.
  - simulator 수동 재현과 UI test 로그 해석에 쓴다.

## 실행 명령

```bash
xcodegen generate
xcodebuild test -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:ticTests/DragSessionGeometryTests
xcodebuild test -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:ticTests/CalendarDragCoordinatorTests
xcodebuild test -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:ticUITests/DirectDragUITests/testSameDayTimedBlockDragMovesVisibly
```

## 해석 규칙

- drag 버그를 고칠 때는 먼저 `ticTests`에서 계산 계약을 고정한다.
- 그 다음 `ticUITests`로 실제 simulator 경로를 확인한다.
- 둘 중 하나만 통과하면 고친 것으로 보지 않는다.
