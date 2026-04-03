# tic — 아키텍처 결정 기록 (ADR)

## ADR-001: EventKit을 Single Source of Truth로 사용
**결정:** 모든 캘린더/리마인더 데이터는 EventKit에 저장. 로컬 복제 없음.

**맥락:** 앱이 Apple Calendar과 Reminders와 동기화해야 한다. SwiftData에 데이터를 복제하면 양방향 동기화 로직이 필요 — 복잡하고, 오류 발생 쉽고, 불필요하다.

**결과:** EventKit에 직접 쓰기/읽기. `EKEventStoreChanged` 노티피케이션으로 자동 갱신. 동기화 버그 없음. Apple이 iCloud 동기화를 무료로 처리.

**트레이드오프:** EventKit이 지원하지 않는 커스텀 필드 추가 불가. 수용 — MVP에서 커스텀 필드 불필요.

---

## ADR-002: SwiftData는 메타데이터 전용
**결정:** SwiftData에 3개 모델만 저장: SearchHistory, CalendarSelection, NotificationMeta.

**맥락:** 검색 기록(UX), 캘린더 가시성 설정(앱 고유), 스누즈 상태(일시적)를 영속화해야 한다. 이 중 어느 것도 EventKit에 속하지 않는다.

**결과:** 최소 스키마. 마이그레이션 복잡도 없음. SwiftData 컨테이너가 가볍다.

---

## ADR-003: iOS 17+ 최소 타겟
**결정:** iOS 17이 최소 지원 버전.

**맥락:** SwiftData, Interactive Widget (WidgetKit의 App Intents), @Observable에 필수. iOS 17+ 점유율 90% 이상. iOS 16 지원 시 Core Data로 전환 + 위젯 인터랙션 불가 — 미미한 도달률 대비 상당한 복잡도 증가.

**결과:** SwiftData, @Observable, Interactive Widget, 최신 SwiftUI API 전부 사용 가능.

---

## ADR-004: @Observable 사용 (@ObservableObject 대신)
**결정:** 모든 상태 관리에 Observation 프레임워크(`@Observable`) 사용.

**맥락:** iOS 17+ 타겟이므로 사용 가능. @Observable은 세밀한 뷰 업데이트(변경된 속성을 읽는 뷰만 리렌더), 적은 보일러플레이트(`@Published` 불필요), 간단한 DI(`@EnvironmentObject` 래퍼 불필요)를 제공.

---

## ADR-005: 단순 MVVM, 무거운 아키텍처 미사용
**결정:** MVVM + Service layer. Clean Architecture, VIPER, TCA, coordinator 패턴 미사용.

**맥락:** ~25개 파일, 6개 화면, 1명 개발자 + AI 에이전트. 이 규모에서 아키텍처 오버헤드는 납기 지연만 초래하고 이점이 없다. 앱이 성장하면 단순 MVVM에서 리팩토링하기 쉽다.

**결과:** ViewModel이 Service에 직접 접근. use-case/interactor 레이어 없음. repository 패턴 없음.

---

## ADR-006: MVP에서 주간 뷰 제외
**결정:** 년간/월간/일간만 출시.

**맥락:** Pinch 네비게이션(일↔월↔년)이 3단계로 깔끔하다. 주간 뷰 추가 시 pinch 계층 모호성(일→주→월→년?) + 타임라인 구현 작업 2배. 주간 뷰는 월간/일간 대비 사용자 가치 낮음.

**결과:** 추후 선택적 scope로 아키텍처 변경 없이 추가 가능.

---

## ADR-007: 로컬 알림 + 사용자 탭으로 Live Activity 시작
**결정:** 백그라운드에서는 사용자가 로컬 알림을 탭할 때 Live Activity 시작. 포그라운드에서는 자동 시작.

**맥락:** 백그라운드에서 Live Activity를 시작하려면:
- BGAppRefreshTask: ±5분 타이밍 불확실성 — 리마인더 앱에서 허용 불가
- Push-to-start (APNs): 서버 필요 — "서버 없음" 제약 위반
- Notification extensions: NSE/NCE에서 ActivityKit 접근 불가

로컬 알림은 정확한 시간에 발송된다. 사용자가 탭하면 앱이 열리면서 Live Activity 시작. 사용자가 탭하지 않으면 — 폰을 보고 있지 않으므로 Live Activity가 있어도 의미 없음.

**향후:** 서버 인프라 추가 시 APNs push-to-start로 무인터랙션 Live Activity 시작으로 업그레이드.

