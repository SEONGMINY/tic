# tic — 타임라인 블록 애니메이션 계약

## 목적

타임라인 블록 애니메이션은 미관이 아니라 상태 이해를 위한 피드백 수단이다.

사용자는 아래 두 가지를 끊김 없이 느껴야 한다.

- 타임블록이 `붙어 있는 요소`에서 `떠다니는 조작 대상`으로 바뀌는 순간
- day → month/year → day 전환 중에도 같은 블록을 계속 조작하고 있다는 연속성

핵심 용어:

- `timelineCard`: day timeline에서 보이는 full card 표현
- `calendarPill`: month/year 탐색 중 보이는 익명 capsule 표현
- `selectedDate`: 현재 화면이 기준으로 삼는 확정 날짜
- `activeDate`: drag session 중 hover로만 바뀌는 임시 날짜
- `drop on touch up`: drop은 손을 떼는 한 번으로만 끝난다
- `single overlay`: 실제 이동 중 블록 overlay는 항상 하나만 유지한다
- `single active target`: month/year에서 강조되는 날짜 target도 항상 하나만 유지한다
- `restore-first policy`: invalid drop은 억지 확정 대신 원위치 복원을 우선한다
- `bounded handoff`: drag 시작 직후 local preview가 먼저 lift되고, root owner 전환은 explicit `touch claim` 이후에만 일어난다
- `touch claim`: root recognizer가 현재 touch를 현재 session token으로 명시적으로 인수했다는 신호다
- `rootClaimPending`: local preview는 시작됐지만 root ownership은 아직 없고, `presentation continuity`만 제한적으로 유지될 수 있는 handoff pending 상태다
- `holding card`: `rootClaimPending + non-day`에서 마지막 day overlay frame에 잠깐 고정되는 full card 표현이다

## 레퍼런스 영상 관찰

영상은 `videos/block-animation.MP4`이고, timecode 기준은 `videos/animation.json`이다.

`ffprobe` 기준 영상은 약 `60fps` 소스다. 따라서 `00:00:04:15` 같은 표기를 30fps로 읽으면 안 된다.

주요 시점:

- `00:00:02:17` 약 `2.283s`: 편집 가능 상태가 분명해진다. 블록이 조작 가능한 객체로 읽히기 시작한다.
- `00:00:03:35` 약 `3.583s`: 년/월 캘린더로 이동하는 입력이 발생한다.
- `00:00:04:15` 약 `4.250s`: scope transition이 실제로 시작된다.
- `00:00:04:16` ~ `00:00:04:26` 약 `4.267s` ~ `4.433s`: full card가 anonymous capsule로 압축되는 핵심 구간이다.

관찰 요약:

- 편집 진입 직후에는 full card가 충분히 보인다.
- scope transition 직전까지는 사용자가 원래 이벤트 블록을 직접 잡고 있다는 감각이 유지된다.
- transition이 시작되면 블록은 사라지지 않고 `timelineCard`에서 `calendarPill`로 presentation만 바뀐다.
- month/year에서 capsule은 익명 pill이다. 제목 텍스트, resize handle, 툴바는 보이지 않는다.
- month와 year 모두 같은 pill 길이를 유지해야 같은 객체처럼 느껴진다.
- 영상 후반의 최종 landing 세부는 일부 가려져 있다. day로 돌아온 뒤 landing/commit 순서는 본 문서의 설계 추정이 포함된다.

## 상태 머신

최소 상태:

- `idle`: 편집 세션 없음
- `editModeReady`: 편집 모드 진입 완료. 원본 블록이 조작 가능 상태다.
- `liftPreparing`: 원본 블록이 `떠다니는 조작 대상`으로 바뀌는 lift 단계다.
- `floatingTimeline`: `timelineCard` overlay가 손가락을 거의 즉시 따라간다.
- `transitionHoldingCard`: scope transition 시작 직후. full card 정체성을 잠깐 유지한다.
- `floatingCalendarPill`: `calendarPill` 상태. month/year 탐색 중이다.
- `returningToTimeline`: 결과 날짜 기준 day scope로 복귀 중이다.
- `dropping`: touch up 직후 landing/commit 대기 상태다.
- `restoring`: invalid drop 또는 cancel 후 원위치 복원 중이다.
- `committed`: drop 성공 후 저장 완료. 성공 commit 시에만 편집 모드 종료.

전이 규칙:

- `idle` → `editModeReady`: long press 성공
- `editModeReady` → `liftPreparing`: 본체 drag 시작
- `liftPreparing` → `floatingTimeline`: overlay가 분리되고 원본은 placeholder 역할로 남음
- `floatingTimeline` → `transitionHoldingCard`: pinch 또는 scope 전환 시작
- `transitionHoldingCard` → `floatingCalendarPill`: full card가 capsule로 압축됨
- `floatingCalendarPill` → `returningToTimeline`: valid target이 있는 상태에서 day 복귀 시작
- `returningToTimeline` → `dropping`: day timeline landing 준비 완료
- `dropping` → `committed`: 유효한 `activeDate` 또는 `selectedDate` 기준으로 최종 저장
- `dropping` → `restoring`: invalid drop
- `floatingTimeline` 또는 `floatingCalendarPill` → `restoring`: cancel 또는 session 중단
- `restoring` → `editModeReady`: cancel / invalid drop / restore에서는 편집 모드를 종료하지 않는다
- `committed` → `idle`: 저장과 함께 편집 모드 종료

