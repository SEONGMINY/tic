# docs-diff: pending-touch-continuity

Baseline: `15b1b9e`

## `docs/adr.md`

```diff
diff --git a/docs/adr.md b/docs/adr.md
index fcf1829..2fcd00e 100644
--- a/docs/adr.md
+++ b/docs/adr.md
@@ -94,16 +94,20 @@ cross-scope drag의 핵심은 블록이 사라졌다가 새로 생기는 것처
 이번 drag 고장의 핵심은 소유권 전환 순서가 느슨했다는 점이다. `source block -> placeholder` 전환이 root claim보다 먼저 일어나면 local preview와 root overlay가 동시에 owner처럼 보인다. local/global 좌표가 섞인 상태로 handoff를 진행하면 첫 프레임 점프와 잘못된 hit-test가 겹친다. `captureTouch(near:)`의 동기 성공을 drag 시작 조건으로 두면 root recognizer가 아직 touch를 관측하지 못한 첫 프레임에서 drag가 시작되지 않을 수 있다.
 
 추가로 이번 회귀는 `ownership`과 `presentation continuity`를 같이 잠근 데서 나왔다. `rootClaimPending` 동안 `hover`, `placeholder`, `global drop ownership`을 막는 것은 맞지만, scope transition continuity까지 함께 꺼지면 블록이 사라진 것처럼 보인다.
+이번 회귀는 거기서 한 단계 더 나아가, `render continuity`만 복구하고 `touch tracking relay`는 복구하지 않았기 때문에 `보이지만 더 이상 움직이지 않는 카드`를 만든 점도 포함한다.
 
 결정:
 
 - `bounded handoff`는 local preview 즉시 lift → explicit `touch claim` 성공 → root ownership 전환 순서로만 진행한다.
 - claim pending 동안에는 source placeholder, month/year `activeDate` hover, `global drop ownership`을 켜지 않는다.
-- `render visibility`와 `interaction ownership`은 별도 정책으로 분리한다.
+- `render visibility`, `interaction ownership`, `touch tracking relay`는 별도 정책으로 분리한다.
 - `rootClaimPending` 중에도 scope transition continuity는 유지될 수 있다. 다만 이것은 `render continuity`이지 `ownership transfer`가 아니다.
+- `rootClaimPending + non-day`에서는 같은 live touch를 따라가는 `touch tracking relay`를 유지할 수 있다. 다만 이것도 `ownership transfer`는 아니다.
 - `day` 내부 local preview와 `non-day` continuity overlay는 같은 책임이 아니다.
 - `rootClaimPending` 상태에서 day → month/year로 전환되면 블록은 사라지지 않고 `holding card`로 유지된다. 이 카드는 마지막으로 확인된 day overlay frame에 잠깐 고정된다.
+- `touch tracking relay`가 붙어 있으면 이 `holding card`는 손가락을 계속 따라가야 한다.
 - claim 성공 전에는 `calendarPill`, month/year `activeDate` hover, source placeholder, `global drop ownership`을 켜지 않는다.
+- `calendarPill` morph는 `claim 후 morph` 정책을 따른다. claim 성공 전에는 full card를 유지한다.
 - `pending + non-day` 상태에서 touch up 하면 commit이 아니라 `restore-first policy`로 복귀한다.
 - claim window는 `2 frame 이내의 매우 짧은 window`로 유지한다. 실패나 timeout이면 `restore-first policy`로 즉시 복구한다.
 - `selectedDate`는 commit 전까지 바꾸지 않는다. `activeDate`는 root ownership 이후 month/year hover candidate로만 사용한다.
```

## `docs/code-architecture.md`