---

## ADR-008: 겹치는 일정에 Column-Packing 알고리즘
**결정:** 타임라인 레이아웃에 탐욕적 column-packing 알고리즘 사용.

**맥락:** Apple Calendar이 사용하는 방식. 시간이 겹치는 이벤트를 나란히 열에 배치, 각 열에 동일한 너비 비율. 알고리즘: 시작 시간 정렬 → 겹치는 클러스터 그룹화 → 탐욕적 열 할당 → 너비 분할.

**결과:** SwiftUI 뷰 body 바깥에서 레이아웃 속성 미리 계산하여 매 렌더마다 재계산 방지. 날짜별 캐시.

---

## ADR-009: 타임라인에 ScrollView + ZStack (LazyVStack 아님)
**결정:** 일간 타임라인은 ScrollView 안에 ZStack + absolute positioning (.offset + .frame) 사용.

**맥락:** 이벤트는 임의의 시간 범위에 걸치고 겹친다 — 이산적 행에 매핑되지 않음. LazyVStack은 균일하고 겹치지 않는 행에 설계됨. 하루 최대 24개 시간 라인 + ~10-30개 이벤트 블록 — lazy loading의 이점을 얻기엔 너무 적음.

**성능 규칙:**
- GeometryReader는 최상위에서 1번만, 반복 뷰 안에 넣지 않기
- 레이아웃 속성 미리 계산하고 캐시
- TicItem에 Equatable 적용하여 리렌더 최소화

---

## ADR-010: 위젯 데이터에 App Group UserDefaults 사용
**결정:** 공유 SwiftData가 아닌 App Group UserDefaults로 위젯과 데이터 공유.

**맥락:** 위젯은 타임라인 생성 시 빠르고 동기적인 읽기가 필요. UserDefaults가 더 단순하고 소량의 다음 일정 JSON 캐시에 충분. 메인 앱이 EventKit 변경마다 캐시 업데이트 + `WidgetCenter.shared.reloadAllTimelines()` 호출.

---

## ADR-011: 이벤트 블록에 캘린더 고유 색상 사용
**결정:** 균일한 오렌지가 아닌 각 캘린더의 네이티브 EKCalendar.cgColor 사용.

**맥락:** 무채색 UI + 컬러 이벤트 블록은 UI 복잡도 추가 없이 캘린더 시각적 구분을 제공. 오렌지 포인트는 앱 크롬(오늘 표시, 버튼, 강조)에 예약. 캘린더 색상은 사용자의 기존 Apple Calendar 설정에서 가져옴 — 설정 작업 제로.

---

## ADR-012: 권한 요청 전략
**결정:** 캘린더 + 리마인더는 첫 실행 시. 알림은 첫 일정 생성 시 지연 요청.

**맥락:** 3개 연속 권한 팝업은 마찰을 유발. 알림 권한을 첫 일정 생성으로 지연하면:
1. 첫 실행 팝업 3개 → 2개로 감소 (EventKit이 캘린더+리마인더 묶음)
2. 맥락 제공 — 사용자가 방금 일정을 만들었으므로 알림 권한이 자연스러움
3. 거부해도 앱 동작 (알림만 없음)

---

## ADR-013: 제한적 반복 일정 지원
**결정:** 6가지 프리셋 반복 규칙 지원. 커스텀 반복 편집기 없음.

**옵션:** 없음 / 매일 / 매주 / 2주마다 / 매월 / 매년

**맥락:** EventKit의 EKRecurrenceRule은 복잡한 패턴(매월 셋째 화요일 등)을 지원하지만, 커스텀 반복 UI 구축은 MVP 대비 불균형적 노력. 6가지 프리셋이 ~95% 사용 사례를 커버. EventKit은 어떤 반복 패턴이든 읽기 가능 — 생성만 제한.

---

## ADR-014: Pinch 제스처 네비게이션
**결정:** MagnifyGesture로 scope 전환 + matchedGeometryEffect 애니메이션.

**맥락:** Apple Calendar이 사용하는 패턴 — 사용자가 기대하는 방식. 구현: `MagnifyGesture`가 scale < 임계값 → 축소 (일→월→년), scale > 임계값 → 확대 (년→월→일). `matchedGeometryEffect`가 매칭된 캘린더 셀 간 전환 애니메이션.

**상태:** `enum CalendarScope { case year, month, day }`가 렌더링할 뷰 결정.
