# Phase 2: day-overlay-session

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
- `ticTests/DragSessionGeometryTests.swift`
- `ticTests/DragSessionEngineTests.swift`

아래 현재 UI 파일들도 다시 읽어라:

- `tic/Views/ContentView.swift`
- `tic/Views/Calendar/DayView.swift`
- `tic/Views/Components/TimelineView.swift`
- `tic/Views/Components/EditableEventBlock.swift`

## 작업 내용

이번 phase의 목적은 **day timeline 안에서 root overlay 기반 drag session을 실제로 연결**하는 것이다. month/year hover는 아직 붙이지 마라.

### 1. `CalendarDragCoordinator` 추가

`tic/DragSession/CalendarDragCoordinator.swift`를 추가하라.

책임:

- `DragSessionEngine` 인스턴스 보유
- 현재 overlay 표시용 snapshot/placeholder 상태 보유
- day timeline frame과 pointer global 위치 입력 받기
- session 시작, move, drop, cancel을 SwiftUI에서 쓰기 쉬운 API로 감싼다

규칙:

- coordinator는 `@Observable`이어야 한다.
- session owner는 root scope 위 하나만 존재해야 한다.
- EventKit write는 아직 coordinator 안에서 하지 마라. 우선 candidate 계산과 UI 상태만 만든다.

### 2. `ContentView`에 root overlay host 추가

`ContentView.swift`를 수정하라.

- `@State`로 `CalendarDragCoordinator`를 소유한다.
- `scopeView` 위에 root overlay를 렌더링한다.
- `DayView`에 coordinator를 주입한다.
- overlay는 current scope 교체 중에도 사라지지 않아야 한다.

### 3. `DayView`와 `TimelineView` 연결

아래를 구현하라.

- day timeline global frame을 coordinator에 보고
- 편집 중인 블록을 drag session source로 시작
- drag 중 원본 블록은 ghost/placeholder처럼 남긴다
- 실제 이동 블록은 root overlay에서만 렌더링한다
- 같은 날 timeline 안에서 move 중 minute candidate가 계속 갱신된다

기존 `pendingEditingDates`는 유지하되, drag session 동안은 overlay candidate 기반으로만 화면을 갱신하라.

### 4. `EditableEventBlock` 리팩터링

`EditableEventBlock.swift`에서 move gesture 경로를 분리하라.

- resize top/bottom은 기존 로컬 제스처를 유지한다.
- move gesture는 local frame offset으로 최종 확정하지 말고 coordinator로 이벤트를 전달한다.
- drag 시작 전 visual continuity가 깨지지 않도록, overlay 첫 frame은 원본 블록 frame과 정확히 맞춰라.

### 5. 순수 로직 테스트 보강

새 순수 로직이 생기면 해당 테스트를 같은 phase에서 추가하라.

예시:

- placeholder visible 조건
- overlay initial frame continuity
- timeline frame 변경 후 minute candidate 재계산

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodegen generate && xcodebuild test -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16'
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/5-swift-drag-port/index.json`의 phase 2 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- 이 phase에서는 month/year 날짜 셀 hover를 붙이지 마라.
- 기존 resize 기능과 delete/duplicate toolbar를 깨뜨리지 마라.
- drag 시작 직후 overlay가 튀거나 크기가 바뀌면 안 된다. source frame continuity를 우선하라.
- 기존 edge-hover timer 기반 cross-day 처리 로직은 아직 완전히 제거하지 마라. phase 4에서 정리한다.
