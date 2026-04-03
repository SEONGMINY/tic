# Phase 6: live-activity

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `/docs/prd.md` — Live Activity 섹션
- `/docs/flow.md` — F9 (Live Activity), F11 (알림 액션)
- `/docs/data-schema.md` — TicActivityAttributes
- `/docs/adr.md` — ADR-007 (로컬 알림 + 사용자 탭으로 LA 시작)

그리고 이전 phase의 작업물을 반드시 확인하라:

- `/tic/Services/EventKitService.swift` — fetchAllItems
- `/tic/Services/NotificationService.swift` — schedule, scheduleSnooze
- `/tic/Models/TicItem.swift`
- `/tic/ticApp.swift` — 앱 진입점
- `/tic/Views/ContentView.swift`
- `project.yml` — 타겟 설정 (NSSupportsLiveActivities)
- `/ticWidgets/` — Widget Extension 구조

이전 phase에서 만들어진 코드를 꼼꼼히 읽고, 설계 의도를 이해한 뒤 작업하라.

## 작업 내용

Live Activity (잠금화면 + Dynamic Island)를 구현한다. ActivityKit을 사용.

### 1. `/tic/Services/LiveActivityService.swift`

```swift
import ActivityKit

@Observable
class LiveActivityService {
    private var currentActivity: Activity<TicActivityAttributes>?
    
    func start(for item: TicItem) throws
    func update(for item: TicItem)
    func end(for identifier: String)
    func endAll()
    func transition(to next: TicItem) throws  // 현재 종료 → 다음 시작
    
    var isActivityActive: Bool { currentActivity != nil }
}
```

핵심 규칙:
- `start`: `Activity.request(attributes:content:pushType:nil)` 호출. pushType은 nil (로컬 전용, 서버 없음).
- `update`: `currentActivity?.update(using:)` 으로 ContentState 업데이트.
- `end`: `currentActivity?.end(using:content:dismissalPolicy:.immediate)`.
- `transition`: end(현재) → start(다음) 연속 호출.
- `TicActivityAttributes`는 ActivityAttributes 프로토콜 준수.

### 2. TicActivityAttributes 정의

이 구조체는 **메인 앱과 Widget Extension 양쪽에서 사용**해야 하므로, 공유 가능한 위치에 놓아야 한다.

방법: `/tic/Models/TicActivityAttributes.swift` 에 정의하고, project.yml에서 이 파일을 **양쪽 타겟의 sources에 포함**시키라.

```swift
import ActivityKit

struct TicActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var startDate: Date
        var endDate: Date
        var isReminder: Bool
        var calendarColorHex: String
    }
    var eventIdentifier: String
}
```

### 3. Live Activity UI — Widget Extension 내 구현

`/ticWidgets/TicLiveActivityView.swift`:

```swift
import WidgetKit
import SwiftUI
import ActivityKit

struct TicLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TicActivityAttributes.self) { context in
            // 잠금화면 UI
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded
                DynamicIslandExpandedRegion(.leading) { ... }
                DynamicIslandExpandedRegion(.trailing) { ... }
                DynamicIslandExpandedRegion(.center) { ... }
                DynamicIslandExpandedRegion(.bottom) { ... }
            } compactLeading: {
                // Compact leading
            } compactTrailing: {
                // Compact trailing
            } minimal: {
                // Minimal
            }
        }
    }
}
```

잠금화면 UI 디자인:
- 배경: 무채색 (시스템 기본)
- 상단: "tic" 로고 텍스트 (좌) + 시간 범위 (우)
- 중앙: 일정 제목 (큰 폰트)
- 하단: [완료] [10분 후 알림] 버튼 2개
  - 버튼은 `Button(intent:)` 사용 — App Intents 연동 (Phase 7에서 완성)
  - 이 phase에서는 버튼 UI만 만들고, intent 연결은 placeholder

Dynamic Island 디자인:
- Compact: 좌 = "tic" 또는 오렌지 원, 우 = 일정 제목 (truncated)
- Expanded: 일정 제목 + 시간 + 완료/스누즈 버튼
- Minimal: 오렌지 원

