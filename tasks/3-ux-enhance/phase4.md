# Phase 4: cross-day-drag

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `docs/flow.md` — F3a(편집 모드, 날짜 간 블록 이동)
- `docs/code-architecture.md` — 날짜 간 블록 이동 (overlay 패턴), CrossDayDragState
- `docs/adr.md` — ADR-021(overlay 패턴)

그리고 아래 소스 파일들을 읽어 현재 구현 상태를 파악하라:

- `tic/Views/Calendar/DayView.swift` — Phase 2-3에서 수정됨 (편집 모드 상태, phantom block)
- `tic/Views/Components/TimelineView.swift` — Phase 2-3에서 수정됨 (편집 모드 핸들, 리사이즈, 이동)
- `tic/Views/Components/EditableEventBlock.swift` — Phase 3에서 생성되었을 수 있음 (500줄 초과 시)
- `tic/Services/EventKitService.swift` — Phase 0에서 moveToDate() 추가됨
- `tic/ViewModels/DayViewModel.swift` — loadItems, computeLayout

Phase 0-3의 작업물을 꼼꼼히 확인하라.

## 작업 내용

### 1. CrossDayDragState 정의

DayView.swift (또는 적절한 위치)에 아래 구조체 정의:

```swift
struct CrossDayDragState {
    let item: TicItem              // 드래그 중인 아이템
    let originalStart: Date        // 원래 시작 시간
    let originalEnd: Date          // 원래 종료 시간
    var currentOffset: CGSize      // 현재 드래그 offset (손가락 위치)
    var targetDate: Date           // 이동할 날짜
    var targetHour: Int            // 이동할 시간 (15분 스냅 후)
    var targetMinute: Int
}
```

DayView에 상태 추가:
```swift
@State private var crossDayDrag: CrossDayDragState?
```

### 2. 날짜 전환 감지 로직

Phase 3에서 구현된 블록 본체 DragGesture를 확장한다. 편집 모드에서 블록을 좌우로 드래그할 때:

```swift
.onChanged { value in
    let horizontalDrag = value.translation.width
    
    if abs(horizontalDrag) > 60 {
        // 날짜 전환 트리거
        let direction: Int = horizontalDrag > 0 ? -1 : 1  // 우로 드래그 = 이전날, 좌로 = 다음날
        let newDate = viewModel.selectedDate.adding(days: direction)
        
        // crossDayDrag 상태 설정
        crossDayDrag = CrossDayDragState(
            item: item,
            originalStart: item.startDate!,
            originalEnd: item.endDate!,
            currentOffset: value.translation,
            targetDate: newDate,
            targetHour: ...,
            targetMinute: ...
        )
        
        // 타임라인 slide 전환
        slideDirection = direction > 0 ? .trailing : .leading
        withAnimation(.easeInOut(duration: 0.25)) {
            contentId = UUID()
            viewModel.selectedDate = newDate
        }
    } else {
        // 기존 y축 이동 로직 (Phase 3)
    }
}
```

### 3. Overlay 렌더링

DayView의 최상위 ZStack에 overlay 추가:

```swift
.overlay {
    if let drag = crossDayDrag {
        // 드래그 중인 블록을 overlay로 렌더링
        // 타임라인 전환과 독립적으로 손가락 위치에 따라 이동
        let blockColor = Color(cgColor: drag.item.calendarColor)
        
        RoundedRectangle(cornerRadius: 4)
            .fill(blockColor.opacity(0.85))
            .overlay {
                Text(drag.item.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(4)
            }
            .frame(
                width: UIScreen.main.bounds.width - 60,  // timeColumnWidth + 간격
                height: eventHeight(...)
            )
            .shadow(radius: 8, y: 4)  // 떠있는 느낌
            .position(
                x: UIScreen.main.bounds.width / 2 + 4,  // 중앙
                y: drag.currentOffset.height + ...       // 손가락 위치 기준
            )
    }
}
```

### 4. 드래그 완료 (onEnded)

```swift
.onEnded { value in
    if let drag = crossDayDrag {
        // 손가락 위치 → 시간으로 변환 (15분 스냅)
        let yInTimeline = value.location.y  // 스크롤 offset 고려 필요
        let hour = Int(yInTimeline / hourHeight)
        let minuteFraction = (yInTimeline - CGFloat(hour) * hourHeight) / hourHeight
        let minute = Int(round(minuteFraction * 4)) * 15  // 15분 스냅
        
        // 새 시작/종료 시간 계산
        let calendar = Calendar.current
        let duration = drag.originalEnd.timeIntervalSince(drag.originalStart)
        var components = calendar.dateComponents([.year, .month, .day], from: drag.targetDate)
        components.hour = hour
        components.minute = minute
        let newStart = calendar.date(from: components)!
        let newEnd = newStart.addingTimeInterval(duration)
        
        // EventKit 업데이트
        try? eventKitService.moveToDate(drag.item, newStart: newStart, newEnd: newEnd)
        
        // 상태 초기화
        crossDayDrag = nil
        editingItemId = nil
    }
}
```

### 5. 연속 날짜 이동

드래그 중에 추가로 좌우 드래그하면 또 다른 날짜로 전환할 수 있어야 한다:
- `crossDayDrag != nil` 상태에서 추가 좌우 드래그 감지
- `targetDate`를 업데이트하고 다시 타임라인 slide 전환
- 이 로직은 `.onChanged`에서 처리

### 6. 취소

드래그 중 원래 위치로 돌아오면 (translation이 작아지면):
- 원래 날짜로 복귀
- `crossDayDrag = nil`
- 편집 모드는 유지 (editingItemId 유지)

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodebuild build -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5
```

빌드 성공 (에러 없음).

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/3-ux-enhance/index.json`의 phase 4 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- **이 phase는 실기기 테스트 없이 동작 검증이 어렵다.** 컴파일 성공이 AC지만, 제스처 로직의 정확성은 보장되지 않는다. 코드의 논리적 정확성에 집중하라.
- **스크롤 offset 고려**: 드래그 위치를 시간으로 변환할 때, ScrollView의 현재 스크롤 offset을 고려해야 한다. `GeometryReader`를 사용하여 scroll offset을 추적하거나, 좌표계를 `.coordinateSpace`로 관리하라.
- **타임라인 전환 후 데이터 로드**: `viewModel.selectedDate`가 변경되면 `.onChange`에서 `dayViewModel.loadItems`가 호출된다. 이때 드래그 중인 블록은 overlay에 있으므로 타임라인의 블록 목록에서는 사라질 수 있다. 이는 의도된 동작이다.
- **duration 유지**: 날짜 간 이동 시 이벤트의 duration(종료-시작 차이)은 반드시 유지되어야 한다.
- **overlay의 z-index**: DayView 최상위에 있으므로 다른 모든 UI 위에 표시된다. 이는 의도된 동작.
- `crossDayDrag`와 기존 Phase 3의 y축 이동 로직이 서로 배타적으로 동작해야 한다. 좌우 60px 이상 드래그 → crossDay 모드, 그 미만 → y축 이동 모드. 한번 crossDay 모드에 진입하면 y축 이동으로 전환하지 않는다.
