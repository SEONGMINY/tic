# Phase 3: edit-mode

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `docs/flow.md` — F3a(편집 모드 전체 명세: 진입, 핸들, toolbar, 리사이즈, 이동, 해제)
- `docs/code-architecture.md` — 편집 모드 상태 설계, z-index 순서, 제스처 우선순위
- `docs/adr.md` — ADR-020(편집 모드 @State), ADR-023(500줄 초과 시 분리)
- `docs/prd.md` — 타임라인 편집 모드 테이블

그리고 아래 소스 파일들을 읽어 현재 구현 상태를 파악하라:

- `tic/Views/Calendar/DayView.swift` — Phase 2에서 수정됨
- `tic/Views/Components/TimelineView.swift` — Phase 2에서 z-index 재정렬됨
- `tic/Services/EventKitService.swift` — Phase 0에서 duplicate(), moveToDate() 추가됨
- `tic/ViewModels/DayViewModel.swift` — computeLayout 등

Phase 0-2의 작업물을 꼼꼼히 확인하라.

## 작업 내용

### 1. 편집 모드 상태 관리

DayView에 아래 상태 추가:

```swift
@State private var editingItemId: String?          // 편집 중인 블록 ID (nil = 기본 상태)
@State private var showEditToolbar: Bool = true     // toolbar 표시 여부
```

TimelineView에 편집 모드 관련 파라미터 추가:

```swift
var editingItemId: Binding<String?>
var onResizeItem: (_ itemId: String, _ newStart: Date, _ newEnd: Date) -> Void
var onMoveItem: (_ itemId: String, _ newStart: Date, _ newEnd: Date) -> Void
var onDuplicateItem: (_ itemId: String) -> Void
```

### 2. 편집 모드 진입 / 해제

**진입:**
- 이벤트 블록의 기존 `.contextMenu`를 제거하고, `.onLongPressGesture(minimumDuration: 0.5)` 로 교체
- long press 시:
  1. `UIImpactFeedbackGenerator(style: .medium).impactOccurred()` (haptic)
  2. `editingItemId = item.id`
  3. `showEditToolbar = true`

**해제:**
- 빈 영역 탭: ZStack 전체에 `.onTapGesture` 추가. `editingItemId != nil`일 때만 `editingItemId = nil` 설정
- 편집 중 블록 탭: `showEditToolbar = false` (toolbar만 닫힘, editingItemId 유지)
- 다른 블록 long press: 자동으로 `editingItemId`가 새 블록 ID로 교체됨

**편집 모드 중 제스처 비활성화:**
- DayView의 타임라인 좌우 스와이프 DragGesture: `editingItemId == nil` 조건 추가
- TimelineView의 빈 시간대 long press: `editingItemId == nil` 조건으로 `.allowsHitTesting` 제어

### 3. 핸들 렌더링

편집 중인 블록(`editingItemId == item.id`)일 때 블록 위에 핸들 오버레이:

```swift
// 상단-우측 핸들 (시작 시간 조절)
Circle()
    .fill(.white)
    .frame(width: 8, height: 8)
    .shadow(radius: 2)
    .position(x: blockWidth, y: 0)  // 블록 우상단

// 하단-좌측 핸들 (종료 시간 조절)
Circle()
    .fill(.white)
    .frame(width: 8, height: 8)
    .shadow(radius: 2)
    .position(x: 0, y: blockHeight)  // 블록 좌하단
```

핸들은 블록의 overlay로 배치. `.zIndex(3)` (editingOverlay 레벨).

### 4. 리사이즈 (DragGesture on handles)

각 핸들에 `DragGesture` 부착:

**상단-우측 핸들 (시작 시간):**
```swift
.gesture(
    DragGesture()
        .onChanged { value in
            // y축 이동량 → 15분 단위 스냅
            let minutesDelta = Int(round(value.translation.height / (hourHeight / 4))) * 15
            // 임시 시작 시간 계산 (표시용)
            // tooltip에 새 시간 표시
        }
        .onEnded { value in
            // 최종 시작 시간 계산
            // 최소 30분 보장: newStart < currentEnd - 30분
            // onResizeItem 호출
        }
)
```

**하단-좌측 핸들 (종료 시간):**
- 동일한 패턴, 종료 시간 조절
- 최소 30분 보장: newEnd > currentStart + 30분

**Tooltip 구현:**
- 드래그 중 핸들 옆에 시간 표시하는 작은 뷰
- `@State private var resizeTooltip: (time: String, position: CGPoint)?`
- 배경: `.ultraThinMaterial`, cornerRadius 6, font `.system(size: 11, design: .monospaced)`
- 핸들에서 x 방향으로 약간 떨어진 위치에 표시

**15분 단위 스냅 계산:**
```swift
func snapToQuarterHour(_ date: Date) -> Date {
    let calendar = Calendar.current
    let minute = calendar.component(.minute, from: date)
    let snapped = Int(round(Double(minute) / 15.0)) * 15
    return calendar.date(bySetting: .minute, value: snapped % 60, of: date)!
}
```

### 5. 블록 이동 (같은 날, y축)

편집 모드에서 블록 본체에 DragGesture 부착:

