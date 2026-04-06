# Phase 1: simple-view-updates

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `docs/prd.md` — PRD (EventFormView 폼 필드 테이블, 인터랙션 테이블)
- `docs/flow.md` — F2(MonthView "이번달"), F5(일정 생성 Segmented Control), F7(YearView "올해")
- `docs/code-architecture.md` — 코드 아키텍처

그리고 아래 소스 파일들을 읽어 현재 구현 상태를 파악하라:

- `tic/Views/Calendar/YearView.swift` — 현재 "오늘" 버튼 구현
- `tic/Views/Calendar/MonthView.swift` — 현재 MonthView (floating 버튼 없음)
- `tic/Views/EventFormView.swift` — 현재 폼 UI
- `tic/ViewModels/EventFormViewModel.swift` — Phase 0에서 isAllDay 추가됨

Phase 0의 작업물을 확인하라:
- `tic/ViewModels/EventFormViewModel.swift` — isAllDay 필드 추가 확인

## 작업 내용

### 1. YearView: "오늘" → "올해" 텍스트 변경

`tic/Views/Calendar/YearView.swift`에서:
- 왼쪽 하단 floating 버튼의 `Text("오늘")`을 `Text("올해")`로 변경
- 그 외 로직(scrollToTodayTrigger, 스크롤 동작)은 변경 없음

### 2. MonthView: "이번달" floating 버튼 추가

`tic/Views/Calendar/MonthView.swift`에서 YearView의 floating 버튼 패턴을 그대로 복사하여 적용:

```swift
// 왼쪽 하단 floating 버튼
Button {
    scrollToThisMonthTrigger.toggle()
} label: {
    Text("이번달")
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.orange)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
}
.padding(.leading, 16)
.padding(.bottom, 16)
```

**구현 규칙:**
- `@State private var scrollToThisMonthTrigger = false` 추가
- `.onChange(of: scrollToThisMonthTrigger)` 에서 현재 월(올해의 이번달)로 스크롤 애니메이션 (`.easeOut(duration: 0.3)`)
- 기존 MonthView의 ScrollViewReader 안에 ZStack으로 감싸고 `.bottomLeading` alignment 사용
- YearView의 구현 패턴과 동일한 방식으로 작성

### 3. EventFormView 개편

`tic/Views/EventFormView.swift`를 수정한다:

**3a. Segmented Control 추가 (생성 모드에서만):**
- 폼 최상단(제목 Section 위)에 `Picker` (`.pickerStyle(.segmented)`)를 배치
- 선택지: `["이벤트", "미리 알림"]`
- `viewModel.isCalendarType`에 바인딩
- **수정 모드(`viewModel.isEditMode == true`)일 때는 Segmented Control을 숨긴다** (렌더링하지 않음)
- Segmented Control의 스타일: `.padding(.horizontal, 16)`, `.padding(.vertical, 8)`

**3b. 타입 전환 시 데이터 처리:**
- Segmented Control 전환 시 `viewModel.title`은 유지
- `viewModel.selectedCalendar`은 `nil`로 초기화
- 이벤트 → 미리 알림 전환 시: 기존 로직대로 시간 토글 표시
- 미리 알림 → 이벤트 전환 시: startDate/endDate가 nil이면 기본값(09:00-10:00) 세팅

**3c. 하루 종일 토글 추가:**
- `viewModel.isCalendarType`이 true일 때만 표시
- 시작/종료 DatePicker Section 안, DatePicker 들 위에 배치:
  ```swift
  Toggle("하루 종일", isOn: $viewModel.isAllDay)
      .font(.system(size: 14))
  ```
- `isAllDay == true`일 때: DatePicker의 `displayedComponents`를 `[.date]`로 변경 (시간 숨김)
- `isAllDay == false`일 때: 기존대로 `[.date, .hourAndMinute]`

**3d. 캘린더 선택 분리:**
- `viewModel.isCalendarType == true`일 때: `allCalendars`만 Menu에 표시 (리마인더 리스트 제외)
- `viewModel.isCalendarType == false`일 때: `allReminderLists`만 Menu에 표시 (캘린더 제외)
- 기존의 "캘린더" / "미리 알림" Section 분리를 제거하고, 선택된 타입에 맞는 목록만 표시

**3e. 둥근 스타일:**
- Form의 Section들에 더 큰 cornerRadius 적용. `.listRowBackground`에 `RoundedRectangle(cornerRadius: 16)` 사용하거나, Form 대신 ScrollView + VStack + custom card 스타일로 변경하지 않는다 — Form의 기본 InsetGroupedListStyle을 유지하되, `.listSectionSpacing(.compact)` 등으로 간격 조정
- 각 Section에 `.clipShape(RoundedRectangle(cornerRadius: 16))` 은 Form에서 제대로 동작하지 않으므로, **`.environment(\.defaultMinListRowHeight, 44)` 정도의 미세 조정만 하고 과도한 커스텀은 피한다**

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodebuild build -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5
```

빌드 성공 (에러 없음).

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/3-ux-enhance/index.json`의 phase 1 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- MonthView의 스크롤은 `monthOffsetRange` (±120개월) 기반이다. 현재 월의 offset을 정확히 계산하여 스크롤 타겟으로 사용하라. `baseDate`는 2026년 1월 1일이다.
- EventFormView에서 Form 스타일을 과도하게 커스텀하지 마라. SwiftUI Form은 스타일 오버라이드에 민감하여 레이아웃이 깨질 수 있다. 최소한의 변경만 하라.
- Segmented Control이 `.onChange`로 `isCalendarType` 변경을 감지할 때, selectedCalendar를 nil로 초기화하는 로직을 넣어야 한다. 단, 이미 `selectedCalendarId` Binding의 set에서 isCalendarType을 세팅하는 로직이 있으므로, 양방향 무한 루프가 발생하지 않도록 주의하라.
- 수정 모드에서 네비게이션 타이틀이 "일정 수정"인지 "이벤트 편집"인지 확인하라. 기존 코드의 타이틀을 유지한다.
