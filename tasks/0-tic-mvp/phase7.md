# Phase 7: widgets

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `/docs/prd.md` — 위젯 섹션 (Small/Medium, 인터랙션, 딥링크)
- `/docs/flow.md` — F10 (위젯 인터랙션)
- `/docs/data-schema.md` — 위젯 데이터 공유 (App Group UserDefaults)
- `/docs/code-architecture.md` — App Intents, 딥링킹
- `/docs/adr.md` — ADR-010 (App Group UserDefaults)

그리고 이전 phase의 작업물을 반드시 확인하라:

- `/ticWidgets/TicWidgetBundle.swift` — Widget Bundle (TicLiveActivity 이미 포함)
- `/ticWidgets/TicLiveActivityView.swift` — Live Activity UI
- `/tic/Models/TicActivityAttributes.swift` — 공유 모델
- `/tic/Services/EventKitService.swift` — fetch 메서드들
- `/tic/Services/LiveActivityService.swift`
- `/tic/ticApp.swift` — 딥링크 처리 (.onOpenURL)
- `project.yml` — 타겟 설정, App Group

이전 phase에서 만들어진 코드를 꼼꼼히 읽고, 설계 의도를 이해한 뒤 작업하라.

## 작업 내용

Small/Medium 위젯과 App Intents (완료/스누즈), App Group 캐시, 딥링크를 구현한다.

### 1. App Group 캐시 모델

메인 앱과 위젯이 공유하는 데이터 구조. **양쪽 타겟에 포함되어야 한다.**

`/tic/Models/WidgetData.swift` (메인 앱 + Widget Extension 양쪽 sources에 포함):

```swift
import Foundation

struct WidgetEventItem: Codable {
    let id: String
    let title: String
    let startDate: Date?
    let endDate: Date?
    let isReminder: Bool
    let isCompleted: Bool
    let calendarColorHex: String
    let isAllDay: Bool
}

struct WidgetCache {
    static let suiteName = "group.com.tic.app"
    static let cacheKey = "widgetEventCache"
    
    static func save(events: [WidgetEventItem]) { ... }  // UserDefaults에 JSON 저장
    static func load() -> [WidgetEventItem] { ... }       // UserDefaults에서 JSON 로드
}
```

핵심 규칙:
- `UserDefaults(suiteName: "group.com.tic.app")` 사용. 일반 UserDefaults가 아님.
- 캐시에 저장할 이벤트: 오늘부터 미래 7일간의 일정. 최대 20개.
- `calendarColorHex`: CGColor → hex string 변환하여 저장. Codable을 위해.

### 2. EventKitService에 캐시 업데이트 연동

EventKitService에서 이벤트가 변경될 때마다 (create/update/delete/complete + EKEventStoreChanged) 위젯 캐시를 업데이트하라:

```swift
func updateWidgetCache() {
    let events = fetchEvents(from: .now, to: Date().adding(days: 7))
    let widgetItems = events.map { WidgetEventItem(from: $0) }
    WidgetCache.save(events: widgetItems)
    WidgetCenter.shared.reloadAllTimelines()
}
```

### 3. `/ticWidgets/WidgetProvider.swift`

```swift
import WidgetKit

struct TicWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TicWidgetEntry { ... }
    func getSnapshot(in context: Context, completion: @escaping (TicWidgetEntry) -> Void) { ... }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TicWidgetEntry>) -> Void) {
        let events = WidgetCache.load()
        let entry = TicWidgetEntry(date: .now, events: events)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct TicWidgetEntry: TimelineEntry {
    let date: Date
    let events: [WidgetEventItem]
}
```

### 4. `/ticWidgets/SmallWidget.swift`

다음 일정 1개 표시.

```swift
struct SmallTicWidget: Widget {
    let kind: String = "SmallTicWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TicWidgetProvider()) { entry in
            SmallWidgetView(entry: entry)
        }
        .configurationDisplayName("tic")
        .description("다음 일정을 확인하세요")
        .supportedFamilies([.systemSmall])
    }
}

struct SmallWidgetView: View {
    var entry: TicWidgetEntry
    // 다음 일정 1개: 제목 + 시간
    // 탭 → 딥링크 (widgetURL)
    // 완료 버튼 (Intent)
}
```

디자인:
- 배경: 시스템 위젯 배경
- 상단: "tic" 작은 로고
- 중앙: 일정 제목 (2줄까지)
- 하단: 시간 (HH:mm) + 완료 버튼
- 일정 없으면: "예정된 일정이 없습니다"
- `.widgetURL(URL(string: "tic://day?date=\(dateString)")!)` 로 딥링크

### 5. `/ticWidgets/MediumWidget.swift`

다음 3-4개 일정 표시.

```swift
struct MediumTicWidget: Widget {
    let kind: String = "MediumTicWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TicWidgetProvider()) { entry in
            MediumWidgetView(entry: entry)
        }
        .configurationDisplayName("tic")
        .description("오늘의 일정을 한눈에")
        .supportedFamilies([.systemMedium])
    }
}

struct MediumWidgetView: View {
    var entry: TicWidgetEntry
    // 상단: "tic" + 날짜
    // 리스트: 최대 4개 일정 (색상 점 + 시간 + 제목)
    // 4개 초과: "+N개 더" 표시
    // 각 항목에 완료 버튼 (Intent)
}
```

