from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
from typing import List, Optional

from .geometry import (
    build_final_drop_result,
    find_active_date,
    minute_candidate_from_pointer,
    overlay_frame_from_anchor,
)
from .models import (
    ConfigSpec,
    DragState,
    EventRecord,
    EventType,
    FinalDropResult,
    Outcome,
    Point,
    Rect,
    Scope,
    SessionResult,
    SessionSpec,
    TraceFrame,
)


@dataclass
class EngineContext:
    session: SessionSpec
    config: ConfigSpec
    state: DragState = DragState.IDLE
    outcome: Outcome = Outcome.NONE
    current_scope: Scope = Scope.DAY
    pointer_global: Optional[Point] = None
    anchor: Optional[Point] = None
    overlay_frame_global: Optional[Rect] = None
    date_candidate: Optional[date] = None
    minute_candidate: Optional[int] = None
    active_date: Optional[date] = None
    drag_started: bool = False
    drag_start_ts_ms: Optional[int] = None
    drop_accepted: bool = False
    final_drop_result: Optional[FinalDropResult] = None
    invalid_reason: Optional[str] = None
    press_start_point: Optional[Point] = None
    trace: List[TraceFrame] = field(default_factory=list)

    @property
    def duration_minute(self) -> int:
        return self.session.item.end_minute - self.session.item.start_minute


def replay_session(
    session: SessionSpec,
    events: List[EventRecord],
    config: ConfigSpec,
) -> SessionResult:
    context = EngineContext(session=session, config=config, current_scope=session.initial_scope)
    for event in events:
        apply_event(context, event)
    return SessionResult(
        session_id=session.session_id,
        drag_started=context.drag_started,
        drag_start_ts_ms=context.drag_start_ts_ms,
        final_state=context.state,
        outcome=context.outcome,
        drop_accepted=context.drop_accepted,
        date_candidate=context.date_candidate,
        minute_candidate=context.minute_candidate,
        final_drop_result=context.final_drop_result,
        trace=tuple(context.trace),
    )


def apply_event(context: EngineContext, event: EventRecord) -> None:
    context.invalid_reason = None
    if event.global_point is not None:
        context.pointer_global = event.global_point

    if event.type == EventType.TOUCH_START:
        _handle_touch_start(context, event)
        _record(context, event.ts_ms, "touch_start")
        return

    if event.type == EventType.LONG_PRESS_RECOGNIZED:
        _handle_long_press(context)
        _record(context, event.ts_ms, "long_press_recognized")
        return

    if event.type == EventType.DRAG_START:
        _handle_drag_start(context, event)
        _record(context, event.ts_ms, "drag_start")
        return

    if event.type == EventType.DRAG_MOVE:
        _handle_drag_move(context, event)
        _record(context, event.ts_ms, "drag_move")
        return

    if event.type == EventType.CALENDAR_MODE_ENTER:
        _handle_calendar_mode_enter(context, event)
        _record(context, event.ts_ms, "calendar_mode_enter")
        return

    if event.type == EventType.HOVER_DATE:
        _handle_hover_date(context, event)
        _record(context, event.ts_ms, "hover_date")
        return

    if event.type == EventType.DROP:
        _handle_drop(context, event.ts_ms)
        return

    if event.type == EventType.CANCEL:
        _start_restore(context, event.ts_ms, "cancelled_by_event")
        return


def _handle_touch_start(context: EngineContext, event: EventRecord) -> None:
    target = event.target
    if target is None or target.kind != "timeline_block" or target.part != "body":
        context.state = DragState.IDLE
        return
    context.state = DragState.PRESSING
    context.press_start_point = event.global_point
    context.pointer_global = event.global_point
    context.current_scope = context.session.initial_scope
    context.date_candidate = context.session.item.date
    context.minute_candidate = context.session.item.start_minute
    context.active_date = None
    if event.global_point is not None:
        context.anchor = Point(
            x=event.global_point.x - context.session.item.frame_global.x,
            y=event.global_point.y - context.session.item.frame_global.y,
        )
        context.overlay_frame_global = overlay_frame_from_anchor(
            event.global_point,
            context.anchor,
            context.session.item.frame_global,
        )


def _handle_long_press(context: EngineContext) -> None:
    if context.state == DragState.PRESSING:
        context.state = DragState.DRAG_READY


def _handle_drag_start(context: EngineContext, event: EventRecord) -> None:
    if context.state not in {DragState.DRAG_READY, DragState.DRAGGING_TIMELINE, DragState.DRAGGING_CALENDAR}:
        return
    if not context.drag_started:
        context.drag_started = True
        context.drag_start_ts_ms = event.ts_ms
    if context.current_scope == Scope.DAY:
        context.state = DragState.DRAGGING_TIMELINE
        _update_timeline_candidates(context, event.global_point)
    else:
        context.state = DragState.DRAGGING_CALENDAR
        _update_calendar_candidates(context, event.global_point)


