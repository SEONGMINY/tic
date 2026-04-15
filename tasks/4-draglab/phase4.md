# Phase 4: parallel-search-cli

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `docs/code-architecture.md` — 병렬 실험 원칙과 DragSessionEngine 역할
- `docs/adr.md` — draglab/restore 관련 ADR
- `docs/testing.md` — 순수 로직 테스트 원칙
- `/tasks/4-draglab/docs-diff.md` — 이번 task의 문서 변경 기록

그리고 이전 phase의 작업물을 반드시 확인하라:

- `experiments/draglab/README.md`
- `experiments/draglab/configs/baseline.json`
- `experiments/draglab/configs/search_space.json`
- `experiments/draglab/src/draglab/contracts.py`
- `experiments/draglab/src/draglab/geometry.py`
- `experiments/draglab/src/draglab/state_machine.py`
- `experiments/draglab/src/draglab/replay.py`
- `experiments/draglab/src/draglab/scoring.py`
- `experiments/draglab/src/draglab/report.py`
- `experiments/draglab/tests/test_contracts.py`
- `experiments/draglab/tests/test_geometry.py`
- `experiments/draglab/tests/test_state_machine.py`
- `experiments/draglab/tests/test_scoring.py`

## 작업 내용

이번 phase의 목적은 **반복 실행 가능한 CLI와 병렬 튜닝 루프**를 완성하는 것이다.

### 1. `cli.py`

아래 서브커맨드를 구현하라.

- `validate`
  - JSON 계약과 fixture를 검증
- `replay`
  - 특정 세션 또는 전체 세션을 재생
  - 상태 trace와 결과를 사람이 읽기 쉬운 형태로 출력
- `score`
  - baseline config로 전체 세션 점수 계산
- `tune`
  - search space에서 config 후보를 뽑아 반복 평가

명령은 `python3 -m draglab.cli ...` 형태로 실행 가능해야 한다.

### 2. `search.py`

탐색 전략을 구현하라.

- baseline config 로드
- search space 로드
- deterministic random search
- 후보별 전체 세션 평가
- top-K 후보 유지

초기 구현은 random search면 충분하다. grid search를 억지로 넣지 마라.

### 3. `parallel.py`

병렬 실험은 아래 원칙을 지켜 구현하라.

- 기본 병렬화 단위는 `config`
- 필요 시 `session chunk` 헬퍼를 둘 수 있지만 nested pool은 만들지 마라.
- `ProcessPoolExecutor` 또는 표준 라이브러리 기반 process 병렬화를 사용하라.
- 세션 내부 상태 전이는 절대 병렬화하지 마라.
- deterministic seed와 merge 순서를 보장하라.

### 4. README 보강

README에 아래를 추가하라.

- `validate`, `replay`, `score`, `tune` 실행 예시
- 병렬화 정책
- 결과 해석 방법
- Swift 이식 시 어떤 config를 기준값으로 가져갈지 정리하는 방법

### 5. 테스트

이 phase에서 테스트를 바로 작성하라.

최소 아래 테스트 파일을 추가하라.

- `test_cli.py`
- `test_parallel.py`

필수 검증 항목:

- `validate`가 정상 fixture에서 성공한다.
- `replay`가 특정 세션의 상태 전이 trace를 반환한다.
- `score`가 aggregate 결과를 생성한다.
- `tune`이 작은 budget에서도 결과를 남긴다.
- 같은 seed로 두 번 실행했을 때 상위 후보 순서가 재현된다.
- 병렬 worker 수가 달라도 total score가 변하지 않는다.

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && PYTHONPATH=experiments/draglab/src python3 -m draglab.cli validate --data experiments/draglab/data && PYTHONPATH=experiments/draglab/src python3 -m draglab.cli replay --data experiments/draglab/data --config experiments/draglab/configs/baseline.json --session s001 && PYTHONPATH=experiments/draglab/src python3 -m draglab.cli score --data experiments/draglab/data --config experiments/draglab/configs/baseline.json && PYTHONPATH=experiments/draglab/src python3 -m draglab.cli tune --data experiments/draglab/data --config experiments/draglab/configs/baseline.json --search-space experiments/draglab/configs/search_space.json --budget 4 --workers 2 --seed 7 && PYTHONPATH=experiments/draglab/src python3 -m unittest discover -s experiments/draglab/tests -p 'test_*.py'
```

CLI smoke test와 전체 테스트가 모두 통과하면 AC 통과.

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/4-draglab/index.json`의 phase 4 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- generated run artifacts는 기본적으로 `experiments/draglab/runs/` 아래에 두되, 불필요한 대용량 결과물을 커밋하지 마라.
- `tune`의 기본 병렬화는 coarse-grained process 병렬화여야 한다. thread 기반 shared mutable state를 만들지 마라.
- CLI 출력은 디버그 친화적이어야 하지만, JSON과 사람이 읽는 텍스트를 뒤섞어 파싱하기 어렵게 만들지 마라.
- 이 phase에서 Swift 코드를 수정하지 마라. 이번 task의 목표는 Python 실험기와 Swift 계약의 기준 환경을 만드는 것이다.
