# Phase 5: live-activity-redesign

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `docs/prd.md` — Live Activity 테이블 (데이터, 카운트다운, 종료 조건)
- `docs/flow.md` — F9(Live Activity 전체 명세: lock screen, DI, 카운트다운, 종료)
- `docs/data-schema.md` — TicActivityAttributes ContentState ([ActivityEvent], currentIndex, nextIndex)
- `docs/code-architecture.md` — LiveActivityService 시그니처
- `docs/adr.md` — ADR-018(안정적 레이아웃), ADR-022(다중 이벤트 LA)

그리고 아래 소스 파일들을 읽어 현재 구현 상태를 파악하라:

- `ticWidgets/TicLiveActivityView.swift` — 현재 UI (Phase 0에서 임시 수정되었을 수 있음)
- `tic/Services/LiveActivityService.swift` — 현재 start/update/end 로직
- `tic/Views/ContentView.swift` — LA 시작 로직
- `tic/Models/TicActivityAttributes.swift` — Phase 0에서 ContentState 변경됨

Phase 0의 작업물을 확인하라:
- `tic/Models/TicActivityAttributes.swift` — [ActivityEvent] + currentIndex/nextIndex 구조 확인

## 작업 내용

### 1. LiveActivityService 전면 개편

`tic/Services/LiveActivityService.swift`를 수정한다.

**시그니처 변경:**

```swift
class LiveActivityService {
    /// 오늘의 전체 일정으로 Live Activity 시작
    func start(events: [TicItem]) throws
    
    /// 상태 갱신 (currentIndex/nextIndex 재계산)
    func update(events: [TicItem])
    
    /// 특정 activity 종료
    func end(for identifier: String)
    
    /// 모든 activity 종료
    func endAll()
    
    var isActivityActive: Bool { get }
}
```

**start(events:) 구현:**
1. 시간 있는 일정만 필터 (`startDate != nil && endDate != nil && !isAllDay`)
2. 시작 시간 기준 정렬
3. 최대 10개로 자르기
4. `[ActivityEvent]`로 변환 (title, startDate, endDate, colorHex)
5. `currentIndex` 계산: 현재 시간이 startDate~endDate 범위 안인 일정의 index
6. `nextIndex` 계산: currentIndex 다음, 또는 currentIndex가 nil이면 현재 시간 이후 첫 일정
7. `Activity.request()` 호출
8. `CGColor.hexString` extension 활용 (이미 존재)

**update(events:) 구현:**
1. start와 동일한 필터/정렬/변환
2. currentIndex/nextIndex 재계산
3. `activity.update(content:)` 호출

**currentIndex/nextIndex 계산 로직:**
```swift
func computeIndices(events: [ActivityEvent]) -> (current: Int?, next: Int?) {
    let now = Date()
    var currentIdx: Int? = nil
    var nextIdx: Int? = nil
    
    for (i, event) in events.enumerated() {
        if event.startDate <= now && now < event.endDate {
            currentIdx = i
        }
        if event.startDate > now && nextIdx == nil {
            nextIdx = i
        }
    }
    
    // currentIndex가 있고 nextIdx가 없으면, current 다음 일정을 next로
    if let ci = currentIdx, nextIdx == nil, ci + 1 < events.count {
        nextIdx = ci + 1
    }
    
    return (currentIdx, nextIdx)
}
```

### 2. TicLiveActivityView 전면 재작성

`ticWidgets/TicLiveActivityView.swift`를 전면 재작성한다.

**Lock Screen 뷰:**

```
┌─────────────────────────────────────┐
│  tic                    ⏱ 1h 24m   │  ← 로고 + 카운트다운
├─────────────────────────────────────┤
│  09:00 ●──●──●── ─ ─ ─● 17:00      │  ← progress line + dots
│  지금  팀 미팅           10:00-11:00 │  ← 현재 일정 (있을 때만)
│  다음  디자인 리뷰        14:00-15:00 │  ← 다음 일정 (있을 때만)
└─────────────────────────────────────┘
```

