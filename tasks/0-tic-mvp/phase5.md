# Phase 5: search-settings

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `/docs/prd.md` — 검색, 설정
- `/docs/flow.md` — F6 (검색), F8 (설정)
- `/docs/data-schema.md` — SearchHistory, CalendarSelection SwiftData 모델

그리고 이전 phase의 작업물을 반드시 확인하라:

- `/tic/Views/ContentView.swift` — showSearch, showSettings 상태
- `/tic/Models/SearchHistory.swift` — SwiftData 모델
- `/tic/Models/CalendarSelection.swift` — SwiftData 모델
- `/tic/Services/EventKitService.swift` — fetchEvents, fetchReminders, availableCalendars
- `/tic/ViewModels/EventFormViewModel.swift` — 일정 수정 연결 참고

이전 phase에서 만들어진 코드를 꼼꼼히 읽고, 설계 의도를 이해한 뒤 작업하라.

## 작업 내용

검색 화면과 설정(캘린더 선택) 화면을 구현한다.

### 1. `/tic/ViewModels/SearchViewModel.swift`

```swift
@Observable
class SearchViewModel {
    var query: String = ""
    var results: [Date: [TicItem]] = [:]  // 날짜별 그룹핑
    var isSearching: Bool = false
    
    func search(service: EventKitService) async
    
    // SearchHistory CRUD (SwiftData)
    func loadHistory(context: ModelContext)
    func saveHistory(context: ModelContext)
    func deleteHistory(_ item: SearchHistory, context: ModelContext)
    
    var recentSearches: [SearchHistory] = []
}
```

핵심 규칙:
- `search`: query가 비어있으면 results 초기화. 아니면:
  - EventKitService에서 과거 1년 ~ 미래 1년 범위로 이벤트 + 리마인더 fetch
  - title에 query가 포함된 항목 필터링 (대소문자 무시)
  - 결과를 날짜별로 그룹핑하여 `results`에 저장
  - 날짜 키는 startDate의 startOfDay (시간 없는 리마인더는 dueDate 또는 "날짜 없음" 별도 섹션)
- `saveHistory`: 검색 실행 시 query를 SearchHistory로 저장. 중복 제거 (같은 query면 searchedAt만 업데이트).
- `recentSearches`: searchedAt 내림차순, 최대 20개.

### 2. `/tic/Views/SearchView.swift`

Navigation push로 표시되는 검색 화면.

```swift
struct SearchView: View {
    @State private var viewModel = SearchViewModel()
    var eventKitService: EventKitService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack {
                // 검색바
                // query가 비어있으면: 최근 검색 기록
                // query가 있으면: 검색 결과 (날짜별 섹션)
            }
            .navigationTitle("검색")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.query, prompt: "일정 검색...")
        }
    }
}
```

검색 결과 UI:
- 날짜별 섹션: `Section(header: Text("4월 16일 (수)"))` 
- 각 결과 항목: 시간 + 제목 + 캘린더 색상 인디케이터
- 항목 탭 → EventFormView로 수정 모드 진입 (sheet)

최근 검색 기록 UI:
- 각 항목: 검색어 텍스트 + ✕ 삭제 버튼
- 탭 → 해당 검색어로 검색 실행
- ✕ → `viewModel.deleteHistory(item, context:)`

`.searchable` 연동:
- `onChange(of: viewModel.query)` 에서 debounce 후 검색 실행
- 또는 `.onSubmit(of: .search)`에서 검색 실행 + 기록 저장

### 3. `/tic/Views/SettingsView.swift`

캘린더/리마인더 목록 토글 bottom sheet.

```swift
struct SettingsView: View {
    var eventKitService: EventKitService
    @Environment(\.modelContext) private var modelContext
    @Query private var selections: [CalendarSelection]
    
    var body: some View {
        NavigationStack {
            List {
                Section("캘린더") {
                    ForEach(eventKitService.availableCalendars(), id: \.calendarIdentifier) { calendar in
                        // 색상 원 + 캘린더 이름 + Toggle
                    }
                }
                Section("미리 알림") {
                    ForEach(eventKitService.availableReminderLists(), id: \.calendarIdentifier) { list in
                        // 색상 원 + 리스트 이름 + Toggle
                    }
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
```

토글 동작:
- CalendarSelection이 존재하면 `isEnabled` 값 사용.
- 존재하지 않으면 기본 true (첫 실행 시 전체 활성화).
- 토글 변경 → CalendarSelection upsert (있으면 업데이트, 없으면 생성).

### 4. EventKitService에 CalendarSelection 반영

EventKitService의 fetch 메서드들이 CalendarSelection의 `isEnabled` 상태를 반영해야 한다:
- 비활성화된 캘린더의 이벤트/리마인더는 fetch 결과에서 제외.
- 방법: fetch 후 CalendarSelection을 조회하여 필터링. 또는 predicate에 calendars 파라미터로 활성화된 것만 전달.
- ModelContext를 EventKitService에 직접 넣지 말고, **ContentView 레벨에서 활성화된 calendarIdentifier 리스트를 EventKitService에 전달**하는 방식이 깔끔하다.

### 5. ContentView에서 SearchView, SettingsView 연결

- 🔍 아이콘 탭 → `NavigationLink` 또는 `.sheet`으로 SearchView 표시
- ⚙️ 아이콘 탭 → `.sheet`으로 SettingsView 표시 (bottom sheet)
- SearchView에서 일정 탭 시 EventFormView 표시 (수정 모드)

### 6. xcodegen 재생성

파일 추가 후 `xcodegen generate` 실행.

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodegen generate && xcodebuild build -project tic.xcodeproj -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -1 | grep -q "BUILD SUCCEEDED"
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/0-tic-mvp/index.json`의 phase 5 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.
작업 중 사용자 개입이 반드시 필요한 상황이 발생하면 status를 `"blocked"`로, `"blocked_reason"` 필드에 사유를 기록하고 작업을 즉시 중단하라.

## 주의사항

- `@Query`는 SwiftUI View에서만 사용 가능. ViewModel에서는 `ModelContext`를 통해 직접 fetch.
- `.searchable`은 NavigationStack 안에서 사용해야 검색바가 정상 표시됨.
- 검색 범위 (과거 1년 ~ 미래 1년)는 EventKit predicate에서 설정. 너무 넓은 범위는 성능 이슈.
- CalendarSelection 첫 실행 로직: DB에 아무 레코드도 없으면 모든 캘린더가 활성화된 것으로 간주.
- 시뮬레이터 이름이 `iPhone 16`이 아닐 수 있다. `xcrun simctl list devices available`로 확인하고 적절히 조정하라.
