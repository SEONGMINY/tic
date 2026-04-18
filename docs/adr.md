# tic — 아키텍처 결정 기록 (ADR)

## ADR-001: EventKit을 Single Source of Truth로 사용
모든 캘린더/리마인더 데이터는 EventKit에 저장. 로컬 복제 없음. `EKEventStoreChanged`로 자동 갱신. Apple이 iCloud 동기화 처리. 트레이드오프: 커스텀 필드 불가 — MVP에서 불필요.

## ADR-002: SwiftData는 메타데이터 전용
3개 모델만: SearchHistory, CalendarSelection, NotificationMeta. EventKit에 속하지 않는 것만 저장. 최소 스키마, 마이그레이션 복잡도 없음.

## ADR-003: iOS 17+ 최소 타겟
SwiftData, Interactive Widget, @Observable에 필수. iOS 17+ 점유율 90%+. iOS 16 지원 시 대비 복잡도 증가 대비 도달률 미미.

## ADR-004: @Observable 사용
@ObservableObject 대신 Observation 프레임워크. 세밀한 뷰 업데이트, 적은 보일러플레이트, 간단한 DI.

## ADR-005: 단순 MVVM
~25개 파일, 6개 화면, 1명 개발자 + AI. 이 규모에서 아키텍처 오버헤드는 납기 지연만 초래. ViewModel이 Service에 직접 접근. use-case/repository 레이어 없음.

## ADR-006: MVP에서 주간 뷰 제외
Pinch 네비게이션(일↔월↔년) 3단계로 깔끔. 주간 뷰 추가 시 계층 모호성 + 작업량 2배.

## ADR-007: 로컬 알림 + 사용자 탭으로 Live Activity 시작
백그라운드에서 Live Activity를 정확한 시점에 시작하려면 서버(APNs)가 필요 — "서버 없음" 제약 위반. 로컬 알림은 정확한 시간에 발송. 사용자가 탭 → 앱 열림 → LA 시작. 향후 APNs push-to-start로 업그레이드.

## ADR-008: Column-Packing 알고리즘
Apple Calendar 방식. 시작 시간 정렬 → 겹치는 클러스터 그룹화 → 탐욕적 열 할당 → 너비 분할. 뷰 body 바깥에서 미리 계산.

## ADR-009: ScrollView + ZStack (LazyVStack 아님)
이벤트는 임의 시간 범위에 걸치고 겹침 — 이산적 행에 매핑 불가. 하루 최대 ~30개 블록으로 lazy loading 불필요. GeometryReader는 최상위 1번만. 레이아웃 미리 계산 + 캐시.

## ADR-010: 위젯에 App Group UserDefaults
위젯은 빠르고 동기적인 읽기 필요. 소량 JSON 캐시에 공유 SwiftData보다 단순.

## ADR-011: 캘린더 고유 색상
무채색 UI + 컬러 이벤트 블록. 오렌지는 앱 크롬 전용. 사용자의 기존 Apple Calendar 색상 활용 — 설정 작업 제로.

## ADR-012: 권한 요청 전략
캘린더+리마인더: 첫 실행. 알림: 첫 일정 생성 시 지연 요청. 연속 팝업 3개 → 2개로 감소 + 맥락 제공.

## ADR-013: 제한적 반복 일정 지원
6가지 프리셋만. 커스텀 반복 UI는 MVP 대비 불균형적 노력. ~95% 사용 사례 커버. EventKit은 어떤 패턴이든 읽기 가능.

## ADR-014: Pinch 제스처 네비게이션
MagnifyGesture → scope 전환 + matchedGeometryEffect 애니메이션. Apple Calendar 기대 패턴.

## ADR-015: 년간 뷰에서 EventKit 쿼리 제거
미니 월 셀마다 쿼리 시 ~504개 → 프레임 드랍. 년간 뷰 목적은 "빠른 월 선택".

## ADR-016: 고정 범위 + LazyVStack 가상화
년간 1~9999년, 월간 ±120개월. 동적 확장은 @State 변경 → 무한 렌더 루프 위험.

## ADR-017: 월별 이벤트 일괄 캐시
`eventCountsForMonth()`로 월 전체 1회 fetch. 날짜별 개별 쿼리(30+개) 방지. EKEventStoreChanged 시 무효화.

## ADR-018: Live Activity에 안정적 레이아웃
`GeometryReader + Capsule` 기반. `position()` 커스텀 그래픽은 잠금화면/DI에서 레이아웃 깨짐 (실기기 확인). progress line은 `Path` + `StrokeStyle(dash:)` 로 실선/점선 구현.