**Progress Line 구현:**

```swift
struct ProgressLineView: View {
    let events: [ActivityEvent]
    let currentIndex: Int?
    
    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let timeRange = totalTimeRange  // 첫 시작 ~ 마지막 종료
            let now = Date()
            let progress = min(max(now.timeIntervalSince(timeRange.start) / timeRange.duration, 0), 1)
            let progressX = totalWidth * CGFloat(progress)
            
            ZStack(alignment: .leading) {
                // 실선 (경과)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 4))
                    path.addLine(to: CGPoint(x: progressX, y: 4))
                }
                .stroke(.white, lineWidth: 2)
                
                // 점선 (남은)
                Path { path in
                    path.move(to: CGPoint(x: progressX, y: 4))
                    path.addLine(to: CGPoint(x: totalWidth, y: 4))
                }
                .stroke(.white.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                
                // 각 일정 dot
                ForEach(Array(events.enumerated()), id: \.offset) { index, event in
                    let x = xPosition(for: event.startDate, in: timeRange, totalWidth: totalWidth)
                    let isCurrent = index == currentIndex
                    let isPast = event.endDate < now
                    
                    Circle()
                        .fill(Color(hex: event.colorHex))
                        .frame(width: isCurrent ? 12 : 8, height: isCurrent ? 12 : 8)
                        .opacity(isPast ? 0.6 : 1.0)
                        .shadow(color: isCurrent ? Color(hex: event.colorHex).opacity(0.6) : .clear, radius: 4)  // 글로우
                        .position(x: x, y: 4)
                }
            }
        }
        .frame(height: 16)
    }
}
```

**시간 라벨 (양 끝):**
- 왼쪽: 첫 일정 시작 시간 (HH:mm)
- 오른쪽: 마지막 일정 종료 시간 (HH:mm)
- `.monospacedDigit()` 적용

**카운트다운 로직:**
- 일정 1개만 + 현재 진행 중: `Text(timerInterval: event.startDate...event.endDate, countsDown: true)`
- 여러 일정 + 다음 일정 존재: `Text(timerInterval: now...nextEvent.startDate, countsDown: true)`
- 빈 시간(진행 중 없음, 다음 있음): 다음 일정까지 남은 시간
- 모든 일정 종료: **카운트다운 숨김** (Text를 렌더링하지 않음)

**"지금/다음" 라벨:**
```swift
if let ci = state.currentIndex {
    HStack {
        Text("지금").font(.system(size: 10, weight: .bold)).foregroundStyle(.orange)
        Text(state.events[ci].title).font(.system(size: 12)).lineLimit(1)
        Spacer()
        Text(timeRange(state.events[ci])).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
    }
}
if let ni = state.nextIndex {
    HStack {
        Text("다음").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
        Text(state.events[ni].title).font(.system(size: 12)).lineLimit(1)
        Spacer()
        Text(timeRange(state.events[ni])).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
    }
}
```

**Progress 자동 갱신:**
- Lock Screen 뷰 전체를 `TimelineView(.periodic(every: 60))` 으로 감싸서 1분마다 자동 리렌더
- 이것이 Live Activity에서 동작하지 않을 수 있음 → 동작하지 않으면 제거하고 앱의 60초 타이머에 의존

**Dynamic Island Expanded:**
```swift
DynamicIslandExpandedRegion(.leading) {
    Text("tic").font(.system(size: 12, weight: .bold)).foregroundStyle(.orange)
}
DynamicIslandExpandedRegion(.trailing) {
    // 카운트다운 (Lock Screen과 동일 로직)
}
DynamicIslandExpandedRegion(.bottom) {
    // 축소된 ProgressLineView
    // + 시작/끝 시간
}
```

**Dynamic Island Compact:**
```swift
compactLeading: {
    HStack(spacing: 4) {
        Circle().fill(.orange).frame(width: 6, height: 6)
        // 현재 또는 다음 일정 제목
        Text(currentOrNextTitle).font(.system(size: 12)).lineLimit(1)
    }
}
compactTrailing: {
    // 카운트다운
}
```

