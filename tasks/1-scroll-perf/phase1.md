# Phase 1: day-slide-animation

## 사전 준비

아래 파일들을 반드시 읽고 현재 구현을 이해하라:

- `/tic/Views/Calendar/DayView.swift` — 일간 뷰 (수정 대상)
- `/tic/Views/Components/TimelineView.swift` — 타임라인 뷰
- `/tic/ViewModels/CalendarViewModel.swift` — selectedDate
- `/docs/flow.md` — F3: 일간 뷰 흐름

이전 phase의 작업물도 확인하라:
- MonthView, YearView가 변경되었을 수 있음

## 작업 내용

DayView에서 날짜 전환 시 Slide In / Slide Out 애니메이션을 구현한다.

### 1. 주간 스트립 스와이프 시 슬라이드

주간 스트립을 좌우 스와이프하면 1주 단위로 전환되는데, 이때 아래 타임라인 영역이 슬라이드 애니메이션으로 전환되어야 한다.

- 오른쪽 스와이프 (이전 주): 타임라인이 **오른쪽에서 현재 위치로** 슬라이드 인, 기존은 **왼쪽으로** 슬라이드 아웃
- 왼쪽 스와이프 (다음 주): 반대 방향

### 2. 타임라인 영역 스와이프 시 슬라이드

타임라인 영역에서 좌우 스와이프로 ±1일 이동 시에도 동일한 슬라이드 애니메이션 적용.

### 3. 주간 스트립 날짜 탭 시

주간 스트립에서 다른 날짜를 탭할 때도 슬라이드 방향을 판단하여 애니메이션 적용:
- 현재 날짜보다 미래 → 좌로 슬라이드
- 현재 날짜보다 과거 → 우로 슬라이드

### 구현 방법

```swift
@State private var slideDirection: Edge = .trailing
@State private var contentId = UUID()

// 타임라인 영역에 적용
VStack { ... }
    .id(contentId)
    .transition(.asymmetric(
        insertion: .move(edge: slideDirection),
        removal: .move(edge: slideDirection == .trailing ? .leading : .trailing)
    ))

// 날짜 변경 시
func changeDate(to newDate: Date) {
    slideDirection = newDate > viewModel.selectedDate ? .trailing : .leading
    withAnimation(.easeInOut(duration: 0.25)) {
        contentId = UUID()
        viewModel.selectedDate = newDate
    }
}
```

### 4. 주간 스트립 선택 인디케이터

선택된 날짜의 오렌지 원이 `matchedGeometryEffect`로 부드럽게 이동하도록 유지.

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodegen generate && xcodebuild build -project tic.xcodeproj -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -1 | grep -q "BUILD SUCCEEDED"
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/1-scroll-perf/index.json`의 phase 1 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- DayView의 기존 기능 (FAB, ActionListSheet, context menu, 일정 수정 등)을 유지하라.
- `DragGesture`와 타임라인 내부 `ScrollView`의 충돌 주의. 가로 스와이프만 날짜 이동, 세로 스크롤은 타임라인 스크롤.
- `minimumDistance`를 적절히 설정하여 의도치 않은 날짜 전환 방지 (60pt 권장).
- 시뮬레이터 이름이 `iPhone 16`이 아닐 수 있다. `xcrun simctl list devices available`로 확인하고 적절히 조정하라.