```diff
diff --git a/docs/code-architecture.md b/docs/code-architecture.md
index 2f53be9..8f7c52d 100644
--- a/docs/code-architecture.md
+++ b/docs/code-architecture.md
@@ -180,6 +180,7 @@ phantomBlock: PhantomBlock?
 
 - `render visibility`: local preview, `holding card`, `calendarPill` 중 무엇을 지금 보여줄지 결정하는 정책
 - `interaction ownership`: source `placeholder`, month/year `activeDate` hover, `global drop ownership`을 누가 가질지 결정하는 정책
+- `touch tracking relay`: root가 같은 live touch를 계속 관측하고 overlay frame을 갱신할 수 있는지 결정하는 정책
 
 cross-scope drag는 여기에 ownership handoff state를 하나 더 둔다.
 
@@ -263,11 +264,14 @@ struct DragSessionContext {
 - `captureTouch(near:)`의 동기 성공을 drag 시작 조건으로 두지 않는다. root recognizer가 첫 프레임에 아직 touch를 관측하지 못했을 수 있기 때문이다.
 - 이번 회귀의 원인은 `ownership`과 `presentation continuity`를 같이 잠근 데 있었다.
 - `rootClaimPending`은 root ownership을 아직 주지 않는 상태지만, `render visibility`는 non-day continuity를 위해 별도 계산할 수 있다.
+- `rootClaimPending`은 root ownership을 아직 주지 않는 상태라도, `touch tracking relay`는 따로 붙어 있을 수 있다.
 - `day` 내부 local preview와 `non-day` continuity overlay는 같은 책임이 아니다.
 - `rootClaimPending + non-day`에서는 `holding card`를 마지막으로 확인된 day overlay frame에 잠깐 고정할 수 있다. 이것은 `render visibility`를 위한 `render continuity`이지 root `interaction ownership`이 아니다.
+- `rootClaimPending + non-day`에서는 `touch tracking relay`가 같은 손가락을 계속 따라가며 overlay frame을 갱신할 수 있어야 한다.
 - root ownership이 오기 전에는 source `placeholder`, root `interaction ownership`, month/year `activeDate` hover, `global drop ownership`을 켜지 않는다.
 - 원본 블록은 root claim 성공 뒤에만 placeholder/ghost처럼 남고, 실제 이동 중 블록은 전역 overlay로만 렌더링한다.
 - claim 성공 전에는 `calendarPill`로 바꾸지 않는다.
+- `calendarPill` morph는 `claim 후 morph` 정책을 따른다. tracking relay가 살아 있어도 claim 성공 전에는 full `timelineCard`를 유지한다.
 - `EditableEventBlock`은 local move completion owner가 아니라 pointer forwarding 역할만 가진다.
 - drag 중 실시간 추적은 per-frame animation이 아니라 직접 position 업데이트로 처리한다.
 - 상태 전환 애니메이션만 명시적으로 `withAnimation` 또는 spring을 사용한다.
```

## `docs/flow.md`

```diff
diff --git a/docs/flow.md b/docs/flow.md
index 7a196e7..426b727 100644
--- a/docs/flow.md
+++ b/docs/flow.md
@@ -34,6 +34,8 @@
   이 `holding card`는 마지막으로 확인된 day overlay frame에 잠깐 고정된다
   claim 성공 뒤 overlay는 root scope 위에서 계속 유지되는 `single overlay`
   `rootClaimPending`의 `holding card`는 `render visibility`를 위한 continuity일 뿐이고 root `interaction ownership`은 아니다
+  `rootClaimPending + non-day`에서는 root가 같은 touch를 계속 관측하는 `touch tracking relay`도 유지돼야 한다
+  이 relay는 같은 손가락을 계속 따라가기 위한 것이고 root `interaction ownership`과는 별도다
   scope 전환 중에도 같은 블록을 계속 조작한다고 느껴야 함
   month/year hover 계산은 root `touch claim` 성공 이후에만 활성화
   각 날짜 셀 hover → `activeDate`만 갱신, `selectedDate`는 즉시 바뀌지 않음
@@ -105,6 +107,8 @@
   `day` 내부 local preview와 `non-day` continuity overlay는 같은 책임이 아니다
   `rootClaimPending` 상태에서 `day -> month/year`로 전환되면 블록은 사라지지 않고 `holding card`로 유지된다
   이 `holding card`는 마지막으로 확인된 day overlay frame에 잠깐 고정된다
+  `rootClaimPending + non-day`에서는 `touch tracking relay`가 같은 손가락을 계속 따라가며 `holding card`도 같이 움직여야 한다
+  이 relay는 root ownership이 아니므로 claim 성공 전에는 hover나 `global drop ownership`을 열지 않는다
   `source block -> placeholder` 전환이 root claim보다 먼저 일어나면 안 된다
   local/global 좌표가 섞인 상태로 root handoff를 진행하면 안 된다
   `captureTouch(near:)`의 동기 성공을 drag 시작 조건으로 두지 않는다. root recognizer가 첫 프레임에 아직 touch를 못 본 상태면 drag가 아예 시작되지 않을 수 있다
@@ -203,6 +207,7 @@
   pinch scope transition으로 month scope 전환 가능
   `CalendarDragCoordinator` session을 유지한 채 scope만 교체
   `rootClaimPending` 상태로 year scope에 들어와도 블록은 `holding card`로 계속 보일 수 있다. 이는 `presentation continuity`일 뿐 root `interaction ownership`은 아니다
+  이 구간에서도 `touch tracking relay`는 계속 살아 있어야 하며, 카드가 손가락을 계속 따라가야 한다
   month/year hover 계산은 root `touch claim` 성공 이후에만 활성화
   pointer가 날짜 셀 위에서 안정적으로 머물면 `activeDate`만 갱신
   claim 성공 전에는 `calendarPill`, source `placeholder`, `global drop ownership`을 켜지 않는다
```

