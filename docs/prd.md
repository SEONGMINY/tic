# tic — 제품 요구사항 문서 (PRD)

## 개요
Apple Calendar 이벤트와 Apple Reminders를 하나의 미니멀 인터페이스로 통합하는 iOS 캘린더/리마인더 앱. 로컬 전용, 서버 없음, 인증 없음.

**목표:** 빠른 MVP → 시장 검증 → YC 지원.
**철학:** 빠르게 출시하되 안정적으로. 최소 화면, 최소 UI. 금융 앱 스타일의 미니멀 심미성.

## 타겟
- iOS 17+
- Bundle ID: `com.tic.app`

## 핵심 기능

### 캘린더 뷰
- **월간 뷰** (기본): 그리드에 일정 있는 날 오렌지 점 표시. 오늘은 오렌지 원. 날짜 탭 → 일간 뷰. Pinch out → 년간 뷰. 왼쪽 하단 "이번달" floating 버튼 → 이번 달로 스크롤. drag session 중에도 month scope는 유지될 수 있으며, 날짜 셀 hover로 `activeDate`를 갱신한다. hover 판정은 `global coordinates` 기준 frame hit-test를 사용한다.
- **년간 뷰**: 12개월 미니 그리드. 월 탭 → 월간 뷰. Pinch in → 월간 뷰. 왼쪽 하단 "올해" floating 버튼. drag session 중에는 year scope에서도 날짜 hover와 drop 후보 계산을 지원한다. scope 교체 중에도 root overlay는 유지된다.
- **일간 뷰**: "다음 행동" 카드 (오늘만) + 주간 스트립 + 24시간 타임라인 + 리마인더 체크리스트 FAB. 좌우 스와이프로 날짜 이동 (주간 스트립 + 타임라인 독립 slide 애니메이션). Pinch out → 월간 뷰.
- **MVP에서 주간 뷰 제외.**

### 일정 관리
- **생성**: + 버튼 (빈 폼), 타임라인 빈 영역 long press (시간 자동 입력 + phantom block 표시), 시간 라벨 long press (동일 동작). Bottom sheet 폼 (`.medium` 기본 + `.large` 확장).
- **조회**: EventKit이 Single Source of Truth. 캘린더 이벤트 + 리마인더를 `TicItem`으로 통합.
- **수정**: 일정 블록 탭 → 수정 bottom sheet.
- **삭제**: 편집 모드 toolbar 또는 수정 화면. 확인 alert 필수.
- **복제**: 편집 모드 toolbar. 같은 시간에 즉시 배치, 반복 규칙 제외.
- **반복**: 없음 / 매일 / 매주 / 2주마다 / 매월 / 매년.

### 타임라인 편집 모드
이벤트 블록 long press(0.5초) → 편집 모드 진입. haptic 피드백.

애니메이션은 미관이 아니라 상태 이해를 위한 피드백 수단이다. 사용자는 블록이 붙어 있는 요소에서 떠다니는 조작 대상으로 바뀌는 순간과, scope 전환 뒤에도 같은 객체를 계속 잡고 있다는 점을 즉시 이해해야 한다.

cross-scope move의 시작은 `bounded handoff`다.

- drag 시작 직후 source 내부 local preview는 즉시 lift된다.
- root ownership은 explicit `touch claim` 성공 후에만 넘어간다.
- `source block -> placeholder` 전환이 root claim보다 먼저 일어나면 안 된다. local preview와 root overlay가 동시에 active owner가 되면 안 된다.
- root handoff는 `global coordinates`로 정규화된 frame과 pointer만 사용한다. local/global 좌표 혼용은 금지한다.
- `captureTouch(near:)`의 동기 성공을 drag 시작 게이트로 두면 root recognizer가 아직 touch를 관측하지 못한 첫 프레임에서 drag가 시작조차 안 될 수 있다.

