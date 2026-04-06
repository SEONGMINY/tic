# Phase 0: data-service-layer

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `docs/data-schema.md` — 데이터 스키마 (TicActivityAttributes ContentState 구조 포함)
- `docs/code-architecture.md` — 코드 아키텍처 (서비스 계약, 편집 모드 상태 설계)
- `docs/adr.md` — 아키텍처 결정 기록 (ADR-022: 다중 이벤트 LA)

그리고 아래 소스 파일들을 읽어 현재 구현 상태를 파악하라:

- `tic/Models/TicActivityAttributes.swift` — 현재 ContentState (단일 이벤트)
- `tic/Services/EventKitService.swift` — 현재 CRUD 메서드
- `tic/ViewModels/EventFormViewModel.swift` — 현재 폼 상태 관리

## 작업 내용

### 1. TicActivityAttributes.ContentState 구조 변경

`tic/Models/TicActivityAttributes.swift` 파일을 수정한다.

기존 ContentState(title, startDate, endDate, isReminder, calendarColorHex)를 아래 구조로 **교체**:

```swift
struct TicActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var events: [ActivityEvent]  // 오늘의 전체 일정 (최대 10개)
        var currentIndex: Int?       // 현재 진행 중 일정 index
        var nextIndex: Int?          // 다음 일정 index
    }
}

struct ActivityEvent: Codable, Hashable {
    var title: String
    var startDate: Date
    var endDate: Date
    var colorHex: String           // 캘린더 고유 색상 (#RRGGBB)
}
```

- `eventIdentifier` 프로퍼티는 제거한다. 더 이상 단일 이벤트가 아니므로 불필요.
- `ActivityEvent`는 같은 파일에 정의한다.
- 하위 호환 불필요 (미출시 상태).

### 2. EventKitService에 duplicate(), moveToDate() 추가

`tic/Services/EventKitService.swift`에 아래 2개 메서드를 추가한다:

```swift
/// 동일 시간에 일정 복제. 반복 규칙은 제외.
func duplicate(_ item: TicItem) throws -> String

/// 일정의 시작/종료 시간을 변경 (날짜 간 이동 또는 같은 날 시간 변경에 사용)
func moveToDate(_ item: TicItem, newStart: Date, newEnd: Date) throws
```

**duplicate 구현 규칙:**
- `item.ekEvent`가 있으면 새 EKEvent를 생성 (title, notes, calendar, startDate, endDate, isAllDay 복사)
- `item.ekReminder`가 있으면 새 EKReminder 생성 (title, notes, calendar, dueDate 복사)
- **반복 규칙(recurrenceRules)은 복사하지 않는다** — 단일 일정으로 복제
- 알림(alarms)은 복사한다
- 생성 후 `eventStore.save()` 호출
- 새 identifier를 반환

**moveToDate 구현 규칙:**
- `item.ekEvent`가 있으면 `startDate`와 `endDate`를 newStart/newEnd로 변경 후 save
- `item.ekReminder`가 있으면 `dueDateComponents`를 newStart 기반으로 변경 후 save
- duration(기존 종료-시작 차이)은 유지하지 않음 — 호출자가 newStart와 newEnd를 명시적으로 전달

### 3. EventFormViewModel에 isAllDay 필드 추가

`tic/ViewModels/EventFormViewModel.swift`에 아래를 추가:

```swift
var isAllDay: Bool = false
```

**관련 로직:**
- `prepareForEdit` 시: `item.isAllDay` 값을 `isAllDay`에 할당
- `save` 시: `isCalendarType && isAllDay`이면 startDate/endDate를 하루 단위로 설정하고 EKEvent의 `isAllDay = true`로 저장
- `createEvent` 호출 시 `isAllDay` 파라미터를 전달할 수 있도록 EventKitService의 `createEvent` 시그니처에 `isAllDay: Bool = false` 파라미터 추가
- `update` 메서드에도 `isAllDay` 파라미터 추가

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodebuild build -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5
```

빌드 성공 (에러 없음). WARNING은 무시.

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/3-ux-enhance/index.json`의 phase 0 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- ContentState 구조 변경으로 `TicLiveActivityView.swift`, `LiveActivityService.swift`, `ContentView.swift`에서 컴파일 에러가 발생할 수 있다. **이 phase에서는 해당 파일들의 컴파일 에러만 최소한으로 수정**하라 (타입 맞추기, 임시 빈 배열 전달 등). UI 리디자인은 Phase 5에서 한다.
- `WidgetIntents.swift`에서 `TicActivityAttributes`를 참조할 수 있다. 컴파일 에러 발생 시 최소 수정.
- 기존 `EventKitService`의 `createEvent`, `update` 메서드 시그니처에 `isAllDay` 파라미터를 추가할 때 기본값(`= false`)을 반드시 지정하여 기존 호출 코드가 깨지지 않게 하라.
- `CGColor.hexString` extension이 이미 `LiveActivityService.swift`에 있다. 중복 정의하지 마라.
