# tic — 사용자 흐름

## F1: 첫 실행
```
앱 실행
 → 시스템: 캘린더 권한 요청 팝업
 → 시스템: 미리 알림 권한 요청 팝업
 → 월간 뷰 (모든 캘린더 기본 활성화)
```
거부 시: 빈 캘린더로 앱 동작, 재시도/차단 없음.

## F2: 월간 뷰 (기본 화면)
```
[월간 뷰]
 내비: "2026년" ⚙️ 🔍 +
 그리드: 일정 있는 날 오렌지 점, 오늘 = 오렌지 원
 왼쪽 하단: "이번달" floating 버튼 (Capsule, .ultraThinMaterial)
 
 날짜 탭 → F3 (해당 날짜 일간 뷰)
 Pinch in → F3 (selectedDate 기준 일간 뷰)
 Pinch out → F7 (년간 뷰)
 "2026년" 탭 → 오늘로 이동
 "이번달" 탭 → 올해의 이번달로 스크롤
 + 탭 → F5 (일정 생성, 빈 폼)
 🔍 탭 → F6 (검색)
 ⚙️ 탭 → F8 (설정)

 drag session 중:
  pinch scope transition으로 day/year scope 전환 가능
  `CalendarDragCoordinator` session을 유지한 채 scope만 교체
  overlay는 root scope 위에서 계속 유지
  각 날짜 셀 hover → activeDate 갱신
  날짜 셀 판정은 global coordinates 기준 hit-test
  drop 시 activeDate + minuteCandidate로 최종 확정
  month drop 성공 시 결과 날짜 기준으로 day scope로 복귀
```

## F3: 일간 뷰
```
[일간 뷰]
 내비: "← 4월" ⚙️ 🔍 +

 [주간 스트립] (독립 slide in/out 애니메이션)
   7일 탭 + 좌우 스와이프 (주 단위)
   선택된 날: circle 강조 (matchedGeometryEffect)

 오늘인 경우:
   [다음 행동 카드] — 다음 이벤트/시간있는 리마인더 1개

 [종일 이벤트 영역] (있을 때만)

 [24시간 타임라인] (독립 slide in/out 애니메이션)
  시간 라벨 영역 (52pt) + 이벤트 블록 영역
  이벤트 블록: 시간 기준 배치, 캘린더 고유 색상
  겹치는 일정: column-packing
  현재 시간: 빨간 선 + 원 (오늘만)

 [📋 FAB] 우하단 — 탭 → 일정 리스트 sheet

 기본 상태 제스처:
  타임라인 좌우 스와이프 → 이전/다음 날
  Pinch out → 월간 뷰
  빈 타임라인 long press (0.5초) → F5a
  시간 라벨 long press (0.5초) → F5a (해당 정각)
  이벤트 블록 탭 → F4
  이벤트 블록 long press (0.5초) → F3a (편집 모드)
```
과거 날짜: 다음 행동 카드 숨김.

### F3a: 편집 모드
```
진입: 이벤트 블록 long press → haptic (.medium)

 [편집 중 블록]
  상단-우측: 8pt 흰색 원 핸들 + 그림자 (시작 시간 조절)
  하단-좌측: 8pt 흰색 원 핸들 + 그림자 (종료 시간 조절)
  핸들 드래그 중: 옆에 tooltip으로 변경 시간 실시간 표시

 [Floating Toolbar] 블록 아래 (공간 부족 시 위)
  .ultraThinMaterial + cornerRadius(12) + shadow(4)
  [🗑 삭제(red) | 📋 복제(primary)]
  너비: auto (padding 16pt), 블록 중앙 정렬

 조작:
  꼭짓점 드래그 → 리사이즈 (15분 스냅, 최소 30분)
  블록 본체 y축 드래그 → 같은 날 이동 (15분 스냅, 자동 스크롤)
  블록 본체 이동은 단일 root drag path로만 처리
  drag session 중 pinch scope transition으로 day/month/year scope 전환 가능
  drag session 중 원본 블록은 placeholder/ghost처럼 남고, 실제 이동 중 블록은 전역 overlay로 유지
  overlay owner는 DayView가 아니라 root `CalendarDragCoordinator`
  day timeline에서는 `dateCandidate`, `minuteCandidate`를 둘 다 갱신
  month/year에서는 `activeDate`만 갱신하고 `minuteCandidate`는 drag session이 유지
  drop 시 `dateCandidate + minuteCandidate + duration`으로 확정
  month/year drop 성공 시 결과 날짜 기준으로 day scope로 복귀
  삭제 탭 → 확인 alert → EventKit 삭제
  복제 탭 → 같은 시간에 즉시 배치 (반복 규칙 제외, sheet 없음)

 해제:
  빈 영역 탭 → 편집 모드 완전 해제
  편집 블록 탭 → toolbar만 닫힘, 편집 모드 유지
  다른 블록 long press → 현재 해제 → 새 블록 편집 모드
  invalid drop / overflow / hover 미확정 / cancel → restore 후 종료
  legacy edge-hover timer 기반 인접 날짜 이동은 핵심 경로가 아니며 제거 대상

 비활성화:
  타임라인 좌우 스와이프 (블록 드래그와 충돌 방지)
  빈 시간대 long press (편집 모드와 충돌 방지)
```

