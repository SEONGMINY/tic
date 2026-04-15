# Phase 1: engine-and-tests

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `docs/flow.md`
- `docs/prd.md`
- `docs/code-architecture.md`
- `docs/adr.md`
- `docs/testing.md`
- `/tasks/5-swift-drag-port/docs-diff.md`

그리고 아래 소스 파일들을 읽어 현재 구현 상태를 파악하라:

- `project.yml`
- `tic/Views/ContentView.swift`
- `tic/Views/Calendar/DayView.swift`
- `tic/Views/Components/TimelineView.swift`
- `tic/Views/Components/EditableEventBlock.swift`
- `tic/Extensions/Date+Extensions.swift`

그리고 이전 phase의 작업물을 반드시 확인하라:

- `docs/flow.md`
- `docs/prd.md`
- `docs/code-architecture.md`
- `docs/adr.md`

## 작업 내용

이번 phase의 목적은 **Swift 쪽 순수 drag 로직과 테스트 기반을 먼저 만든다**는 것이다. 아직 SwiftUI drag overlay wiring은 하지 마라.

### 1. `ticTests` target 추가

`project.yml`을 수정해 XCTest bundle target `ticTests`를 추가하라.

- 소스 경로는 `ticTests`
- 앱 모듈 `tic`를 testable import 할 수 있게 설정
- `tic` scheme에서 test action이 `ticTests`를 포함하도록 갱신
- `xcodegen generate`로 `tic.xcodeproj/project.pbxproj`도 갱신하라

### 2. 순수 drag 로직 파일 추가

새 폴더 `tic/DragSession/`을 만들고 아래 파일을 추가하라.

- `DragSessionTypes.swift`
- `DragSessionGeometry.swift`
- `DragSessionEngine.swift`

핵심 요구사항:

- SwiftUI `View` 타입에 의존하지 마라.
- EventKit에 의존하지 마라.
- `CGPoint`, `CGRect`, `CGSize`, `Date`, `Calendar` 정도의 Foundation/CoreGraphics 타입만 사용하라.
- Python `draglab` baseline과 맞는 계산 규칙을 명시하라.

### 3. 상태/계약 정의

최소 아래 수준의 타입을 정의하라.

```swift
enum DragSessionState
struct DragSessionContext
struct DragSessionParams
struct DragSessionSnapshot
enum DragSessionOutcome
```

다음 규칙을 코드에 반영하라.

- `droppable`은 top-level state가 아니라 snapshot 파생 값이다.
- `pressing`, `dragReady`, `draggingTimeline`, `draggingCalendar`, `restoring`, `idle`를 구분한다.
- invalid drop은 snap/clamp로 강제 저장하지 말고 restore 경로를 선택할 수 있어야 한다.
- `minuteCandidate`는 day timeline geometry에서만 갱신한다.
- `activeDate`는 calendar cell hit-test에서만 갱신한다.

### 4. Geometry 규칙 구현

`DragSessionGeometry.swift`에 아래 순수 계산을 넣어라.

- global Y → day timeline minute 변환
- minute snap
- overlay origin 계산
- source duration 유지
- overflow/invalid candidate 판정
- month/year date cell hit-test

핵심 규칙:

- minute snap은 `draglab` baseline과 동일한 간격을 사용한다.
- day timeline bounds 밖이면 minute candidate를 `nil`로 둘 수 있어야 한다.
- calendar hover는 가장 최근 frame이 아니라 현재 pointer가 실제 포함되는 date cell만 active로 본다.

### 5. XCTest 추가

`ticTests/` 아래 최소 아래 테스트 파일을 추가하라.

- `DragSessionGeometryTests.swift`
- `DragSessionEngineTests.swift`

필수 테스트:

- long press 이후 drag start threshold가 맞게 동작한다.
- day timeline에서 snapped minute candidate가 예상대로 계산된다.
- invalid drop은 droppable false가 된다.
- activeDate가 없는 calendar drag는 drop 불가다.
- restore path가 정상적으로 terminal snapshot을 만든다.
- false start 시 idle로 복귀한다.

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodegen generate && xcodebuild test -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ticTests/DragSessionGeometryTests -only-testing:ticTests/DragSessionEngineTests
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/5-swift-drag-port/index.json`의 phase 1 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- 이 phase에서는 `ContentView`, `DayView`, `TimelineView`, `MonthView`, `YearView`의 동작을 바꾸지 마라.
- geometry 함수 안에서 `UIScreen.main.bounds`를 직접 읽지 마라. 필요한 frame은 모두 입력으로 받아라.
- `Calendar.current`를 하드코딩하더라도 테스트에서 주입 가능해야 한다.
- drag 파라미터 기본값은 `experiments/draglab/configs/baseline.json` 의미와 맞아야 한다.