## `docs/prd.md`

```diff
diff --git a/docs/prd.md b/docs/prd.md
index aab1d6e..be27d21 100644
--- a/docs/prd.md
+++ b/docs/prd.md
@@ -44,7 +44,7 @@ cross-scope move의 시작은 `bounded handoff`다.
 | 꼭짓점 리사이즈 | 상단-우측(시작시간), 하단-좌측(종료시간) 핸들. 15분 단위 스냅. 최소 30분. 핸들 옆 tooltip으로 시간 실시간 표시 |
 | 블록 이동 (같은 날) | 블록 본체 y축 드래그. 15분 단위 스냅. 자동 스크롤 지원 |
 | 블록 이동 (날짜 간) | cross-day move도 별도 local fallback 없이 단일 `root drag path`로 처리한다. drag 시작 직후 local preview가 lift되고, explicit `touch claim` 성공 후에만 원본 블록이 placeholder/ghost로 남고 실제 이동 블록이 root `single overlay`로 넘어간다. claim pending 동안에는 placeholder를 켜지 않는다. |
-| 블록 이동 (scope 간) | `pinch scope transition`은 문서상의 제스처가 아니라 실제 구현 대상이다. drag session은 day → month/year 전환 중에도 유지되며, root `CalendarDragCoordinator`가 전역 overlay와 session lifetime을 소유한다. 다만 `rootClaimPending` 동안에는 `global drop ownership`과 hover를 열지 않는다. 이 구간은 `presentation continuity`를 위해 마지막 day overlay frame에 잠깐 고정된 `holding card`만 유지하고, claim 성공 전에는 `calendarPill`로 바꾸지 않는다. `pending + non-day` touch up은 commit이 아니라 restore다. claim 성공 뒤에만 익명 `calendarPill`과 month/year hover 경로가 열린다. |
+| 블록 이동 (scope 간) | `pinch scope transition`은 문서상의 제스처가 아니라 실제 구현 대상이다. drag session은 day → month/year 전환 중에도 유지되며, root `CalendarDragCoordinator`가 전역 overlay와 session lifetime을 소유한다. 다만 `rootClaimPending` 동안에는 `global drop ownership`과 hover를 열지 않는다. 이 구간은 `presentation continuity`를 위해 마지막 day overlay frame에 잠깐 고정된 `holding card`를 유지하고, `touch tracking relay`가 같은 손가락을 계속 따라가야 한다. claim 성공 전에는 `calendarPill`로 바꾸지 않는다. `pending + non-day` touch up은 commit이 아니라 restore다. claim 성공 뒤에만 익명 `calendarPill`과 month/year hover 경로가 열린다. |
 | drag 피드백 | pointer 이동과 overlay 이동은 drag 중 거의 즉시 일치해야 한다. 연속 drag follow와 hover update는 빠르게 지나가야 하고, per-frame animation으로 손가락을 늦게 따라가게 만들지 않는다. `touch claim` pending은 `2 frame 이내의 매우 짧은 window`로만 허용한다. |
 | drop 계산 | day timeline은 `dateCandidate`, `minuteCandidate`를 둘 다 갱신한다. month/year는 `selectedDate`를 commit 전까지 유지하고 `activeDate`만 갱신하며 `minuteCandidate`는 drag session이 유지한다. 최종 drop은 `drop on touch up`으로만 끝나고 `dateCandidate + minuteCandidate + duration`으로 계산한다. 성공 후 `selectedDate`와 화면 scope는 결과 날짜의 day 기준으로 맞춘다. Swift와 Python이 동일한 규칙을 사용한다. |
 | 표현 단순화 | full card는 lift와 landing에서는 충분히 보이되, month/year 탐색 중에는 제목 텍스트와 핸들을 제거한 익명 capsule만 보여준다. month와 year 모두 `same pill length`를 유지해 같은 객체처럼 인지되게 한다. |
```