def _handle_drag_move(context: EngineContext, event: EventRecord) -> None:
    if context.state == DragState.PRESSING:
        if context.press_start_point is None or event.global_point is None:
            return
        if _distance(context.press_start_point, event.global_point) > context.config.press_slop_pt:
            context.state = DragState.IDLE
            context.pointer_global = event.global_point
            context.invalid_reason = "false_start_pre_long_press"
            return

    if context.state == DragState.DRAG_READY and not context.drag_started:
        if context.press_start_point is not None and event.global_point is not None:
            if _distance(context.press_start_point, event.global_point) >= context.config.drag_start_min_distance_pt:
                context.drag_started = True
                context.drag_start_ts_ms = event.ts_ms
                context.state = (
                    DragState.DRAGGING_TIMELINE
                    if context.current_scope == Scope.DAY
                    else DragState.DRAGGING_CALENDAR
                )

    if context.state == DragState.DRAGGING_TIMELINE:
        _update_timeline_candidates(context, event.global_point)
    elif context.state == DragState.DRAGGING_CALENDAR:
        _update_calendar_candidates(context, event.global_point)


def _handle_calendar_mode_enter(context: EngineContext, event: EventRecord) -> None:
    if not context.drag_started:
        return
    context.current_scope = event.to_scope or context.current_scope
    if context.current_scope == Scope.DAY:
        context.state = DragState.DRAGGING_TIMELINE
        context.date_candidate = context.session.item.date
    else:
        context.state = DragState.DRAGGING_CALENDAR
        context.active_date = None
        context.date_candidate = None


def _handle_hover_date(context: EngineContext, event: EventRecord) -> None:
    if context.state != DragState.DRAGGING_CALENDAR or event.date is None:
        return
    context.active_date = event.date
    context.date_candidate = event.date


def _handle_drop(context: EngineContext, ts_ms: int) -> None:
    if context.state not in {DragState.DRAGGING_TIMELINE, DragState.DRAGGING_CALENDAR}:
        _record(context, ts_ms, "drop_ignored")
        return

    if context.current_scope == Scope.DAY:
        candidate_date = context.date_candidate or context.session.item.date
    else:
        candidate_date = context.active_date or context.date_candidate

    final_result = build_final_drop_result(
        date_candidate=candidate_date,
        minute_candidate=context.minute_candidate,
        duration_minute=context.duration_minute,
    )
    if final_result is None:
        _start_restore(context, ts_ms, "invalid_drop")
        return

    context.final_drop_result = final_result
    context.date_candidate = final_result.date
    context.minute_candidate = final_result.start_minute
    context.drop_accepted = True
    context.outcome = Outcome.DROPPED
    _record(context, ts_ms, "drop_commit")
    context.state = DragState.IDLE
    _record(context, ts_ms, "idle_after_drop")


def _start_restore(context: EngineContext, ts_ms: int, reason: str) -> None:
    context.state = DragState.RESTORING
    context.invalid_reason = reason
    context.outcome = Outcome.CANCELLED if context.drag_started else Outcome.NONE
    context.drop_accepted = False
    _record(context, ts_ms, "restore")
    context.state = DragState.IDLE
    _record(context, ts_ms, "idle_after_restore")


def _update_timeline_candidates(context: EngineContext, pointer_global: Optional[Point]) -> None:
    if pointer_global is None:
        return
    context.pointer_global = pointer_global
    context.current_scope = Scope.DAY
    context.date_candidate = context.session.item.date
    context.minute_candidate = minute_candidate_from_pointer(
        pointer_global,
        context.session.layouts.day,
        context.config.minute_snap_step,
    )
    if context.anchor is not None:
        context.overlay_frame_global = overlay_frame_from_anchor(
            pointer_global,
            context.anchor,
            context.session.item.frame_global,
        )


def _update_calendar_candidates(context: EngineContext, pointer_global: Optional[Point]) -> None:
    if pointer_global is None:
        return
    context.pointer_global = pointer_global
    layout = (
        context.session.layouts.month
        if context.current_scope == Scope.MONTH
        else context.session.layouts.year
    )
    context.active_date = find_active_date(
        pointer_global,
        layout,
        cell_hit_inset_pt=context.config.cell_hit_inset_pt,
        previous_active_date=context.active_date,
        cell_hysteresis_pt=context.config.cell_hysteresis_pt,
    )
    if context.active_date is not None:
        context.date_candidate = context.active_date
    if context.anchor is not None:
        context.overlay_frame_global = overlay_frame_from_anchor(
            pointer_global,
            context.anchor,
            context.session.item.frame_global,
        )


def _distance(start: Point, end: Point) -> float:
    dx = end.x - start.x
    dy = end.y - start.y
    return (dx * dx + dy * dy) ** 0.5


def _record(context: EngineContext, ts_ms: int, note: str) -> None:
    droppable = build_final_drop_result(
        date_candidate=(
            context.active_date or context.date_candidate
            if context.current_scope != Scope.DAY
            else context.date_candidate
        ),
        minute_candidate=context.minute_candidate,
        duration_minute=context.duration_minute,
    ) is not None and context.state in {
        DragState.DRAGGING_TIMELINE,
        DragState.DRAGGING_CALENDAR,
    }
    context.trace.append(
        TraceFrame(
            ts_ms=ts_ms,
            state=context.state,
            outcome=context.outcome,
            scope=context.current_scope,
            droppable=droppable,
            pointer_global=context.pointer_global,
            overlay_frame_global=context.overlay_frame_global,
            date_candidate=context.date_candidate,
            minute_candidate=context.minute_candidate,
            active_date=context.active_date,
            invalid_reason=context.invalid_reason,
            note=note,
        )
    )
