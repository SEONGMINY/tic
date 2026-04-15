# Phase 1: contracts-and-fixtures

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `docs/flow.md` — cross-scope drag 흐름과 activeDate/drop semantics
- `docs/prd.md` — 제품 요구사항과 drag 실험기의 역할
- `docs/code-architecture.md` — DragSessionEngine, geometry 계약, experiments 구조
- `docs/adr.md` — ADR-024, ADR-025, ADR-026
- `docs/testing.md` — 순수 로직 중심 테스트 원칙
- `/tasks/4-draglab/docs-diff.md` — 이번 task의 문서 변경 기록

그리고 이전 phase의 작업물을 반드시 확인하라:

- `docs/flow.md`
- `docs/prd.md`
- `docs/code-architecture.md`
- `docs/adr.md`

## 작업 내용

이번 phase의 목적은 Python 실험기의 **데이터 계약과 fixture를 고정**하는 것이다.

### 1. `experiments/draglab/` 스캐폴드 생성

아래 디렉토리 구조를 생성하라.

```text
experiments/draglab/
  README.md
  pyproject.toml
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

- `runs/`는 빈 디렉토리로 두지 말고 `.gitkeep` 등 최소 추적 파일을 둬라.
- 외부 라이브러리 의존 없이 표준 라이브러리만으로 동작하게 설계하라.

### 2. JSON 계약 고정

`sessions.json`, `events.json`, `expected.json`의 구조를 아래 요구사항에 맞게 고정하라.

- `sessions.json`
  - `sessionId`, `timezone`, `scenarioTags`, `initialScope`
  - device width/height/safeArea
  - day/month/year layout frame 정보
  - dragged item의 source date/startMinute/endMinute/frame
  - dataset split(train/dev/test)
- `events.json`
  - `touch_start`, `long_press_recognized`, `drag_start`, `drag_move`, `calendar_mode_enter`, `hover_date`, `drop`, `cancel`
  - 각 이벤트는 `tsMs`와 필요한 좌표/보조 필드를 가진다.
- `expected.json`
  - drag 시작 기대 여부
  - 기대 drag start 시점
  - stable hover date 기대값
  - drop 허용/거부 기대값
  - 최종 `date/startMinute/endMinute`
  - terminal outcome(`dropped`, `cancelled`)

### 3. `models.py`

실험기의 기본 데이터 모델을 dataclass나 Enum 중심으로 정의하라.

- Session spec
- Layout/frame spec
- Input event spec
- Expected result spec
- Config spec

이 단계에서는 상태 머신 구현을 하지 않는다. 데이터 모델과 직렬화 기준만 잡아라.

### 4. `contracts.py`

아래 책임을 구현하라.

- JSON 파일 로드
- 기본 구조 검증
- 타입/필수 필드 검증
- session/events/expected 간 참조 일치 검증
- 잘못된 fixture를 설명 가능한 오류로 반환

검증 로직은 순수 함수로 작성하라.

### 5. 기본 fixture 추가

최소 아래 시나리오를 fixture로 포함하라.

- 정상 day timeline drag + same-day drop
- month scope로 넘어가 날짜 변경 후 valid drop
- false start(드래그로 보면 안 되는 세션)
- invalid drop 후 restore
- hover date가 안정적으로 잡히지 않아 drop 거부되는 세션
- cancel 이벤트로 종료되는 세션

### 6. `README.md`

README에 아래 내용을 정리하라.

- 디렉토리 구조
- 세 파일의 역할
- Swift와 공유할 핵심 좌표/시간 계약
- fixture 시나리오 목록

README에는 `Swift Porting Contract` 섹션을 넣어, 이후 Swift에서 그대로 옮겨야 할 필드명과 의미를 요약하라.

### 7. 테스트

`docs/testing.md` 원칙대로 이 phase에서 테스트를 바로 작성하라.

`test_contracts.py`는 최소 아래를 검증해야 한다.

- 유효 fixture는 정상 로드된다.
- 필수 필드 누락 시 검증이 실패한다.
- 중복 `sessionId`가 감지된다.
- `expected.json`이 없는 세션 참조를 하면 실패한다.
- negative scenario fixture도 스키마 차원에서는 유효하다.

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && PYTHONPATH=experiments/draglab/src python3 -m unittest discover -s experiments/draglab/tests -p 'test_contracts.py'
```

테스트가 모두 통과하면 AC 통과.

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/4-draglab/index.json`의 phase 1 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- 이 phase에서는 상태 머신, scoring, CLI를 구현하지 마라. 계약과 fixture만 만든다.
- `jsonschema` 같은 외부 의존성을 추가하지 마라. 표준 라이브러리 검증으로 충분하다.
- 좌표 단위는 iOS point 기준 global coordinates로 문서와 코드에서 일치시켜라.
- fixture는 “정답”이 아니라 “회귀 기준”이다. 시나리오 이름과 기대값이 분명해야 한다.