## `docs/timeline-block-animation.md`

```diff
diff --git a/docs/timeline-block-animation.md b/docs/timeline-block-animation.md
index 757d585..e8c0cb3 100644
--- a/docs/timeline-block-animation.md
+++ b/docs/timeline-block-animation.md
@@ -92,16 +92,20 @@
 - `rootClaimPending` 동안에는 source placeholder, month/year `activeDate` hover, `global drop ownership`을 켜지 않는다.
 - claim window는 `2 frame 이내의 매우 짧은 window`로 유지한다. 실패나 timeout이면 `restore-first policy`로 즉시 원위치 복구한다.
 - stale claim success, stale end, stale cancel은 현재 token과 맞지 않으면 무시한다.
+- `touch tracking relay`는 root ownership과 분리될 수 있다. root가 같은 live touch를 보고 있더라도, claim 성공 전에는 아직 root owner가 아니다.
 
 ## pending scope transition continuity
 
 - `rootClaimPending` 동안 `hover`, `placeholder`, `global drop ownership`을 막는 것은 맞다.
 - 하지만 scope transition 중 객체의 `presentation continuity`까지 끄면 안 된다.
+- `presentation continuity`만 복구하고 `touch tracking relay`를 복구하지 않으면, 블록은 보이지만 더 이상 움직이지 않는 frozen card가 된다.
 - `day` 내부 local preview와 `non-day` continuity overlay는 같은 책임이 아니다.
 - `rootClaimPending` 상태에서 `day -> month/year`로 전환되면 블록은 사라지지 않고 `holding card`로 유지된다.
 - 이 `holding card`는 마지막으로 확인된 day overlay frame에 잠깐 고정된다.
 - 이 경로는 `render visibility`를 유지하는 `render continuity`일 뿐이다. `interaction ownership`이나 root ownership transfer가 아니다.
+- `rootClaimPending + non-day`에서는 `touch tracking relay`가 같은 손가락을 계속 따라가며 `holding card`의 frame도 계속 갱신해야 한다.
 - claim 성공 전에는 `calendarPill`로 바꾸지 않는다.
+- `calendarPill` morph는 `claim 후 morph` 정책을 따른다.
 - claim 성공 전에는 month/year `activeDate` hover를 켜지 않는다.
 - claim 성공 전에는 source placeholder를 켜지 않는다.
 - claim 성공 전에는 `global drop ownership`을 root로 승격하지 않는다.
@@ -114,6 +118,7 @@
 - lift 전: 원본 블록이 실제 조작 대상처럼 보인다.
 - lift 직후 claim pending 동안에는 source 내부 local preview만 활성 owner다.
 - `rootClaimPending + non-day`에서는 `holding card`가 continuity 표현만 담당한다. 여기서 보이는 overlay는 `interaction ownership`을 뜻하지 않는다.
+- 같은 구간에서 `touch tracking relay`가 붙어 있으면 overlay는 손가락을 계속 따라가지만, 그것만으로 hover나 drop ownership이 열리지는 않는다.
 - root claim 성공 후: 원본 블록은 placeholder/ghost로 남고, 실제 이동 표현은 `single overlay`만 담당한다.
 - month/year에서는 `single active target`만 강조한다. 여러 날짜를 동시에 강조하지 않는다.
 - local preview와 root overlay가 동시에 활성 owner가 되면 안 된다.
```