```swift
.gesture(
    editingItemId == item.id ?
    DragGesture()
        .onChanged { value in
            // y축 이동 → 15분 단위 스냅
            // 블록 위치 실시간 업데이트 (임시 offset)
        }
        .onEnded { value in
            // 새 시작/종료 시간 계산 (duration 유지)
            // onMoveItem 호출
        }
    : nil
)
```

**자동 스크롤:**
- 블록을 화면 상단/하단 가장자리(50pt 이내)로 드래그하면 ScrollView를 자동 스크롤
- `ScrollViewReader.scrollTo`로 구현. 드래그 중 Timer를 사용하여 주기적으로 스크롤 위치 업데이트
- 구현이 복잡하면 이 phase에서는 자동 스크롤 없이 보이는 범위 내에서만 이동 가능하게 하고, 추후 개선

### 6. Floating Toolbar

편집 모드 + `showEditToolbar == true` 일 때 표시:

```swift
HStack(spacing: 0) {
    Button {
        // 삭제 확인 alert
    } label: {
        Label("삭제", systemImage: "trash")
            .font(.system(size: 13))
            .foregroundStyle(.red)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
    }
    
    Divider().frame(height: 20)
    
    Button {
        // duplicate 호출
        if let item = timedItems.first(where: { $0.id == editingItemId }) {
            onDuplicateItem(item.id)
        }
        editingItemId = nil  // 편집 모드 해제
    } label: {
        Label("복제", systemImage: "doc.on.doc")
            .font(.system(size: 13))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
    }
}
.background(.ultraThinMaterial)
.clipShape(RoundedRectangle(cornerRadius: 12))
.shadow(radius: 4, y: 2)
```

**위치 결정:**
- 편집 중인 블록의 하단 + 8pt 간격에 배치
- 블록 하단이 화면 하단에 가까우면 (남은 공간 < toolbar 높이 + 16pt): 블록 상단 - 8pt에 배치
- 블록 중앙 x에 정렬

### 7. DayView에서 콜백 연결

DayView에서 TimelineView의 콜백들을 EventKitService와 연결:

```swift
onResizeItem: { itemId, newStart, newEnd in
    if let item = dayViewModel.timedItems.first(where: { $0.id == itemId }) {
        try? eventKitService.moveToDate(item, newStart: newStart, newEnd: newEnd)
    }
}

onMoveItem: { itemId, newStart, newEnd in
    if let item = dayViewModel.timedItems.first(where: { $0.id == itemId }) {
        try? eventKitService.moveToDate(item, newStart: newStart, newEnd: newEnd)
    }
}

onDuplicateItem: { itemId in
    if let item = dayViewModel.timedItems.first(where: { $0.id == itemId }) {
        try? eventKitService.duplicate(item)
    }
}
```

### 8. 파일 분리 판단

작업 완료 후 TimelineView.swift의 총 라인 수를 확인하라. **500줄을 초과하면** 편집 모드 관련 코드(핸들, 리사이즈, 이동, tooltip, toolbar)를 `tic/Views/Components/EditableEventBlock.swift`로 분리하라.

분리 시:
- `EditableEventBlock`은 편집 중인 단일 블록의 렌더링을 담당하는 View
- TimelineView는 `editingItemId == item.id`일 때 `EditableEventBlock`을 사용하고, 아닐 때 기존 `eventBlock(for:containerWidth:)` 사용

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodebuild build -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5
```

빌드 성공 (에러 없음).

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/3-ux-enhance/index.json`의 phase 3 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- **제스처 충돌이 이 phase의 핵심 리스크다.** DragGesture(리사이즈), DragGesture(이동), DragGesture(타임라인 스와이프), onLongPressGesture(편집 진입), onTapGesture(편집 해제)가 모두 같은 영역에 있다. 우선순위를 명확히 관리하라:
  - 편집 모드 아닐 때: tap → 수정 sheet, long press → 편집 모드 진입, 스와이프 → 날짜 이동
  - 편집 모드일 때: 핸들 drag → 리사이즈, 블록 body drag → 이동, 빈 영역 tap → 해제
- **SwiftUI에서 조건부 제스처**: `if-else`로 제스처를 분기하거나, `.gesture(editingItemId == item.id ? someDrag : nil)` 패턴 사용. `nil`이 AnyGesture에 맞지 않으면 `.disabled()` 등 대안 사용.
- **리사이즈/이동 중 실시간 블록 위치 변경**: `@State`로 임시 offset을 관리하고, onEnded에서 실제 EventKit 업데이트. 드래그 중에는 EventKit을 호출하지 마라 (성능 문제).
- `editingItemId`를 `Binding<String?>`으로 TimelineView에 전달할 때, DayView의 `@State`를 `$editingItemId`로 전달.
- 기존 `.contextMenu`를 제거하면 "수정" context menu가 사라진다. 편집 모드에서는 블록 탭이 수정 sheet을 열지 않으므로 (toolbar만 닫힘), **기본 상태에서의 블록 탭 → 수정 sheet은 유지**해야 한다.
- 삭제 시 기존 `showDeleteAlert` 패턴을 재사용하라.