## ADR-019: 커스텀 네비바 + UILaunchScreen
NavigationStack toolbar가 safe area 과도 차지. 커스텀 VStack 네비바로 완전 제어. UILaunchScreen 키 필수.

## ADR-020: 편집 모드 상태는 View @State
편집 모드(리사이즈, 이동, toolbar)는 트랜지언트 UI 상태. DayView의 @State로 관리, ViewModel에 넣지 않음. 이유: UI 제스처 상태와 서비스 레이어의 책임 경계 분리.

## ADR-021: 날짜 간 블록 이동은 overlay 패턴
드래그 중인 블록을 타임라인에서 분리 → DayView 최상위 overlay로 렌더링. 타임라인 전환 애니메이션과 드래그 상태가 독립 동작. `CrossDayDragState` 구조체로 관리.

## ADR-022: Live Activity ContentState 다중 이벤트
단일 이벤트 → `[ActivityEvent]` 배열 (최대 10개). 4KB 내에서 충분 (~2KB). `currentIndex`/`nextIndex`로 "지금/다음" UI + 카운트다운 대상 결정. progress line에 전체 일정 dot 표시.

## ADR-023: TimelineView 500줄 초과 시 EditableEventBlock 분리
편집 모드(핸들, 리사이즈, 이동, toolbar) 코드가 TimelineView를 비대하게 만들면 `EditableEventBlock.swift`로 분리. 개발자 인지 부하 감소 목적. ADR-005 정신(단순함) 유지하되, 파일당 가독성 우선.

## ADR-024: Cross-scope drag session은 단일 전역 overlay owner로 관리
day timeline에서 시작된 drag session은 month/year scope 전환 중에도 유지된다. 원본 블록은 placeholder/ghost처럼 남고, 실제 이동 중 블록은 단일 전역 overlay로 렌더링한다. 이유: scope 전환 시 뷰 계층이 바뀌어도 drag state가 끊기지 않아야 하고, 좌표 점프를 최소화할 수 있기 때문이다.

## ADR-025: Invalid drop은 clamp보다 restore를 우선
`activeDate` 미확정, `minuteCandidate` 없음, overflow, 금지된 drop zone 같은 경우는 가까운 값으로 강제 확정하지 않는다. 기본 정책은 `restore-first policy`다. 이유: 잘못된 일정 확정은 사용자가 복구하기 어렵고, 이 기능의 핵심 품질은 “자연스러운 이동”보다 “잘못 저장되지 않음”이 우선이기 때문이다.

## ADR-026: Python draglab을 Swift 계약/튜닝 기준 환경으로 사용
cross-scope drag는 threshold와 상태 전이가 많아 SwiftUI에서 바로 튜닝하기 비효율적이다. `experiments/draglab/`에서 JSON fixture 기반 replay, scoring, metric, parameter 탐색을 먼저 수행하고, 검증된 geometry/date/minute 규칙을 Swift로 이식한다. 병렬 실험은 세션 내부가 아니라 `config` 또는 `session chunk` 단위로만 수행한다.

## ADR-027: Cross-scope drag session owner는 scope switch 위의 단일 coordinator
`DayView`가 drag session owner이면 `ContentView.scopeView` 교체 시 session이 끊긴다. 그래서 실제 owner는 `ContentView` 수준의 `CalendarDragCoordinator` 하나로 둔다. `DayView`, `MonthView`, `YearView`는 pointer/frame/reporting만 담당하고, overlay와 session lifetime은 coordinator가 가진다.

## ADR-028: Swift drag 포팅은 `ticTests`와 `draglab` 계약으로 검증
SwiftUI gesture만으로 회귀를 잡으면 속도도 느리고 판단 기준도 흐려진다. 그래서 `DragSessionEngine`, geometry, hover hit-test는 `ticTests`의 순수 로직 XCTest로 먼저 검증한다. threshold와 최종 date/minute 계산 기준은 Python `draglab` fixture/score 계약과 일치해야 한다.

## ADR-029: cross-scope drag path는 pinch scope bridge와 root coordinator 하나로 통일
cross-day / cross-scope 이동은 여러 local fallback을 섞지 않고 단일 `root drag path`로 유지한다. `ContentView`가 `pinch scope transition` bridge owner이고, `CalendarDragCoordinator`가 session lifetime, overlay, cleanup을 맡는다. month/year drop이 성공하면 결과 날짜 기준으로 day scope로 복귀한다. legacy `edge-hover` timer fallback은 제거 대상이며, invalid drop 정책은 계속 `restore-first policy`를 따른다.