## bounded handoff

기존 실패 경로:

- `source block -> placeholder` 전환이 root claim보다 먼저 일어나면 local preview와 root overlay가 동시에 owner처럼 보여 split-brain이 된다.
- local/global 좌표가 섞인 상태로 root handoff를 진행하면 overlay 첫 프레임 점프와 잘못된 hit-test가 같이 발생한다.
- `captureTouch(near:)`의 동기 성공을 drag 시작 조건으로 두면 root recognizer가 아직 touch를 관측하지 못한 첫 프레임에서 drag가 아예 시작되지 않을 수 있다.
- 이번 회귀는 `ownership`과 `presentation continuity`를 같이 잠근 데 있었다. pending 동안 막아야 하는 상호작용 정책과, scope transition continuity에서 유지해야 하는 표현 정책이 분리되지 않았다.

계약:

- drag 시작 직후 source 내부의 local preview는 즉시 lift된다.
- root ownership은 explicit `touch claim` 성공 후에만 전환된다.
- `rootClaimPending` 동안에는 source placeholder, month/year `activeDate` hover, `global drop ownership`을 켜지 않는다.
- claim window는 `2 frame 이내의 매우 짧은 window`로 유지한다. 실패나 timeout이면 `restore-first policy`로 즉시 원위치 복구한다.
- stale claim success, stale end, stale cancel은 현재 token과 맞지 않으면 무시한다.

## pending scope transition continuity

- `rootClaimPending` 동안 `hover`, `placeholder`, `global drop ownership`을 막는 것은 맞다.
- 하지만 scope transition 중 객체의 `presentation continuity`까지 끄면 안 된다.
- `day` 내부 local preview와 `non-day` continuity overlay는 같은 책임이 아니다.
- `rootClaimPending` 상태에서 `day -> month/year`로 전환되면 블록은 사라지지 않고 `holding card`로 유지된다.
- 이 `holding card`는 마지막으로 확인된 day overlay frame에 잠깐 고정된다.
- 이 경로는 `render visibility`를 유지하는 `render continuity`일 뿐이다. `interaction ownership`이나 root ownership transfer가 아니다.
- claim 성공 전에는 `calendarPill`로 바꾸지 않는다.
- claim 성공 전에는 month/year `activeDate` hover를 켜지 않는다.
- claim 성공 전에는 source placeholder를 켜지 않는다.
- claim 성공 전에는 `global drop ownership`을 root로 승격하지 않는다.
- `pending + non-day` 상태에서 touch up 하면 commit이 아니라 `restore-first policy`로 복귀한다.

## 역할 분리

원본과 overlay 역할:

- lift 전: 원본 블록이 실제 조작 대상처럼 보인다.
- lift 직후 claim pending 동안에는 source 내부 local preview만 활성 owner다.
- `rootClaimPending + non-day`에서는 `holding card`가 continuity 표현만 담당한다. 여기서 보이는 overlay는 `interaction ownership`을 뜻하지 않는다.
- root claim 성공 후: 원본 블록은 placeholder/ghost로 남고, 실제 이동 표현은 `single overlay`만 담당한다.
- month/year에서는 `single active target`만 강조한다. 여러 날짜를 동시에 강조하지 않는다.
- local preview와 root overlay가 동시에 활성 owner가 되면 안 된다.

날짜 역할:

- `selectedDate`는 확정 화면 기준이다. commit 전까지 바뀌지 않는다.
- `activeDate`는 month/year에서만 의미가 있는 hover candidate다.
- month/year hover 계산은 root ownership 이후에만 활성화된다.
- day timeline에서는 `minuteCandidate`를 유지하고, month/year에서는 `activeDate`만 갱신한다.

drop 규칙:

- `drop on touch up`만 허용한다.
- drag 중 hover 변화만으로 commit하지 않는다.
- 성공 commit 시에만 편집 모드 종료.
- cancel / invalid drop / restore에서는 편집 모드를 강제로 종료하지 않는다.

## 모션 계약

강조가 필요한 구간:

- `liftPreparing`
- `transitionHoldingCard`
- `returningToTimeline`
- `restoring`

빠르게 지나가야 하는 구간:

- drag follow
- hover update
- month/year 내부 위치 이동

표현 계약:

- `timelineCard`는 내용과 높이를 유지한 채 lift와 landing에서 정체성을 보여준다.
- `calendarPill`은 익명 capsule이다. 제목, 핸들, toolbar를 넣지 않는다.
- month/year 모두 `same pill length`를 유지한다.
- pointer와 overlay는 drag 중 거의 즉시 일치해야 한다.
- per-frame spring으로 손가락을 늦게 따라가게 만들지 않는다.
- scope transition은 shape change를 보여주되, 객체 identity는 유지해야 한다.

## 구현 가드레일

- cross-scope 전체 경로를 여러 overlay로 나누지 않는다.
- `bounded handoff`는 local preview → explicit `touch claim` → root `single overlay` 순서를 지킨다.
- `single overlay`와 `single active target` 원칙을 유지한다.
- day 복귀 전까지 `selectedDate`를 섣불리 바꾸지 않는다.
- invalid drop은 `restore-first policy`를 유지한다.

## 관측성

- `drag_start`
- `root_claim_success`
- `root_claim_timeout`
- `restore_reason`
- `claim_latency_ms`

이 관측성은 디버그와 회귀 재현을 위한 최소 기록이다. hot path마다 무거운 로깅을 추가하는 용도가 아니다.
