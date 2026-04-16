# Phase 3: scope-transition-and-pill

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
- `tasks/7-timeline-block-animation/phase2.md`
- `tic/Views/ContentView.swift`
- `tic/Views/Calendar/MonthView.swift`
- `tic/Views/Calendar/YearView.swift`
- `tic/Views/Components/DragSessionOverlayBlock.swift`
- `tic/DragSession/CalendarDragCoordinator.swift`
- `tic/ViewModels/CalendarScopeTransition.swift`
- `ticTests/CalendarScopeTransitionTests.swift`
- `ticTests/CalendarDragCoordinatorTests.swift`

## 작업 내용

이번 phase의 목적은 **day timeline의 floating card가 month/year 전환 중에도 같은 객체로 느껴지도록 연결하고, anonymous capsule로 안정적으로 압축하는 것**이다.

### 1. scope transition 연결감 구현

영상과 문서 계약을 기준으로 아래를 구현하라.

- scope 전환이 시작된 직후에는 full `timelineCard`가 아주 잠깐 유지되어야 한다.
- 그 다음 `calendarPill`로 압축되며, 사용자는 같은 블록이 다른 캘린더 밀도로 들어간다고 느껴야 한다.
- 전환 입력과 실제 scope animation 사이의 짧은 간격을 presentation phase로 표현하라.
- 권장값은 full card hold 0.08초 ~ 0.12초, capsule 압축 0.12초 ~ 0.20초다.

### 2. `selectedDate` / `activeDate` 역할 분리 구현

아래 규칙을 코드에 정확히 반영하라.

- month/year hover 중에는 `selectedDate`를 바꾸지 마라.
- month/year에서 강조되는 날짜는 `activeDate` 하나뿐이다.
- active target highlight는 진한 배경 또는 동등한 방식으로 분명히 보여야 한다.
- scope 전환 중에도 `single active target` 계약을 유지하라.

### 3. 익명 capsule 규칙 구현

`calendarPill`은 아래 규칙을 만족해야 한다.

- 제목 텍스트, resize handle, toolbar가 없다.
- month와 year에서 pill 길이는 동일하다.
- 위치만 달라지고 길이는 유지되어야 같은 객체 감각이 산다.
- pill 이동은 점프보다 연속 이동처럼 느껴져야 한다.

### 4. hover 안정화 정책 추가

month와 year의 grid 밀도가 다르므로 hover 판단을 분리하라.

- month는 일반적인 enter/exit hysteresis로 충분하다.
- year는 더 보수적인 안정화가 필요하다.
- dwell time, distance threshold, enter/exit threshold 중 적절한 방법을 선택하되 순수 helper로 분리하고 테스트하라.
- year에서 highlight가 과도하게 튀지 않도록 하라.

### 5. 테스트 보강

최소 아래 시나리오를 XCTest로 검증하라.

- scope transition 중 full card hold 후 capsule phase로 넘어간다.
- month/year hover 중 `selectedDate`는 바뀌지 않고 `activeDate`만 갱신된다.
- capsule 길이는 month와 year에서 동일한 presentation 값으로 계산된다.
- year hover 안정화 정책이 month보다 더 보수적으로 동작한다.
- active target이 없으면 pill이 잘못된 날짜에 붙지 않는다.

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodegen generate && xcodebuild test -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' -only-testing:ticTests CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/7-timeline-block-animation/index.json`의 phase 3 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- hover 중 `selectedDate`를 바꾸지 마라.
- month/year에서 pill 길이를 scope마다 다르게 만들지 마라.
- scope 전환 때 두 개의 블록이 동시에 보이는 split-brain 상태를 만들지 마라.
- pointer 추적과 hover stabilization이 서로 싸우지 않게 순수 helper와 UI animation 책임을 분리하라.