| 기능 | 상세 |
|------|------|
| 꼭짓점 리사이즈 | 상단-우측(시작시간), 하단-좌측(종료시간) 핸들. 15분 단위 스냅. 최소 30분. 핸들 옆 tooltip으로 시간 실시간 표시 |
| 블록 이동 (같은 날) | 블록 본체 y축 드래그. 15분 단위 스냅. 자동 스크롤 지원 |
| 블록 이동 (날짜 간) | cross-day move도 별도 local fallback 없이 단일 `root drag path`로 처리한다. drag 시작 직후 local preview가 lift되고, explicit `touch claim` 성공 후에만 원본 블록이 placeholder/ghost로 남고 실제 이동 블록이 root `single overlay`로 넘어간다. claim pending 동안에는 placeholder를 켜지 않는다. |
| 블록 이동 (scope 간) | `pinch scope transition`은 문서상의 제스처가 아니라 실제 구현 대상이다. drag session은 day → month/year 전환 중에도 유지되며, root `CalendarDragCoordinator`가 전역 overlay와 session lifetime을 소유한다. full card는 `timelineCard`로 남아 있다가 scope transition 시작 시점에 익명 `calendarPill`로 단순화된다. month/year hover 계산은 root ownership 이후에만 활성화된다. |
| drag 피드백 | pointer 이동과 overlay 이동은 drag 중 거의 즉시 일치해야 한다. 연속 drag follow와 hover update는 빠르게 지나가야 하고, per-frame animation으로 손가락을 늦게 따라가게 만들지 않는다. `touch claim` pending은 `2 frame 이내의 매우 짧은 window`로만 허용한다. |
| drop 계산 | day timeline은 `dateCandidate`, `minuteCandidate`를 둘 다 갱신한다. month/year는 `selectedDate`를 commit 전까지 유지하고 `activeDate`만 갱신하며 `minuteCandidate`는 drag session이 유지한다. 최종 drop은 `drop on touch up`으로만 끝나고 `dateCandidate + minuteCandidate + duration`으로 계산한다. 성공 후 `selectedDate`와 화면 scope는 결과 날짜의 day 기준으로 맞춘다. Swift와 Python이 동일한 규칙을 사용한다. |
| 표현 단순화 | full card는 lift와 landing에서는 충분히 보이되, month/year 탐색 중에는 제목 텍스트와 핸들을 제거한 익명 capsule만 보여준다. month와 year 모두 `same pill length`를 유지해 같은 객체처럼 인지되게 한다. |
| 강조 타이밍 | 강조가 필요한 구간은 `lift`, `scope transition 시작`, `landing`, `restore`다. 반대로 hover update와 drag follow는 눈에 띄지 않을 정도로 빠르게 지나가야 한다. |
| 오류 처리 | invalid drop, overflow, hover 미확정, cancel, `touch claim` 실패/timeout은 clamp보다 `restore-first policy`를 우선한다. 성공 commit 시에만 편집 모드 종료. cancel / invalid drop / restore에서는 편집 모드를 강제로 종료하지 않는다. legacy `edge-hover` fallback은 제거 대상이다. |
| Floating toolbar | [삭제 \| 복제]. 블록 아래 (공간 부족 시 위). `.ultraThinMaterial` + cornerRadius(12) |
| 해제 | 빈 영역 탭. 편집 중 블록 탭 → toolbar만 닫힘. 다른 블록 long press → 전환 |

### bounded handoff 관측성

- 기록 대상: `drag_start`, `root_claim_success`, `root_claim_timeout`, `restore_reason`, `claim_latency_ms`
- stale claim success / stale end / stale cancel은 현재 token과 맞지 않으면 무시한다.
- 이 관측성은 디버그와 회귀 재현을 위한 것이다. hot path마다 무거운 로깅을 추가하는 용도가 아니다.

### Drag 실험기
- `experiments/draglab/`에서 Python CLI 기반 drag 실험기를 운영한다.
- 입력은 `sessions.json`, `events.json`, `expected.json` 세 파일을 사용한다.
- 목적은 threshold, 상태 전이, geometry 계약, 채점 규칙을 빠르게 반복 검증하고, Swift에 동일한 계산 기준을 옮기는 것이다.
- Swift 포팅은 `CalendarDragCoordinator`, `DragSessionEngine`, `ticTests` 기반으로 진행한다.
- cross-day / cross-scope move는 SwiftUI local completion 경로를 섞지 않고 단일 `root drag path`만 사용한다.
- `minuteCandidate`, `activeDate`, drop validity, restore 정책은 Python `draglab` 계약과 동일해야 한다.
- 테스트는 mock-heavy UI 테스트보다 순수 로직 XCTest를 우선한다.
- 병렬 실험은 세션 내부가 아니라 `config` 또는 `session chunk` 단위로만 수행한다.

### 일정 추가 폼
| 필드 | 필수 | 기본값 | 비고 |
|------|------|--------|------|
| 타입 선택 | — | 이벤트 | Segmented Control `[이벤트 \| 미리 알림]`. 수정 모드에서 숨김 |
| 제목 | 예 | — | 타입 전환 시 유지 |
| 설명 | 아니오 | — | |
| 하루 종일 | 아니오 | 꺼짐 | 이벤트만. 켜면 날짜만, 꺼면 날짜+시간 |
| 캘린더 | 예 | — | 이벤트: 캘린더 목록만 / 미리 알림: 리마인더 목록만. 타입 전환 시 초기화 |
| 시작/종료 | 캘린더: 예, 리마인더: 선택 | 09:00–10:00 | |
| 반복 | 아니오 | 없음 | 6가지 옵션 |
| 알림 | 아니오 | 30분 전 | 없음/5분/15분/30분/1시간 |

전체 폼 스타일: 기본 Form보다 큰 cornerRadius 적용.

### 검색
- 진입: 🔍 아이콘 → navigation push.
- 빈 상태: 최근 검색 기록, 개별 삭제 가능.
- 입력 시: 실시간 필터링, 날짜별 그룹핑. 과거 + 미래 전체.
- 결과 탭 → 일정 상세 bottom sheet.

