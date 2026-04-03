# Phase 2: dynamic-island-verify

## 사전 준비

아래 파일들을 반드시 읽고 현재 구현을 이해하라:

- `/ticWidgets/TicLiveActivityView.swift` — Live Activity + Dynamic Island UI
- `/ticWidgets/WidgetIntents.swift` — CompleteEventIntent, SnoozeEventIntent
- `/tic/Services/LiveActivityService.swift` — ActivityKit 관리
- `/tic/Models/TicActivityAttributes.swift` — ActivityAttributes 정의
- `/docs/prd.md` — Live Activity 섹션
- `/docs/adr.md` — ADR-007

## 작업 내용

Dynamic Island의 compact / expanded / minimal이 정상 동작하는지 검증하고, 필요하면 수정한다.

### 1. 코드 검증

현재 `TicLiveActivity` Widget의 `ActivityConfiguration` 내부에 `DynamicIsland` 블록이 있어야 한다:
- `DynamicIslandExpandedRegion(.leading)` — 제목
- `DynamicIslandExpandedRegion(.trailing)` — 남은 시간
- `DynamicIslandExpandedRegion(.bottom)` — 프로그레스 바 + 시간 + 버튼
- `compactLeading` — 오렌지 점 + 제목
- `compactTrailing` — 남은 시간
- `minimal` — 원형 프로그레스

이 구조가 올바른지 확인하고, 누락된 부분이 있으면 보완하라.

### 2. TicWidgetBundle 확인

`TicWidgetBundle`의 body에 `TicLiveActivity()`가 포함되어 있는지 확인.

### 3. Info.plist 확인

메인 앱의 Info.plist에 `NSSupportsLiveActivities: true`가 있는지 확인.

### 4. ActivityAttributes 공유 확인

`TicActivityAttributes.swift`가 메인 앱과 Widget Extension 양쪽 타겟에 포함되어 있는지 project.yml에서 확인.

### 5. 잠금화면 Live Activity UI 검증

`LockScreenView`에 다음이 포함되어야 한다:
- tic 로고 + 남은 시간
- 일정 제목
- 프로그레스 바 (시작~종료 진행률)
- 시작/종료 시간 레이블
- 완료 버튼 (둥근 배경, 오렌지)
- 10분 후 알림 버튼 (둥근 배경, 회색)

### 6. Intent 동작 검증

- `CompleteEventIntent`: 리마인더 완료 + Live Activity 종료 + 위젯 갱신
- `SnoozeEventIntent`: 10분 알림 등록 + Live Activity 유지 + 위젯 갱신

두 Intent 모두 `ActivityKit` import가 있고, `Activity<TicActivityAttributes>.activities`를 순회하여 해당 activity를 종료/업데이트하는 코드가 있는지 확인.

## Acceptance Criteria

메인 앱 빌드:
```bash
cd /Users/leesm/work/side/tic && xcodegen generate && xcodebuild build -project tic.xcodeproj -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -1 | grep -q "BUILD SUCCEEDED"
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/1-scroll-perf/index.json`의 phase 2 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- Dynamic Island는 실기기에서만 완전히 테스트 가능. 시뮬레이터에서는 빌드 성공만 확인.
- iOS의 Dynamic Island 동작: compact가 기본 표시, 꾹 누르면 expanded, 다른 LA 동시 실행 시 minimal.
- Widget Extension 내 코드에서 `import ActivityKit`이 필요.
- `Button(intent:)` 구문은 iOS 17+ Interactive Widget에서만 동작.
- 기존 코드를 불필요하게 변경하지 마라. 검증 후 문제 있는 부분만 수정.
- 시뮬레이터 이름이 `iPhone 16`이 아닐 수 있다. `xcrun simctl list devices available`로 확인하고 적절히 조정하라.
