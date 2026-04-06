# Phase 2: dayview-timeline-core

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `docs/flow.md` — F3(일간 뷰 제스처), F3a(편집 모드), F5a(phantom block)
- `docs/code-architecture.md` — z-index 순서, 편집 모드 상태 설계, 제스처 우선순위
- `docs/adr.md` — ADR-009(ScrollView + ZStack), ADR-020(편집 모드 @State)

그리고 아래 소스 파일들을 읽어 현재 구현 상태를 파악하라:

- `tic/Views/Calendar/DayView.swift` — 현재 주간 스트립, 타임라인 연동
- `tic/Views/Components/TimelineView.swift` — 현재 ZStack 구조, 제스처, z-index
- `tic/Views/EventFormView.swift` — Phase 1에서 수정됨 (Segmented Control 등)
- `tic/ViewModels/DayViewModel.swift` — computeLayout 등

Phase 0-1의 작업물을 확인하라:
- `tic/Views/EventFormView.swift` — Segmented Control, 하루종일 토글 추가 확인
- `tic/ViewModels/EventFormViewModel.swift` — isAllDay 필드 추가 확인

## 작업 내용

### 1. 주간 스트립 독립 slide in/out 애니메이션

`tic/Views/Calendar/DayView.swift`에서:

현재 타임라인은 `contentId` UUID 교체 + `.transition(.asymmetric(...))` 으로 slide 애니메이션이 적용되어 있다. 주간 스트립도 동일한 패턴으로 독립 애니메이션을 적용한다.

```swift
@State private var weekStripId = UUID()  // 새로 추가
```

- 주간 스트립(`weekStrip`)에 `.id(weekStripId)` + `.transition(.asymmetric(...))` 적용
- 날짜 변경 시(스와이프, 주간 스트립 탭, 주간 스트립 스와이프) `weekStripId = UUID()`도 함께 교체
- 타임라인의 `contentId`와 **독립적으로** 교체 — 하나의 `withAnimation` 블록 안에서 둘 다 교체하되, 각각 자체 transition을 가짐
- `slideDirection`은 공유 (같은 방향으로 슬라이드)

### 2. TimelineView z-index 재정렬

`tic/Views/Components/TimelineView.swift`의 ZStack 내부 순서를 변경한다:

**현재 순서 (문제 있음):**
1. timeLines (시간 구분선)
2. eventBlocks (GeometryReader)
3. currentTimeLine
4. emptySlotGestures (GeometryReader) ← 이벤트 블록 위에 있어서 탭 가려짐

**변경 후 순서:**
1. timeLines (시간 구분선 + 시간 라벨) — 시간 라벨에 long press 제스처 추가
2. emptySlotGestures (빈 시간대 long press) — 이벤트 블록 **아래**로 이동
3. eventBlocks (GeometryReader) — `.zIndex(1)` 부여
4. phantomBlock (있을 때만) — `.zIndex(0.5)` (새로 추가, 이 phase에서 렌더링)
5. currentTimeLine — `.zIndex(2)` 부여

### 3. timeColumnWidth 확대 + 시간 라벨 long press

`tic/Views/Components/TimelineView.swift`에서:

- `timeColumnWidth`를 `44`에서 `52`로 변경
- `DayView.swift`에서 `computeLayout(containerWidth:)` 호출 시 전달하는 너비도 업데이트: `UIScreen.main.bounds.width - 52` → `UIScreen.main.bounds.width - 60` (52pt 시간 컬럼 + 8pt 간격)
- 시간 라벨("09:00" 등) 텍스트에 long press 제스처 추가:

```swift
Text(String(format: "%02d:00", hour))
    // ... 기존 스타일 ...
    .contentShape(Rectangle())
    .onLongPressGesture(minimumDuration: 0.5) {
        let calendar = Calendar.current
        if let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: selectedDate) {
            onTimeSlotLongPress(date)
        }
    }
```

- 시간 라벨의 터치 영역을 넓히기 위해 `.frame(width: timeColumnWidth)` 전체에 `.contentShape(Rectangle())` 적용

### 4. Phantom Block

**DayView에 phantom block 상태 추가:**