## ADR-030: cross-scope 동안 타임블록은 하나의 session identity를 유지하고 presentation만 바꾼다
cross-scope drag의 핵심은 블록이 사라졌다가 새로 생기는 것처럼 보이지 않는 것이다. 따라서 블록 identity는 drag session 전체에서 하나로 유지하고, 표현만 `timelineCard`와 `calendarPill` 사이에서 바꾼다. 실제 이동 객체는 항상 하나의 `single overlay`만 유지한다. month/year 날짜 강조도 하나의 `single active target`만 허용한다. `selectedDate`는 확정 전까지 유지하고, `activeDate`는 hover candidate로만 사용한다. 최종 확정은 `drop on touch up`만 허용하고, invalid drop은 계속 `restore-first policy`를 따른다. 성공 commit 시에만 편집 모드 종료다.

## ADR-031: drag ownership handoff는 bounded `touch claim` 계약으로 고정한다
이번 drag 고장의 핵심은 소유권 전환 순서가 느슨했다는 점이다. `source block -> placeholder` 전환이 root claim보다 먼저 일어나면 local preview와 root overlay가 동시에 owner처럼 보인다. local/global 좌표가 섞인 상태로 handoff를 진행하면 첫 프레임 점프와 잘못된 hit-test가 겹친다. `captureTouch(near:)`의 동기 성공을 drag 시작 조건으로 두면 root recognizer가 아직 touch를 관측하지 못한 첫 프레임에서 drag가 시작되지 않을 수 있다.

추가로 이번 회귀는 `ownership`과 `presentation continuity`를 같이 잠근 데서 나왔다. `rootClaimPending` 동안 `hover`, `placeholder`, `global drop ownership`을 막는 것은 맞지만, scope transition continuity까지 함께 꺼지면 블록이 사라진 것처럼 보인다.
이번 회귀는 거기서 한 단계 더 나아가, `render continuity`만 복구하고 `touch tracking relay`는 복구하지 않았기 때문에 `보이지만 더 이상 움직이지 않는 카드`를 만든 점도 포함한다.

결정:

- `bounded handoff`는 local preview 즉시 lift → explicit `touch claim` 성공 → root ownership 전환 순서로만 진행한다.
- claim pending 동안에는 source placeholder, month/year `activeDate` hover, `global drop ownership`을 켜지 않는다.
- `render visibility`, `interaction ownership`, `touch tracking relay`는 별도 정책으로 분리한다.
- `rootClaimPending` 중에도 scope transition continuity는 유지될 수 있다. 다만 이것은 `render continuity`이지 `ownership transfer`가 아니다.
- `rootClaimPending + non-day`에서는 같은 live touch를 따라가는 `touch tracking relay`를 유지할 수 있다. 다만 이것도 `ownership transfer`는 아니다.
- `day` 내부 local preview와 `non-day` continuity overlay는 같은 책임이 아니다.
- `rootClaimPending` 상태에서 day → month/year로 전환되면 블록은 사라지지 않고 `holding card`로 유지된다. 이 카드는 마지막으로 확인된 day overlay frame에 잠깐 고정된다.
- `touch tracking relay`가 붙어 있으면 이 `holding card`는 손가락을 계속 따라가야 한다.
- claim 성공 전에는 `calendarPill`, month/year `activeDate` hover, source placeholder, `global drop ownership`을 켜지 않는다.
- `calendarPill` morph는 `claim 후 morph` 정책을 따른다. claim 성공 전에는 full card를 유지한다.
- `pending + non-day` 상태에서 touch up 하면 commit이 아니라 `restore-first policy`로 복귀한다.
- claim window는 `2 frame 이내의 매우 짧은 window`로 유지한다. 실패나 timeout이면 `restore-first policy`로 즉시 복구한다.
- `selectedDate`는 commit 전까지 바꾸지 않는다. `activeDate`는 root ownership 이후 month/year hover candidate로만 사용한다.
- stale claim success / stale end / stale cancel은 현재 token과 맞지 않으면 무시한다.
- 최소 관측성 이벤트는 `drag_start`, `root_claim_success`, `root_claim_timeout`, `restore_reason`, `claim_latency_ms`다.
- 이 관측성은 디버그와 회귀 재현용이다. hot path마다 무거운 로깅을 추가하는 목적이 아니다.
