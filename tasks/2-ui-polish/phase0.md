# Phase 0: live-activity-redesign

## 사전 준비

아래 파일들을 반드시 읽고 현재 구현을 이해하라:

- `/ticWidgets/TicLiveActivityView.swift` — 현재 Live Activity + Dynamic Island UI
- `/ticWidgets/WidgetIntents.swift` — CompleteEventIntent, SnoozeEventIntent
- `/tic/Models/TicActivityAttributes.swift` — ActivityAttributes
- `/docs/prd.md` — Live Activity 섹션

## 작업 내용

Live Activity 잠금화면과 Dynamic Island Expanded UI를 항공편 앱(Flighty/AirJet) 스타일로 리디자인한다. **시각적 여정(visual journey)** 패턴 적용.

### 1. 잠금화면 Live Activity — 리디자인

기존 단순 리스트 레이아웃을 **시각적 여정 레이아웃**으로 변경:

```
┌──────────────────────────────────────────┐
│ tic                        팀 미팅        │
│                                          │
│  09:00  ●━━━━━━━⏱━━━○  10:00           │
│                                          │
│  시작됨 09:00          30분 남음          │
│                                          │
│  ┌──────────┐    ┌────────────────────┐  │
│  │   완료   │    │   10분 후 알림     │  │
│  └──────────┘    └────────────────────┘  │
└──────────────────────────────────────────┘
```

구현 규칙:
- **상단**: "tic" 로고(좌, 오렌지, 작은 폰트) + 일정 제목(우, 큰 폰트)
- **중앙 (핵심)**: 시작 시간(좌, 큰 볼드) + 프로그레스 라인 + 시계 아이콘(진행 위치) + 종료 시간(우, 큰 볼드)
  - 프로그레스 라인: 진행된 부분 = 오렌지 실선, 남은 부분 = 회색 점선
  - 시계 아이콘: `Image(systemName: "clock.fill")` 오렌지, 현재 진행 위치에 배치
  - 시작/종료 시간: `.system(size: 28, weight: .bold, design: .rounded)` + monospacedDigit
- **하단 상태**: "시작됨 HH:mm"(좌, 회색) + "N분 남음"(우, 오렌지)
- **버튼**: 둥근 배경 스타일 유지. "완료" = 오렌지 20% 배경, "10분 후 알림" = 회색 배경
- 배경: `.activityBackgroundTint(.black.opacity(0.8))`

### 2. Dynamic Island Expanded — 리디자인

Flighty 스타일:

```
┌──────────────────────────────────────┐
│ 팀 미팅                    ⏱ tic    │
│                                      │
│ 09:00 ●━━━━━⏱━━━○ 10:00            │
│                                      │
│ 🟠 진행 중                           │
│ 30분 남음                            │
└──────────────────────────────────────┘
```

구현 규칙:
- **leading**: 일정 제목 (큰 폰트, 볼드)
- **trailing**: 시계 아이콘 + "tic" (작은 폰트)
- **bottom**:
  - 시작 시간(좌, 볼드) + 프로그레스 라인(중앙, 오렌지→회색 점선) + 종료 시간(우, 볼드)
  - 프로그레스 라인 위에 시계 아이콘 (현재 위치)
  - 상태: "진행 중" (오렌지) + "N분 남음"
- 버튼은 expanded에서 제거 (공간 부족, 잠금화면에서 사용)

### 3. Dynamic Island Compact — 유지

현재 구현 유지:
- Leading: 오렌지 점 + 제목
- Trailing: 남은 시간 (오렌지, rounded)

### 4. Dynamic Island Minimal — 유지

현재 구현 유지:
- 원형 프로그레스 (오렌지 stroke)

### 5. 프로그레스 라인 컴포넌트

공통 컴포넌트로 추출:

```swift
struct JourneyProgressView: View {
    let startDate: Date
    let endDate: Date
    let showTimes: Bool  // true = 시작/종료 시간 표시
    let height: CGFloat  // 라인 높이
    
    // 진행 부분: 오렌지 실선
    // 미진행 부분: 회색 점선 (StrokeStyle dash)
    // 진행 위치: 시계 아이콘 (clock.fill)
}
```

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodegen generate && xcodebuild build -project tic.xcodeproj -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -1 | grep -q "BUILD SUCCEEDED"
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/2-ui-polish/index.json`의 phase 0 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- `Button(intent:)` 구문 유지. App Intents 연동 깨뜨리지 마라.
- 프로그레스 라인의 시계 아이콘 위치는 `GeometryReader`로 계산. 진행률에 따라 x 좌표 결정.
- 잠금화면과 Dynamic Island에서 동일한 `JourneyProgressView` 컴포넌트를 공유하라.
- `.activityBackgroundTint`은 잠금화면에만 적용. Dynamic Island는 시스템 배경.
- 시뮬레이터 이름이 `iPhone 16`이 아닐 수 있다. `xcrun simctl list devices available`로 확인하고 적절히 조정하라.
