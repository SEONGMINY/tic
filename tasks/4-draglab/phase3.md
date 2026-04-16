# Phase 3: scoring-and-metrics

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `docs/prd.md` — drag UX 요구사항과 잘못된 drop 방어 기준
- `docs/code-architecture.md` — candidate, restore, geometry 계약
- `docs/adr.md` — restore-first / draglab 관련 ADR
- `docs/testing.md` — 순수 로직 테스트 원칙
- `/tasks/4-draglab/docs-diff.md` — 이번 task의 문서 변경 기록

그리고 이전 phase의 작업물을 반드시 확인하라:

- `experiments/draglab/src/draglab/models.py`
- `experiments/draglab/src/draglab/contracts.py`
- `experiments/draglab/src/draglab/geometry.py`
- `experiments/draglab/src/draglab/state_machine.py`
- `experiments/draglab/src/draglab/replay.py`
- `experiments/draglab/tests/test_contracts.py`
- `experiments/draglab/tests/test_geometry.py`
- `experiments/draglab/tests/test_state_machine.py`

## 작업 내용

이번 phase의 목적은 `expected.json`과 비교하는 **자동 채점기와 자연스러움 metric**을 구현하는 것이다.

### 1. `scoring.py`

세션 단위 점수와 집계 점수를 계산하라.

필수 세부 점수:

- `drag_start_score`
- `session_continuity_score`
- `hover_score`
- `drop_guard_score`
- `final_result_score`
- `restore_score`

필수 규칙:

- positive scenario와 negative scenario를 모두 채점해야 한다.
- false start 방지와 invalid drop 방지는 별도 가중치를 가져야 한다.
- 최종 total score는 correctness와 smoothness를 분리해서 산출하라.

### 2. 자연스러움 metric

trace를 기반으로 아래 metric을 계산하라.

- `overlay_anchor_error_pt`
- `frame_jump_pt_p95`
- `size_jump_ratio_p95`
- `hover_churn_per_sec`
- `restore_duration_ms`
- `restore_overshoot_pt`
- `scope_transition_jump_pt`

이 metric은 정성적 문장을 대신하는 수치로 정의되어야 하며, 값이 작을수록 좋은지 큰 값이 좋은지 방향도 함께 명시하라.

### 3. `report.py`

아래 기능을 구현하라.

- 세션별 breakdown 생성
- aggregate summary 생성
- worst sessions 추출
- threshold 비교에 쓸 수 있는 compact 출력 포맷 생성

report 계층은 엔진을 다시 돌리지 말고, `SessionResult`와 `SessionScore`를 받아 가공만 하게 하라.

### 4. 테스트

이 phase에서 테스트를 바로 작성하라.

`test_scoring.py`는 최소 아래를 검증해야 한다.

- expected와 완전 일치하는 세션은 높은 점수를 받는다.
- false start 세션에서 잘못 drag를 시작하면 점수가 떨어진다.
- invalid drop을 막지 못하면 `drop_guard_score`가 낮아진다.
- restore trace가 없으면 `restore_score`가 낮아진다.
- smoothness metric 계산이 trace 입력에 대해 결정론적으로 나온다.

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && PYTHONPATH=experiments/draglab/src python3 -m unittest discover -s experiments/draglab/tests -p 'test_*.py'
```

`test_contracts.py`, `test_geometry.py`, `test_state_machine.py`, `test_scoring.py`가 모두 통과하면 AC 통과.

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/4-draglab/index.json`의 phase 3 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- scoring 단계에서 threshold 탐색 로직까지 미리 넣지 마라. 점수 계산과 탐색은 분리하라.
- report 계층은 사람이 읽기 쉬운 요약을 제공하되, 데이터 구조를 임의로 손실시키지 마라.
- smoothness metric은 correctness를 덮어쓰면 안 된다. 둘을 분리해 유지하라.
