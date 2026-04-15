# draglab

`draglab`은 타임라인 블록 drag and drop의 상태 전이와 threshold를 Python에서 빠르게 실험하는 환경이다.

## 구조

```text
experiments/draglab/
  data/
    sessions.json
    events.json
    expected.json
  configs/
    baseline.json
    search_space.json
  runs/
  src/draglab/
    __init__.py
    models.py
    contracts.py
  tests/
    test_contracts.py
```

## 데이터 파일 역할

- `sessions.json`
  - 세션별 메타 정보
  - 화면 크기, safe area, timezone
  - day / month / year 레이아웃
  - drag 대상 블록의 source date/startMinute/endMinute/frame
- `events.json`
  - touch와 gesture 재생 로그
  - `touch_start`, `long_press_recognized`, `drag_start`, `drag_move`
  - `calendar_mode_enter`, `hover_date`, `drop`, `cancel`
- `expected.json`
  - drag 시작 여부와 시점
  - stable hover date
  - drop 허용 여부
  - 최종 `date/startMinute/endMinute`
  - terminal outcome

## Fixture 시나리오

- `s001`: same-day drag + valid drop
- `s002`: month scope로 이동 후 valid drop
- `s003`: false start
- `s004`: invalid drop 후 restore
- `s005`: hover 불안정으로 drop 거부
- `s006`: cancel 이벤트로 종료

## Swift Porting Contract

Swift와 Python은 아래 계약을 공유한다.

- 좌표 단위는 iOS point 기준 `global coordinates`
- day timeline minute 계산은 timeline frame + scroll offset을 사용한다
- drag session은 `dateCandidate`와 `minuteCandidate`를 분리해 유지한다
- month/year는 `activeDate`만 갱신하고 `minuteCandidate`는 유지한다
- 최종 drop은 `dateCandidate + minuteCandidate + duration`으로 계산한다
- invalid drop, overflow, missing candidate는 clamp보다 `restore`를 우선한다

이 README와 `src/draglab/contracts.py`가 Python/Swift 공통 계약의 기준 문서 역할을 한다.

## CLI 예시

```bash
PYTHONPATH=experiments/draglab/src python3 -m draglab.cli validate --data experiments/draglab/data
PYTHONPATH=experiments/draglab/src python3 -m draglab.cli replay --data experiments/draglab/data --config experiments/draglab/configs/baseline.json --session s002
PYTHONPATH=experiments/draglab/src python3 -m draglab.cli score --data experiments/draglab/data --config experiments/draglab/configs/baseline.json
PYTHONPATH=experiments/draglab/src python3 -m draglab.cli tune --data experiments/draglab/data --config experiments/draglab/configs/baseline.json --search-space experiments/draglab/configs/search_space.json --budget 8 --workers 4 --seed 7
```

## 병렬화 정책

- 세션 내부 상태 전이는 항상 순차다.
- 병렬화 단위는 `config` 또는 `session chunk`다.
- 기본 구현은 `config` 단위 process 병렬화를 사용한다.
- nested pool은 만들지 않는다.
- 같은 seed면 결과 순서가 재현되어야 한다.

## 결과 해석

- `score`는 correctness / smoothness / combined 점수를 함께 보여준다.
- `tune`은 상위 후보와 결과 파일 경로를 반환한다.
- Swift 이식 시에는 `combined`가 높고 negative scenario 방어 점수가 무너지지 않는 config를 baseline 후보로 삼는다.