**Dynamic Island Minimal:**
```swift
// 기존 progress 원형 유지 (오렌지 링)
// progress = 전체 타임라인 진행률
```

**Color(hex:) extension:**
Live Activity 뷰에서 `colorHex` 문자열을 Color로 변환하는 extension이 필요하다:
```swift
extension Color {
    init(hex: String) {
        // #RRGGBB → Color
    }
}
```

### 3. ContentView LA 시작 로직 변경

`tic/Views/ContentView.swift`에서 Live Activity 시작/업데이트 로직 수정:

기존: 단일 이벤트를 찾아서 `liveActivityService.start(for: item)` 호출
변경: 오늘의 전체 일정을 전달

```swift
// 기존 로직을 아래로 교체:
let todayItems = await eventKitService.fetchAllItems(for: Date())
let timedItems = todayItems.filter { $0.startDate != nil && $0.endDate != nil && !$0.isAllDay }

if timedItems.isEmpty {
    // 일정 없으면 LA 시작하지 않음
    return
}

if liveActivityService.isActivityActive {
    liveActivityService.update(events: timedItems)
} else {
    try? liveActivityService.start(events: timedItems)
}
```

**종료 로직 변경:**
- 기존: 다음 일정이 없으면 `endAll()`
- 변경: **유저 수동 종료 전까지 유지**. `endAll()` 자동 호출을 제거하거나, 모든 일정이 종료된 후에도 LA를 유지하도록 변경
- 모든 일정 종료 후: update만 호출 (실선 꽉 찬 상태, 카운트다운 없음)

### 4. 딥링크

기존 `deepLinkURL(for:)` 함수를 유지하되, 이벤트 배열의 첫 번째 이벤트 날짜 기준으로 URL 생성:
```swift
func deepLinkURL(for events: [ActivityEvent]) -> URL {
    let date = events.first?.startDate ?? Date()
    // tic://day?date=YYYY-MM-dd
}
```

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodebuild build -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5
```

빌드 성공 (에러 없음).

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/3-ux-enhance/index.json`의 phase 5 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- **Live Activity 뷰는 Widget Extension 타겟에 속한다** (`ticWidgets/`). 메인 앱 타겟의 코드를 직접 import할 수 없다. `TicActivityAttributes`와 `ActivityEvent`는 양쪽 타겟에 모두 포함되어야 한다 (현재 이미 그렇게 설정됨).
- **`TimelineView(.periodic)`이 Live Activity에서 동작하지 않을 수 있다.** ActivityKit은 제한된 SwiftUI 서브셋만 지원한다. 동작하지 않으면 제거하고, 앱의 60초 타이머 업데이트에 의존하라.
- **Color(hex:) extension**: Widget Extension 타겟에서 접근 가능한 위치에 정의하라. `TicLiveActivityView.swift` 파일 하단에 private으로 정의하는 것을 추천.
- **ADR-018**: `position()` 기반 커스텀 그래픽은 잠금화면/DI에서 레이아웃이 깨질 수 있다. `GeometryReader` + relative positioning을 사용하되, 레이아웃이 불안정하면 고정 크기 fallback을 사용하라.
- ContentView에서 `endAll()` 자동 호출을 제거할 때, 앱이 완전히 종료되어도 LA가 남아있게 된다. 이는 의도된 동작이다. iOS가 4시간 후 자동으로 LA를 종료한다.
- `Text(timerInterval:countsDown:)`은 ActivityKit에서 잘 동작하는 시스템 제공 자동 카운트다운이다. 이것을 적극 활용하라.
- 기존 `LiveActivityService`의 `currentActivity`, `lastEndTime` 프로퍼티는 유지하되, `start(for: TicItem)` → `start(events: [TicItem])` 시그니처 변경에 맞게 내부 로직을 수정하라.
- `WidgetData.swift`의 `WidgetEventItem`은 변경하지 마라. 위젯 캐시는 이 task의 스코프 밖이다.