## F4: 일정 상세 / 수정
```
[Bottom Sheet - 수정 모드]
 타입 선택 Segmented Control: 숨김
 기존 데이터 자동 입력
 하단: 빨간 "삭제" 버튼 → 확인 alert → EventKit에서 삭제
```

## F5: 일정 생성
```
[Bottom Sheet - 생성 모드]
 진입점:
  a) + 버튼 → 모든 필드 비어있음
  b) 타임라인/시간라벨 long press → F5a

 상단: [이벤트 | 미리 알림] Segmented Control (둥근 스타일, 기본: 이벤트)
 
 폼 (cornerRadius 크게):
  제목 [필수] — 타입 전환 시 유지
  설명
  하루 종일 토글 (이벤트만) — 켜면 날짜만, 꺼면 날짜+시간
  캘린더 선택 — 이벤트: 캘린더 목록만, 미리 알림: 리마인더 목록만 (전환 시 초기화)
  시작/종료 (캘린더) 또는 날짜/시간 토글 (리마인더)
  반복: 6가지 프리셋
  알림: 5가지 옵션
  
 저장: 필수 필드 비어있으면 비활성화
 저장 시: EventKit 쓰기 → 로컬 알림 스케줄 → 첫 일정이면 알림 권한 요청
```

### F5a: Phantom Block 생성
```
타임라인/시간라벨 long press (0.5초)
 → 해당 정각에 phantom block 생성 (1시간, 실제 블록 스타일 + opacity 0.4)
 → EventFormView sheet 올라옴 (.medium 기본, .large 확장)
 → 시작 = 눌린 시간 정각, 종료 = +1시간, 타입 = 이벤트

 저장 완료 → phantom 제거, 실제 블록 렌더링
 취소/dismiss → phantom 제거
```

## F6: 검색
```
[Navigation Push]
 검색바 (자동 포커스)
 빈 입력: 최근 검색 기록 + ✕ 삭제
 입력 시: 실시간 필터링, 날짜별 그룹핑, 과거+미래 전체
 결과 탭 → F4 (일정 수정)
 검색 제출 → SearchHistory 저장 (SwiftData)
```

## F7: 년간 뷰
```
[년간 뷰]
 12개월 미니 캘린더 그리드
 왼쪽 하단: "올해" floating 버튼 (Capsule, .ultraThinMaterial)
 
 월 탭 → F2 (해당 월의 월간 뷰)
 Pinch in → F2 (월간 뷰)
 "올해" 탭 → 올해로 스크롤

 drag session 중:
  pinch scope transition으로 month scope 전환 가능
  `CalendarDragCoordinator` session을 유지한 채 scope만 교체
  pointer가 날짜 셀 위에서 안정적으로 머물면 activeDate 갱신
  overlay는 root scope 위에서 유지되고, scope 교체만으로는 종료되지 않음
  drop은 activeDate가 있고 minuteCandidate가 유지된 경우에만 허용
  year drop 성공 시 결과 날짜 기준으로 day scope로 복귀
  invalid drop은 확정하지 않고 restore
```

## F8: 설정
```
[Bottom Sheet]
 모든 캘린더 + 리마인더 리스트: 켜기/끄기 토글
 기본: 전체 활성화
```

## F9: Live Activity
```
트리거 A (포그라운드): 일정 30분 전 → Live Activity 자동 시작
트리거 B (백그라운드): 로컬 알림 → 사용자 탭 → 앱 열림 → 시작

[Lock Screen]
 상단: "tic" 로고 + 카운트다운 (Text timerInterval, 모든 일정 종료 시 숨김)
 중앙: progress line
   시작 = 첫 일정 시작 시간, 끝 = 마지막 일정 종료 시간
   실선 = 경과, 점선 = 남은
   각 일정 위치에 dot (캘린더 고유 색상)
   현재 진행 중 dot: 1.5배 크기 + 글로우
   지나간 dot: opacity 0.6
   TimelineView(.periodic) 기반 자동 갱신
 하단: "지금" 일정 + "다음" 일정 (상황에 따라 1줄 또는 숨김)

[Dynamic Island Expanded]
 leading: tic + 현재 일정 제목
 trailing: 카운트다운
 bottom: 축소 progress line + 시작/끝 시간

[Dynamic Island Compact]
 leading: tic 아이콘 + 현재/다음 일정 제목
 trailing: 카운트다운

[Dynamic Island Minimal]
 progress 원형 (오렌지 링)

카운트다운 로직:
 일정 1개 → 현재 진행 중 남은 시간
 여러 일정 → 다음 일정까지 남은 시간
 빈 시간 → 다음 일정까지 남은 시간
 모든 종료 → 카운트다운 숨김

종료: 유저 수동 종료. 모든 일정 끝나면 실선 꽉 참 상태로 계속 표시.
탭 → 해당 날짜 DayView로 앱 열기
```

## F10: 위젯 인터랙션
```
[Small 위젯]
 다음 일정 1개: 제목 + 시간
 탭 → 해당 날짜 일간 뷰로 앱 열기

[Medium 위젯]
 다음 3-4개 일정, 초과 시 "+N개 더"
 탭 → 해당 날짜 일간 뷰로 앱 열기

둘 다: App Intents를 통한 완료/스누즈 버튼 (Interactive Widget)
```

## F11: 알림 액션
```
[로컬 알림 - 일정 시간]
 제목: 일정 제목
 액션:
  [완료] → 리마인더 완료 처리 / 이벤트 해제
  [10분 후] → 스누즈 알림 예약
```