### 4. TicWidgetBundle 업데이트

`/ticWidgets/TicWidgetBundle.swift`에 TicLiveActivity를 추가:

```swift
@main
struct TicWidgetBundle: WidgetBundle {
    var body: some Widget {
        TicLiveActivity()
        // SmallWidget, MediumWidget은 Phase 7에서 추가
    }
}
```

### 5. 알림 탭 → Live Activity 시작 연동

ticApp.swift에서 알림 탭 처리:

```swift
@main
struct ticApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    // 딥링크 처리 (위젯 → 앱)
                }
        }
        .modelContainer(for: [...])
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions ...) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, 
                                didReceive response: UNNotificationResponse) async {
        let identifier = response.notification.request.identifier
        switch response.actionIdentifier {
        case "COMPLETE_ACTION":
            // EventKitService.complete() 호출
            break
        case "SNOOZE_ACTION":
            // NotificationService.scheduleSnooze() 호출
            break
        default:
            // 알림 탭 → Live Activity 시작
            // identifier로 EventKit에서 해당 일정 찾기 → LiveActivityService.start()
            break
        }
    }
}
```

### 6. 포그라운드 자동 시작

ContentView 또는 DayView에서:
- 앱이 포그라운드에 있을 때, 다음 일정 30분 전이 되면 자동으로 Live Activity 시작.
- Timer 또는 `.onReceive(Timer.publish(every: 60, ...))`로 매분 체크.
- 이미 활성 Live Activity가 있으면 중복 시작하지 않음.
- 일정 종료 시간이 되면 자동 종료.
- 다음 일정이 30분 이내면 즉시 전환.

### 7. project.yml 업데이트

Widget Extension 타겟에 `TicActivityAttributes.swift`가 포함되어야 한다:
- 메인 앱 sources에 `/tic/Models/TicActivityAttributes.swift` 포함
- Widget Extension sources에도 같은 파일 포함

```yaml
ticWidgets:
  sources:
    - path: ticWidgets
    - path: tic/Models/TicActivityAttributes.swift
```

### 8. xcodegen 재생성

`xcodegen generate` 실행.

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodegen generate && xcodebuild build -project tic.xcodeproj -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -1 | grep -q "BUILD SUCCEEDED"
```

Widget Extension도 빌드:
```bash
cd /Users/leesm/work/side/tic && xcodebuild build -project tic.xcodeproj -scheme ticWidgets -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -1 | grep -q "BUILD SUCCEEDED"
```

두 빌드 모두 성공해야 AC 통과.

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/0-tic-mvp/index.json`의 phase 6 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.
작업 중 사용자 개입이 반드시 필요한 상황이 발생하면 status를 `"blocked"`로, `"blocked_reason"` 필드에 사유를 기록하고 작업을 즉시 중단하라.

## 주의사항

- ActivityKit은 시뮬레이터에서 제한적으로 동작한다. 빌드만 성공하면 AC 통과.
- `TicActivityAttributes`를 양쪽 타겟에서 공유할 때 "duplicate symbol" 에러가 나면, 별도 shared framework를 만들어라. 하지만 우선은 양쪽 sources에 같은 파일 포함하는 방식으로 시도.
- `@UIApplicationDelegateAdaptor`를 사용하면 SwiftUI 앱에서도 AppDelegate를 쓸 수 있다.
- Live Activity 버튼에 `Button(intent:)` 사용 시 App Intents가 필요. Phase 7에서 완성하므로, 이 phase에서는 intent 없는 일반 Button으로 placeholder 처리해도 됨.
- Widget Extension에 `@main`이 있는데 TicWidgetBundle에 아무 Widget도 없으면 빌드 에러. 반드시 TicLiveActivity를 body에 포함시키라.
- 시뮬레이터 이름이 `iPhone 16`이 아닐 수 있다. `xcrun simctl list devices available`로 확인하고 적절히 조정하라.