```swift
@State private var phantomBlock: PhantomBlockInfo?  // nil이면 미표시
@State private var showPhantomSheet = false

struct PhantomBlockInfo {
    let hour: Int
    let minute: Int
}
```

**TimelineView에 phantom block 파라미터 추가:**

TimelineView의 초기화 파라미터에 `phantomBlock: PhantomBlockInfo?` 추가. phantom block이 non-nil이면 ZStack에 렌더링:

```swift
// phantom block 렌더링 (eventBlocks 아래, emptySlotGestures 위)
if let phantom = phantomBlock {
    let yPos = (CGFloat(phantom.hour) + CGFloat(phantom.minute) / 60.0) * hourHeight
    let eventAreaWidth = geometry.size.width - timeColumnWidth
    
    RoundedRectangle(cornerRadius: 4)
        .fill(Color.orange.opacity(0.4))  // 기본 캘린더 색상 + 낮은 opacity
        .frame(width: eventAreaWidth - 2, height: hourHeight - 1)  // 1시간 높이
        .offset(x: timeColumnWidth, y: yPos)
        .zIndex(0.5)
}
```

**DayView에서 phantom block + sheet 연동:**

`onTimeSlotLongPress` 콜백 (기존 `onCreateAtDate`)을 수정:
- long press 시 `phantomBlock = PhantomBlockInfo(hour: hour, minute: 0)` 설정
- `showPhantomSheet = true` 설정
- sheet dismiss 시 (저장 완료 또는 취소): `phantomBlock = nil`

**Bottom Sheet detent:**

EventFormView를 표시하는 `.sheet`에 `.presentationDetents([.medium, .large])` 적용. 기존의 `.presentationDetents([.large])`를 변경.

**DayView에서 onCreateAtDate 콜백 수정:**

현재 `onCreateAtDate: (Date) -> Void` 콜백이 ContentView에서 EventFormView sheet을 띄우는 방식인데, phantom block은 DayView 내부에서 관리해야 한다. 두 가지 접근:

- **방법 A**: DayView 내부에 자체 sheet 상태를 관리하여 phantom block과 동기화
- **방법 B**: 기존 콜백 방식 유지하되, phantom block 상태만 DayView에서 관리

**방법 A를 사용하라.** DayView 내부에 `@State private var showCreateSheet = false`와 `@State private var createDate: Date?`를 추가하고, `onCreateAtDate` 대신 DayView 내부에서 직접 EventFormView sheet을 표시한다. ContentView에서의 기존 + 버튼 생성은 그대로 유지.

DayView에 필요한 추가 파라미터:
```swift
var eventFormViewModel: EventFormViewModel
var notificationService: NotificationService
```

sheet 내에서 EventFormView를 직접 사용. sheet dismiss 시 phantomBlock = nil.

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodebuild build -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5
```

빌드 성공 (에러 없음).

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/3-ux-enhance/index.json`의 phase 2 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- DayView에 EventFormView sheet을 직접 표시할 때, ContentView에서의 기존 sheet 표시 로직과 **충돌하지 않도록** 주의하라. ContentView의 + 버튼은 여전히 ContentView의 sheet을 사용한다. DayView의 sheet은 phantom block 전용이다.
- `PhantomBlockInfo` struct를 별도 파일로 분리하지 마라. DayView.swift 내부 또는 TimelineView.swift 내부에 private으로 정의하되, 두 파일 모두에서 접근해야 하므로 TimelineView.swift 파일 상단에 정의하고 접근 제어자를 internal로 설정하라.
- phantom block의 색상은 `.orange.opacity(0.4)`로 하드코딩한다. 아직 캘린더가 선택되지 않은 상태이므로 캘린더 색상을 알 수 없다.
- z-index 변경 시 기존의 이벤트 블록 탭, context menu, long press가 정상 동작하는지 확인하라. emptySlotGestures가 eventBlocks 아래로 이동하므로 이벤트 블록의 제스처가 우선되어야 한다.
- `weekStripId` 애니메이션 추가 시, 기존 `matchedGeometryEffect`(`dayAnimation` namespace)와 충돌하지 않도록 주의하라. id/transition 방식과 matchedGeometryEffect는 독립적으로 동작하므로 보통 문제없으나, 동시에 애니메이션이 트리거되면 시각적으로 어색할 수 있다.
