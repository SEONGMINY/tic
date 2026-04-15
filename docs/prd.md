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
- **월간 뷰** (기본): 그리드에 일정 있는 날 오렌지 점 표시. 오늘은 오렌지 원. 날짜 탭 → 일간 뷰. Pinch out → 년간 뷰. 왼쪽 하단 "이번달" floating 버튼 → 이번 달로 스크롤. drag session 중에도 month scope는 유지될 수 있으며, 날짜 셀 hover로 `activeDate`를 갱신한다.
- **년간 뷰**: 12개월 미니 그리드. 월 탭 → 월간 뷰. Pinch in → 월간 뷰. 왼쪽 하단 "올해" floating 버튼. drag session 중에는 year scope에서도 날짜 hover와 drop 후보 계산을 지원한다.
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

| 기능 | 상세 |
|------|------|
| 꼭짓점 리사이즈 | 상단-우측(시작시간), 하단-좌측(종료시간) 핸들. 15분 단위 스냅. 최소 30분. 핸들 옆 tooltip으로 시간 실시간 표시 |
| 블록 이동 (같은 날) | 블록 본체 y축 드래그. 15분 단위 스냅. 자동 스크롤 지원 |
| 블록 이동 (날짜 간) | 블록 본체 좌우 드래그 → 타임라인 slide 전환 → 새 날짜에 배치. 손가락 위치 기준. overlay 패턴으로 구현 |
| 블록 이동 (scope 간) | drag session은 day → month/year 전환 중에도 유지. 전역 overlay가 손가락과 함께 이동하고, 원본 블록은 placeholder/ghost처럼 남는다. |
| drop 계산 | day timeline은 `dateCandidate`, `minuteCandidate`를 둘 다 갱신. month/year는 `activeDate`만 갱신하고 `minuteCandidate`는 drag session이 유지. 최종 drop은 `dateCandidate + minuteCandidate + duration`으로 계산한다. |
| 오류 처리 | invalid drop, overflow, hover 미확정, cancel은 clamp보다 `restore-first policy`를 우선한다. |
| Floating toolbar | [삭제 \| 복제]. 블록 아래 (공간 부족 시 위). `.ultraThinMaterial` + cornerRadius(12) |
| 해제 | 빈 영역 탭. 편집 중 블록 탭 → toolbar만 닫힘. 다른 블록 long press → 전환 |

### Drag 실험기
- `experiments/draglab/`에서 Python CLI 기반 drag 실험기를 운영한다.
- 입력은 `sessions.json`, `events.json`, `expected.json` 세 파일을 사용한다.
- 목적은 threshold, 상태 전이, geometry 계약, 채점 규칙을 빠르게 반복 검증하고, Swift에 동일한 계산 기준을 옮기는 것이다.
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
| Pinch out | 일→월→년 | scope 확대 |
| Pinch in | 년→월→일 | scope 축소 |
| 이벤트 탭 | 일간 뷰 (기본 상태) | → 수정 bottom sheet |
| 이벤트 long press | 일간 뷰 | → 편집 모드 (핸들 + toolbar) |
| 빈 타임라인 long press | 일간 뷰 | → phantom block + 생성 sheet |
| 시간 라벨 long press | 일간 뷰 | → phantom block + 생성 sheet (빈 타임라인과 동일) |
| 좌우 스와이프 | 일간 뷰 (기본 상태) | 날짜 이동 |
| 블록 좌우 드래그 | 일간 뷰 (편집 모드) | 날짜 간 블록 이동 |
| drag session 유지 | 일간 뷰 (편집 모드) | Pinch out 또는 scope 전환 뒤에도 drag session 유지 |
| 날짜 셀 hover | 월간/년간 뷰 (drag session 중) | `activeDate` 갱신 |
| drop | 월간/년간 뷰 (drag session 중) | `activeDate + minuteCandidate + duration`이 유효할 때만 확정, 아니면 restore |
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