### 설정
- 진입: ⚙️ 아이콘 → bottom sheet.
- 캘린더/리마인더 리스트 토글. 첫 실행 시 전체 활성화.

### 알림
- 일정 시간에 로컬 알림 발송.
- 액션: 완료 / 10분 후 다시 알림.
- 백그라운드에서 사용자가 알림 탭 시 Live Activity 시작 트리거.

### Live Activity
| 항목 | 결정 |
|------|------|
| 시작 | 포그라운드: 30분 전 자동. 백그라운드: 사용자가 알림 탭 |
| 데이터 | 오늘의 전체 일정 (최대 10개) 타임라인 표시 |
| Lock Screen | tic 로고 + 카운트다운 + progress line (실선=경과, 점선=남은) + dot(각 일정, 캘린더 색상) + "지금/다음" 일정 표시 |
| Dynamic Island | Expanded: 축소된 progress line. Compact: tic + 제목 + 카운트다운. Minimal: progress 원형 |
| 카운트다운 | 일정 1개: 현재 남은 시간. 여러 일정: 다음 일정까지 남은 시간. 모든 종료 후: 숨김 |
| 종료 | 유저 수동 종료. 모든 일정 끝나면 실선 꽉 찬 상태로 계속 표시 |
| Progress 갱신 | `TimelineView(.periodic)` 기반 자동 갱신 |
| 연속 일정 | 전체 타임라인에 이미 포함 |
| 탭 | 해당 날짜 DayView로 앱 열기 |

### 위젯
| 크기 | 내용 | 인터랙션 | 딥링크 |
|------|------|----------|--------|
| Small | 다음 일정 1개 | 완료/스누즈 | 해당 날짜 일간 뷰 |
| Medium | 다음 3-4개, "+N개 더" | 완료/스누즈 | 해당 날짜 일간 뷰 |

### 권한
| 권한 | 요청 시점 | 거부 시 |
|------|-----------|---------|
| 캘린더 + 리마인더 | 첫 실행 (동시) | 빈 캘린더로 앱 동작 |
| 알림 | 첫 일정 생성 시 | 알림 없이 앱 동작 |

## 디자인
- **색상**: 무채색 기반 + 오렌지 포인트. 이벤트 블록은 캘린더 고유 색상.
- **톤**: 미니멀, 금융 앱 스타일. 둥근 cornerRadius 적극 활용.
- **다크 모드**: SwiftUI 시스템 컬러로 자동 대응.

## 인터랙션
| 제스처 | 컨텍스트 | 동작 |
|--------|----------|------|
| 날짜 탭 | 월간 뷰 | → 일간 뷰 |
| pinch out | 일→월→년 | scope 확대. drag session 중에도 같은 `pinch scope transition` 경로를 사용한다. |
| pinch in | 년→월→일 | scope 축소. month/year drop 성공 후에는 결과 날짜 기준으로 day scope로 복귀한다. |
| 이벤트 탭 | 일간 뷰 (기본 상태) | → 수정 bottom sheet |
| 이벤트 long press | 일간 뷰 | → 편집 모드 (핸들 + toolbar) |
| 빈 타임라인 long press | 일간 뷰 | → phantom block + 생성 sheet |
| 시간 라벨 long press | 일간 뷰 | → phantom block + 생성 sheet (빈 타임라인과 동일) |
| 좌우 스와이프 | 일간 뷰 (기본 상태) | 날짜 이동 |
| 블록 좌우 드래그 | 일간 뷰 (편집 모드) | 같은 session 안에서 `root drag path`를 시작한다. legacy `edge-hover` timer fallback은 제거 대상이다. |
| drag session 유지 | 일간 뷰 (편집 모드) | pinch 또는 다른 scope 전환 뒤에도 `CalendarDragCoordinator` session을 유지한다. |
| 날짜 셀 hover | 월간/년간 뷰 (drag session 중) | `selectedDate`는 유지하고 `activeDate`만 갱신한다. 강조는 항상 하나의 target만 유지한다. |
| drop | 월간/년간 뷰 (drag session 중) | `drop on touch up`으로만 끝난다. `activeDate + minuteCandidate + duration`이 유효할 때만 확정하고, 아니면 restore한다. 성공 후 `selectedDate`와 화면 scope는 결과 날짜의 day 기준으로 맞춘다. |
| 빈 영역 탭 | 일간 뷰 (편집 모드) | 편집 모드 해제 |
| "이번달" 탭 | 월간 뷰 | 이번 달로 스크롤 |
| "올해" 탭 | 년간 뷰 | 올해로 스크롤 |
| 📋 FAB 탭 | 일간 뷰 | 시간 없는 리마인더 bottom sheet |

## 네비게이션 바
좌: 년/월 레이블 (탭 → 오늘). 우: ⚙️ 🔍 +

## MVP 범위 밖
- 서버 / 데이터베이스
- 인증
- 주간 뷰
- 커스텀 반복 규칙
- Push-to-start (업그레이드 예정)
