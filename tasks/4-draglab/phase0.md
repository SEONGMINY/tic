# Phase 0: docs-alignment

## 사전 준비

먼저 아래 문서들을 반드시 읽고 프로젝트의 전체 아키텍처와 설계 의도를 완전히 이해하라:

- `docs/flow.md` — F2/F3/F7 제스처 정의와 편집 모드 UX
- `docs/prd.md` — 타임라인 편집 모드, month/year scope, MVP 범위
- `docs/code-architecture.md` — 편집 모드 상태 소유권, overlay 패턴, 프로젝트 구조
- `docs/adr.md` — ADR-020, ADR-021 및 기존 제스처 관련 결정
- `docs/testing.md` — 순수 로직 중심 테스트 원칙

그리고 아래 소스 파일들을 읽어 현재 구현 상태를 파악하라:

- `tic/Views/Calendar/DayView.swift`
- `tic/Views/Components/TimelineView.swift`
- `tic/Views/Components/EditableEventBlock.swift`
- `tic/Views/Calendar/MonthView.swift`
- `tic/Views/Calendar/YearView.swift`

기존 task의 관련 작업물을 반드시 확인하라:

- `tasks/3-ux-enhance/phase3.md`
- `tasks/3-ux-enhance/phase4.md`

## 작업 내용

이번 phase의 목적은 **문서 기준을 먼저 고정**하는 것이다. 코드 구현이나 실험 스캐폴드는 하지 말고, 아래 문서들만 업데이트하라.

### 1. `docs/flow.md` 업데이트

F3a(편집 모드)와 F2/F7 전환 흐름에 아래 내용을 반영하라.

- day timeline에서 long press 후 시작되는 drag session은 month/year scope 전환 중에도 유지될 수 있다.
- drag session 중에는 원본 블록은 placeholder/ghost처럼 남고, 실제 이동 중 블록은 전역 overlay로 존재한다.
- month/year에서는 `activeDate`만 갱신하고, `minuteCandidate`는 drag session이 유지한다.
- month/year에서의 drop은 `dateCandidate + minuteCandidate + duration`으로 최종 확정된다.
- invalid drop, overflow, hover 미확정, cancel은 기본적으로 `restore`로 끝난다.

### 2. `docs/prd.md` 업데이트

타임라인 편집 모드와 인터랙션 표를 확장해서 아래 개념을 명시하라.

- cross-scope drag session
- `dateCandidate`, `minuteCandidate`
- `restore-first policy`
- Python 기반 drag 실험기(`experiments/draglab/`)를 통해 threshold와 상태 전이를 검증한다는 개발 원칙

### 3. `docs/code-architecture.md` 업데이트

아래 내용을 새로 문서화하라.

- `DragSessionContext` 또는 이에 준하는 전역 drag 상태 구조
- `droppable`은 독립 top-level state가 아니라 파생 판정이라는 규칙
- `DragSessionEngine` 같은 순수 로직 레이어를 두고 SwiftUI View는 이벤트 전달/렌더만 담당한다는 구조
- Swift와 Python이 공유해야 할 geometry/date/minute 계약
- `experiments/draglab/` 디렉토리의 역할
- 병렬 실험은 세션 내부가 아니라 `config` 또는 `session chunk` 단위로만 수행한다는 원칙

### 4. `docs/adr.md` 업데이트

새 ADR을 추가하라. 기존 마지막 번호가 023이므로 다음 번호를 사용한다.

- `ADR-024`: cross-scope drag session은 전역 overlay + 단일 session owner로 관리
- `ADR-025`: invalid drop / overflow / missing candidate는 clamp보다 restore를 우선
- `ADR-026`: Python draglab을 Swift 계약 및 threshold 튜닝의 기준 환경으로 사용

### 5. 문서 톤 정리

문서 전반에서 아래 표현을 일관되게 사용하라.

- `drag session`
- `dateCandidate`
- `minuteCandidate`
- `restore`
- `activeDate`
- `global coordinates`

## Acceptance Criteria

```bash
cd /Users/leesm/work/side/tic && rg -n "drag session|dateCandidate|minuteCandidate|restore|DragSessionEngine|ADR-024|ADR-025|ADR-026" docs/flow.md docs/prd.md docs/code-architecture.md docs/adr.md
```

위 grep이 성공하고, 관련 개념이 문서에 실제로 반영되어 있으면 AC 통과.

## AC 검증 방법

위 AC 커맨드를 실행하라. 모두 통과하면 `/tasks/4-draglab/index.json`의 phase 0 status를 `"completed"`로 변경하라.
수정 3회 이상 시도해도 실패하면 status를 `"error"`로 변경하고, 에러 내용을 index.json의 해당 phase에 `"error_message"` 필드로 기록하라.

## 주의사항

- 이 phase에서는 **문서만 수정**하라. `experiments/draglab/` 코드, Swift 소스, runner 스크립트는 건드리지 마라.
- 현재 구현이 아직 month/year drag를 지원하지 않아도 괜찮다. 문서는 “이번 task에서 도입할 목표 구조”를 기준으로 정리하라.
- 기존 문서의 MVP 범위를 무너뜨리지 마라. 사용자 기능을 늘리는 것이 아니라, 기존 제스처 편집 기능의 설계 기준을 정교화하는 것이다.
- `docs-diff.md`는 runner가 자동 생성한다. 직접 만들지 마라.
