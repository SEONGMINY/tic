# Phase 1: widget-redesign

## 사전 준비

아래 파일들을 반드시 읽고 현재 구현을 이해하라:

- `/ticWidgets/SmallWidget.swift` — 현재 Small 위젯
- `/ticWidgets/MediumWidget.swift` — 현재 Medium 위젯 (수정 대상)
- `/ticWidgets/WidgetProvider.swift` — TimelineProvider
- `/ticWidgets/WidgetIntents.swift` — App Intents
- `/tic/Models/WidgetData.swift` — WidgetEventItem, WidgetCache
- `/docs/prd.md` — 위젯 섹션

이전 phase의 작업물도 확인하라:
- `/ticWidgets/TicLiveActivityView.swift` — Live Activity가 변경됨

## 작업 내용

Medium 위젯을 **캘린더 + 이벤트 리스트** 레이아웃으로 리디자인한다.

### 1. Medium 위젯 리디자인

레퍼런스 이미지 기반 레이아웃:

```
┌──────────────────────────────────────────────┐
│                                              │
│  🔴 House Payment        일 월 화 수 목 금 토 │
│     09/01 - 12:00 AM              1  2  3  4 │
│  🟢 Discover Card        5  6  7  8  9 10 11 │
│     09/02 - 12:00 AM    12 13 14 15 16 17 18 │
│  🔵 Labor Day           19 20 21 22 23 24 25 │
│     09/04 - 12:00 AM    26 27 28 29 ③ 31  1 │
│  🟡 Pay Day                                  │
│     09/08 - 12:00 AM                         │
│                                              │
└──────────────────────────────────────────────┘
```

구현 규칙:
- **좌측 (약 55%)**: 이벤트 리스트
  - 각 항목: 캘린더 색상 점(●) + 제목 + 날짜/시간 (작은 폰트, 회색)
  - 최대 4개 표시
  - 초과 시 "+N개 더" 표시
- **우측 (약 45%)**: 미니 월간 캘린더
  - 요일 헤더: 일 월 화 수 목 금 토 (매우 작은 폰트)
  - 날짜 숫자 (작은 폰트)
  - 오늘 날짜: 오렌지 원으로 하이라이트
  - 이벤트 있는 날: 숫자 아래 작은 점 (또는 볼드)
- `.containerBackground(.fill.tertiary, for: .widget)` 유지
- `.widgetURL` 유지 (딥링크)

### 2. 미니 캘린더 구현

위젯 내부에 미니 캘린더를 그리기 위해 **정적 날짜 계산** 사용 (EventKit 접근 불필요):

```swift
struct MiniCalendarView: View {
    let currentDate: Date
    let eventDates: Set<String>  // "yyyy-MM-dd" 형태
    
    // 7열 그리드로 이번 달 렌더링
    // 오늘 = 오렌지 원
    // 이벤트 있는 날 = 볼드 또는 점
}
```

`eventDates`는 `WidgetCache.load()`에서 가져온 이벤트의 `startDate`를 "yyyy-MM-dd" 문자열로 변환하여 Set으로 관리.

### 3. Small 위젯

Small 위젯은 현재 디자인 유지. 변경 없음.

### 4. WidgetProvider 수정

현재 `TicWidgetEntry`에 이벤트 날짜 Set을 추가:

```swift
struct TicWidgetEntry: TimelineEntry {
    let date: Date
    let events: [WidgetEventItem]
    let eventDateStrings: Set<String>  // 미니 캘린더용
}
```

Provider에서 `getTimeline` 시 이벤트 날짜를 Set으로 변환하여 전달.

## Acceptance Criteria

메인 앱 빌드:
```bash
cd /Users/leesm/work/side/tic && xcodegen generate && xcodebuild build -project tic.xcodeproj -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -1 | grep -q "BUILD SUCCEEDED"
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/2-ui-polish/index.json`의 phase 1 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- `.containerBackground(.fill.tertiary, for: .widget)` 필수 (iOS 17).
- 위젯에서 `Calendar` 연산은 동기적이므로 성능 이슈 없음.
- 미니 캘린더의 날짜 그리드가 위젯 크기에 맞게 잘 보이도록 폰트 크기 조정 (6-8pt 권장).
- 기존 `SmallWidget`, `TicWidgetBundle`을 깨뜨리지 마라.
- `Color(hex:)` extension이 MediumWidget.swift에 이미 있는지 확인. 없으면 추가.
- 시뮬레이터 이름이 `iPhone 16`이 아닐 수 있다. `xcrun simctl list devices available`로 확인하고 적절히 조정하라.
