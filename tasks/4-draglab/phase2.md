# Phase 2: engine-core

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `docs/flow.md` — cross-scope drag session, restore, activeDate 흐름
- `docs/code-architecture.md` — DragSessionEngine, geometry 계약, 파생 droppable 규칙
- `docs/adr.md` — ADR-024, ADR-025, ADR-026
- `docs/testing.md` — 순수 로직 테스트 원칙
- `/tasks/4-draglab/docs-diff.md` — 이번 task의 문서 변경 기록

그리고 이전 phase의 작업물을 반드시 확인하라:

- `experiments/draglab/README.md`
- `experiments/draglab/src/draglab/models.py`
- `experiments/draglab/src/draglab/contracts.py`
- `experiments/draglab/data/sessions.json`
- `experiments/draglab/data/events.json`
- `experiments/draglab/data/expected.json`
- `experiments/draglab/tests/test_contracts.py`

## 작업 내용

이번 phase의 목적은 순수 Python으로 **상태 머신과 geometry 변환 엔진**을 구현하는 것이다.

### 1. `state_machine.py`

아래 개념을 명시적으로 구현하라.

- top-level state
  - `idle`
  - `pressing`
  - `drag_ready`
  - `dragging_timeline`
  - `dragging_calendar`
  - `restoring`
- terminal outcome
  - `none`
  - `dropped`
  - `cancelled`

필수 규칙:

- `droppable`은 독립 top-level state가 아니라, 현재 state와 candidate 유효성에서 계산되는 파생 값이다.
- `dragging_timeline`과 `dragging_calendar`는 session을 끊지 않고 이어져야 한다.
- `invalid drop`, `overflow`, `missing minuteCandidate`, `missing activeDate`는 기본적으로 `restoring -> idle`로 간다.
- false start는 `idle`로 복귀해야 하며 outcome을 만들지 않는다.

### 2. `geometry.py`

아래 pure function을 구현하라.

- global pointer -> timeline local y
- local y -> raw minute
- minute clamp + snap
- duration 보존을 포함한 final start/end minute 계산
- pointer anchor를 기준으로 overlay frame 계산
- month/year cell hit-test -> `activeDateCandidate`
- hysteresis / hover activation 보조 계산

Swift와 공유할 기준은 코드와 README가 일치해야 한다.

### 3. `replay.py`

세션별 이벤트를 순차 재생하는 순수 엔진을 구현하라.

최소 출력:

- 최종 state
- outcome
- dateCandidate / minuteCandidate
- final drop result
- 상태 전이 trace
- frame/overlay trace

trace는 이후 scoring에서 그대로 재사용할 수 있어야 한다.

### 4. 상태 컨텍스트

`models.py`를 확장하거나 별도 구조체를 추가해서 아래 정보를 추적하라.

- source date/start/end/duration
- current scope
- pointer global position
- finger-to-block anchor
- overlay frame
- activeDateCandidate
- minuteCandidate
- invalid reason

### 5. 테스트

이 phase에서 테스트를 바로 작성하라.

`test_geometry.py`는 최소 아래를 검증해야 한다.

- y -> minute 환산
- 15분 스냅
- duration 보존과 overflow rejection
- overlay anchor 계산
- month/year cell active 판정과 hysteresis

`test_state_machine.py`는 최소 아래를 검증해야 한다.

- long press 이전 false start 방지
- `pressing -> drag_ready -> dragging_timeline`
- day -> month 전환 후 session 유지
- valid drop의 `dropped` outcome
- invalid drop의 `restoring -> idle`
- cancel 이벤트 처리

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && PYTHONPATH=experiments/draglab/src python3 -m unittest discover -s experiments/draglab/tests -p 'test_*.py'
```

`test_contracts.py`, `test_geometry.py`, `test_state_machine.py`가 모두 통과하면 AC 통과.

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/4-draglab/index.json`의 phase 2 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- 이 phase에서는 scoring, report, CLI, 병렬 탐색을 구현하지 마라.
- `replay.py`는 파일 I/O에 의존하지 말고, 이미 로드된 모델을 받아 순수 계산만 하게 하라.
- 상태 전이 규칙을 뷰 로직처럼 섞지 마라. SwiftUI로 옮길 수 있는 순수 reducer 형태를 유지하라.
- 세션 내부 이벤트 처리는 항상 순차여야 한다. 여기서 병렬화를 시도하지 마라.
