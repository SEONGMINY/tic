# Phase 3: session-stability

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `docs/flow.md`
- `docs/prd.md`
- `docs/code-architecture.md`
- `docs/adr.md`
- `docs/testing.md`
- `/tasks/6-interaction-completion/docs-diff.md`

그리고 이전 phase의 작업물을 반드시 확인하라:

- `tasks/6-interaction-completion/phase0.md`
- `tasks/6-interaction-completion/phase1.md`
- `tasks/6-interaction-completion/phase2.md`
- `tic/Views/ContentView.swift`
- `tic/Views/Calendar/DayView.swift`
- `tic/DragSession/CalendarDragCoordinator.swift`
- `tic/DragSession/DragSessionEngine.swift`
- `ticTests/`

## 작업 내용

이번 phase의 목적은 **세션 종료, 복원, 화면 복귀를 안정화**하는 것이다.

### 1. 종료/복귀 규칙 완성

아래를 보장하라.

- global drop 성공 시 `selectedDate`는 결과 날짜로 맞춘다
- global drop 성공 시 화면은 `day` scope로 복귀한다
- invalid drop / cancel / restore 완료 후 overlay, placeholder, editing 관련 상태가 모두 정리된다
- stale month/year frame registry가 다음 세션에 남지 않는다

### 2. scene phase / interruption 방어

scene 전환 또는 외부 interruption이 active drag session 중 발생했을 때 아래 중 하나의 일관된 정책으로 처리하라.

- 명시적으로 cancel 후 restore
- 또는 세션 종료와 cleanup

핵심은 잘못된 commit이 일어나지 않고 idle 상태로 복귀하는 것이다.

### 3. 테스트 보강

최소 아래 시나리오를 XCTest로 검증하라.

- invalid drop은 restore 후 idle cleanup으로 끝난다
- cancel은 commit 없이 종료된다
- active drag 중 scope round-trip 뒤 drop 성공 시 결과 날짜의 day scope 복귀 규칙이 유지된다
- stale frame registry가 다음 세션의 activeDate를 오염시키지 않는다

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && xcodegen generate && xcodebuild test -scheme tic -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/6-interaction-completion/index.json`의 phase 3 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- invalid drop을 가장 가까운 valid slot으로 강제 보정하지 마라. `restore-first policy`를 유지하라.
- 동일 세션에서 commit과 cancel이 모두 발생하는 race를 만들지 마라.
- 기존 테스트를 깨뜨리지 마라.
