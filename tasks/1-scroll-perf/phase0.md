# Phase 0: infinite-scroll

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `/docs/prd.md` — 캘린더 뷰 요구사항
- `/docs/code-architecture.md` — MVVM + Service Layer 패턴
- `/docs/adr.md` — ADR-009 (ScrollView+ZStack), 성능 규칙

그리고 이전 코드를 반드시 확인하라:

- `/tic/Views/Calendar/MonthView.swift` — 현재 월간 뷰 (수정 대상)
- `/tic/Views/Calendar/YearView.swift` — 현재 년간 뷰 (수정 대상)
- `/tic/Services/EventKitService.swift` — `eventCountsForMonth()`, 메모리 캐시
- `/tic/ViewModels/CalendarViewModel.swift` — `displayedYear`, `daysInMonth()`
- `/tic/Views/ContentView.swift` — scope 전환, `displayedYear` 바인딩

이전 phase에서 만들어진 코드를 꼼꼼히 읽고, 설계 의도를 이해한 뒤 작업하라.

## 작업 내용

MonthView와 YearView에 무한 스크롤을 구현한다. **핵심 원칙: 범위 확장과 이벤트 로딩을 분리하여 EventKit 쿼리 폭주를 방지.**

### 이전 실패 원인 (반드시 숙지)

이전 구현에서 `onAppear`로 범위를 동적 확장했을 때:
1. 새 MonthSection이 렌더링됨
2. 각 MonthSection의 `.task`에서 `eventCountsForMonth()` 호출
3. EventKit에 대량 쿼리 → `CADDatabaseFetchCalendarItemsWithPredicate` 에러 발생

**이 에러를 절대 재발시키지 마라.**

### 1. MonthView 무한 스크롤

**구조:**
```
[anchorMonth] — 뷰 최초 생성 시 고정 (viewModel.displayedMonth)
[monthsBefore: @State Int] — 초기값 48
[monthsAfter: @State Int] — 초기값 48

monthPages() = anchorMonth 기준 (-monthsBefore...monthsAfter) 오프셋으로 Date 배열 생성
```

**범위 확장 조건:**
- 끝에서 5번째 월이 `onAppear`될 때 확장 (끝 도달이 아님)
- 한 번에 24개월씩 확장
- `monthPages()`는 `@State` 변수(monthsBefore/monthsAfter)에만 의존
- `viewModel.displayedYear` 같은 `@Observable` 프로퍼티 변경으로 `monthPages()` 재계산이 발생하면 안 됨

**이벤트 로딩 (쿼리 폭주 방지):**
- MonthSection은 별도 View로 분리
- 이벤트 수는 MonthSection 내부의 `.task`에서 로드
- `@State private var eventCounts: [Int: Int]?` — nil이면 미로드, 로드 후 캐시
- 이미 로드된 월은 재쿼리하지 않음
- EventKitService의 `eventCountsForMonth()`에도 메모리 캐시 적용 (이미 구현됨)

**년도 라벨 업데이트:**
- MonthSection의 `onAppear`에서 `viewModel.displayedYear = month.year` 설정
- 이 변경이 `monthPages()` 재계산을 트리거하면 안 됨 (monthPages가 displayedYear에 의존하지 않도록)

**검증 포인트:**
- 위로 스크롤하면 과거 월이 계속 로드됨
- 아래로 스크롤하면 미래 월이 계속 로드됨
- 빠르게 스크롤해도 EventKit 에러 없음
- 좌상단 년도가 보이는 월에 맞게 변경됨

### 2. YearView 무한 스크롤

**동일 패턴 적용:**
- `anchorYear` 고정, `yearsBefore/yearsAfter` @State
- 끝에서 3번째 년도 `onAppear` 시 10년씩 확장
- **년간 뷰에서 EventKit 쿼리 없음** (이벤트 점 표시 안 함 — 성능 최적화)
- 순수 UI 렌더링만

### 3. project.yml 변경 불필요

파일 구조 변경 없음. 기존 파일만 수정.

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodegen generate && xcodebuild build -project tic.xcodeproj -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -1 | grep -q "BUILD SUCCEEDED"
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/1-scroll-perf/index.json`의 phase 0 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- **`monthPages()` 함수가 `@Observable` 프로퍼티에 의존하면 안 된다.** `@State` 변수와 `anchorMonth`(상수)에만 의존해야 무한 렌더 루프를 방지할 수 있다.
- MonthSection의 `.task`에서 EventKit 쿼리 시, 이미 로드된 경우(`eventCounts != nil`) 스킵해야 한다.
- `onAppear`에서 범위 확장 시, 끝 도달이 아닌 **끝에서 5번째**에서 미리 확장하여 스크롤 끊김을 방지한다.
- 시뮬레이터 이름이 `iPhone 16`이 아닐 수 있다. `xcrun simctl list devices available`로 확인하고 적절히 조정하라.
- `xcodegen generate`를 먼저 실행하라.
