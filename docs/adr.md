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