### 6. `/ticWidgets/WidgetIntents.swift`

App Intents for Interactive Widget.

```swift
import AppIntents

struct CompleteEventIntent: AppIntent {
    static var title: LocalizedStringResource = "완료"
    
    @Parameter(title: "Event ID")
    var eventIdentifier: String
    
    init() {}
    init(eventIdentifier: String) {
        self.eventIdentifier = eventIdentifier
    }
    
    func perform() async throws -> some IntentResult {
        let store = EKEventStore()
        // EventKit에서 identifier로 이벤트/리마인더 찾기
        // 리마인더면 isCompleted = true로 설정
        // 위젯 캐시 업데이트
        // WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct SnoozeEventIntent: AppIntent {
    static var title: LocalizedStringResource = "10분 후 알림"
    
    @Parameter(title: "Event ID")
    var eventIdentifier: String
    
    init() {}
    init(eventIdentifier: String) {
        self.eventIdentifier = eventIdentifier
    }
    
    func perform() async throws -> some IntentResult {
        // UNUserNotificationCenter로 10분 후 알림 스케줄
        // WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
```

핵심 규칙:
- `@Parameter`에는 반드시 기본 init()이 필요 (AppIntents 요구사항).
- Widget Extension 내에서 EventKit 접근 가능 (같은 App Group + 권한).
- Intent 실행 후 `WidgetCenter.shared.reloadAllTimelines()` 호출하여 위젯 갱신.

### 7. Live Activity 버튼에 Intent 연결

Phase 6에서 placeholder로 둔 Live Activity 버튼을 실제 Intent로 교체:

```swift
// TicLiveActivityView.swift 내
Button(intent: CompleteEventIntent(eventIdentifier: context.attributes.eventIdentifier)) {
    Text("완료")
}
Button(intent: SnoozeEventIntent(eventIdentifier: context.attributes.eventIdentifier)) {
    Text("10분 후")
}
```

### 8. TicWidgetBundle 업데이트

```swift
@main
struct TicWidgetBundle: WidgetBundle {
    var body: some Widget {
        TicLiveActivity()
        SmallTicWidget()
        MediumTicWidget()
    }
}
```

### 9. 딥링크 처리 (ticApp.swift)

```swift
.onOpenURL { url in
    // tic://day?date=2026-04-16
    guard url.scheme == "tic", url.host == "day" else { return }
    if let dateString = URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?.first(where: { $0.name == "date" })?.value,
       let date = ISO8601DateFormatter().date(from: dateString) {
        // calendarViewModel.selectedDate = date
        // calendarViewModel.scope = .day
    }
}
```

날짜 포맷: `yyyy-MM-dd` (예: `2026-04-16`). ISO8601이 아닌 간단한 포맷 사용. `DateFormatter`로 파싱.

### 10. project.yml 업데이트

Widget Extension sources에 공유 파일 추가:
- `tic/Models/TicActivityAttributes.swift`
- `tic/Models/WidgetData.swift`

### 11. xcodegen 재생성

`xcodegen generate` 실행.

## Acceptance Criteria

메인 앱 빌드:
```bash
cd /Users/leesm/work/side/tic && xcodegen generate && xcodebuild build -project tic.xcodeproj -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -1 | grep -q "BUILD SUCCEEDED"
```

Widget Extension 빌드:
```bash
cd /Users/leesm/work/side/tic && xcodebuild build -project tic.xcodeproj -scheme ticWidgets -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -1 | grep -q "BUILD SUCCEEDED"
```

두 빌드 모두 성공해야 AC 통과.

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/0-tic-mvp/index.json`의 phase 7 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.
작업 중 사용자 개입이 반드시 필요한 상황이 발생하면 status를 `"blocked"`로, `"blocked_reason"` 필드에 사유를 기록하고 작업을 즉시 중단하라.

## 주의사항

- App Group identifier는 `group.com.tic.app`. entitlements에 이미 설정되어 있어야 함 (Phase 0).
- WidgetData.swift와 TicActivityAttributes.swift를 양쪽 타겟에 포함 시 "duplicate symbol" 에러가 나면: project.yml에서 Widget Extension의 sources에 해당 파일을 명시적으로 추가하고, 메인 앱 타겟에서는 해당 파일이 이미 sources 경로에 포함되어 있는지 확인.
- `Button(intent:)`는 iOS 17+ Interactive Widget에서만 동작. 이전 버전에서는 무시됨.
- Widget에서 `EventKit`을 직접 접근할 때, 권한이 이미 메인 앱에서 승인되어 있어야 한다.
- 위젯 미리보기(Preview)는 Xcode에서만 가능. CLI 빌드에서는 빌드 성공만 확인.
- CGColor → hex 변환 유틸리티 함수를 만들어야 한다. WidgetData.swift나 Extensions에 추가.
- 시뮬레이터 이름이 `iPhone 16`이 아닐 수 있다. `xcrun simctl list devices available`로 확인하고 적절히 조정하라.
