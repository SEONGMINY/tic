from __future__ import annotations

import math
from dataclasses import replace
from datetime import date
from statistics import mean
from typing import Iterable, List, Sequence, Tuple

from .models import (
    AggregateScore,
    ExpectedSession,
    Outcome,
    SessionResult,
    SessionScore,
    SessionSpec,
    SmoothnessMetrics,
    TraceFrame,
)


def score_session(
    session: SessionSpec,
    result: SessionResult,
    expected: ExpectedSession,
) -> SessionScore:
    metrics = compute_smoothness_metrics(session, result)

    drag_start_score = _score_drag_start(result, expected)
    session_continuity_score = _score_session_continuity(result, expected)
    hover_score = _score_hover(result, expected)
    drop_guard_score = 1.0 if result.drop_accepted == expected.should_accept_drop else 0.0
    final_result_score = _score_final_result(result, expected)
    restore_score = _score_restore(result, expected)

    correctness_total = (
        0.20 * drag_start_score
        + 0.15 * session_continuity_score
        + 0.15 * hover_score
        + 0.20 * drop_guard_score
        + 0.20 * final_result_score
        + 0.10 * restore_score
    )
    smoothness_total = _smoothness_total(metrics)
    combined_total = 0.8 * correctness_total + 0.2 * smoothness_total

    return SessionScore(
        session_id=session.session_id,
        drag_start_score=drag_start_score,
        session_continuity_score=session_continuity_score,
        hover_score=hover_score,
        drop_guard_score=drop_guard_score,
        final_result_score=final_result_score,
        restore_score=restore_score,
        correctness_total=correctness_total,
        smoothness_total=smoothness_total,
        combined_total=combined_total,
        smoothness_metrics=metrics,
    )


def aggregate_scores(scores: Sequence[SessionScore]) -> AggregateScore:
    if not scores:
        return AggregateScore(
            session_scores=tuple(),
            correctness_total=0.0,
            smoothness_total=0.0,
            combined_total=0.0,
        )
    return AggregateScore(
        session_scores=tuple(scores),
        correctness_total=mean(score.correctness_total for score in scores),
        smoothness_total=mean(score.smoothness_total for score in scores),
        combined_total=mean(score.combined_total for score in scores),
    )


def compute_smoothness_metrics(session: SessionSpec, result: SessionResult) -> SmoothnessMetrics:
    overlay_frames = [frame.overlay_frame_global for frame in result.trace if frame.overlay_frame_global]
    frame_jump_pt_p95 = _p95(
        _frame_distances(overlay_frames)
    )
    size_jump_ratio_p95 = _p95(_frame_size_ratios(overlay_frames))

    hover_churn_per_sec = _hover_churn_per_second(result.trace)
    restore_duration_ms = _restore_duration_ms(result.trace)
    restore_overshoot_pt = _restore_overshoot(session, result.trace)
    scope_transition_jump_pt = _scope_transition_jump(result.trace)
    overlay_anchor_error_pt = _overlay_anchor_error(session, result.trace)

    return SmoothnessMetrics(
        overlay_anchor_error_pt=overlay_anchor_error_pt,
        frame_jump_pt_p95=frame_jump_pt_p95,
        size_jump_ratio_p95=size_jump_ratio_p95,
        hover_churn_per_sec=hover_churn_per_sec,
        restore_duration_ms=restore_duration_ms,
        restore_overshoot_pt=restore_overshoot_pt,
        scope_transition_jump_pt=scope_transition_jump_pt,
    )


def stable_hover_dates_from_trace(trace: Sequence[TraceFrame]) -> List[Tuple[date, int]]:
    stable: List[Tuple[date, int]] = []
    seen = set()
    for frame in trace:
        if frame.active_date is None:
            continue
        if frame.active_date in seen:
            continue
        seen.add(frame.active_date)
        stable.append((frame.active_date, frame.ts_ms))
    return stable


def _score_drag_start(result: SessionResult, expected: ExpectedSession) -> float:
    if not expected.should_start_drag:
        return 1.0 if not result.drag_started else 0.0
    if not result.drag_started or result.drag_start_ts_ms is None:
        return 0.0
    if expected.expected_drag_start_ts_ms is None:
        return 1.0
    delta = abs(result.drag_start_ts_ms - expected.expected_drag_start_ts_ms)
    return max(0.0, 1.0 - (delta / 150.0))


def _score_session_continuity(result: SessionResult, expected: ExpectedSession) -> float:
    if not expected.expected_stable_hover_dates:
        return 1.0
    saw_calendar = any(frame.scope.value in {"month", "year"} for frame in result.trace)
    return 1.0 if saw_calendar and result.drag_started else 0.0


def _score_hover(result: SessionResult, expected: ExpectedSession) -> float:
    actual = stable_hover_dates_from_trace(result.trace)
    expected_values = [(item.date, item.from_ts_ms) for item in expected.expected_stable_hover_dates]
    if not expected_values:
        return 1.0 if not actual else 0.0
    matches = 0
    for expected_date, expected_ts in expected_values:
        for actual_date, actual_ts in actual:
            if actual_date == expected_date and abs(actual_ts - expected_ts) <= 160:
                matches += 1
                break
    return matches / float(len(expected_values))


def _score_final_result(result: SessionResult, expected: ExpectedSession) -> float:
    if not expected.should_accept_drop:
        return 1.0 if not result.drop_accepted else 0.0
    if result.final_drop_result is None or expected.expected_result is None:
        return 0.0

    date_score = 1.0 if result.final_drop_result.date == expected.expected_result.date else 0.0
    start_delta = abs(result.final_drop_result.start_minute - expected.expected_result.start_minute)
    end_delta = abs(result.final_drop_result.end_minute - expected.expected_result.end_minute)
    time_score = max(0.0, 1.0 - ((start_delta + end_delta) / 60.0))
    return (date_score * 0.5) + (time_score * 0.5)


def _score_restore(result: SessionResult, expected: ExpectedSession) -> float:
    if expected.should_accept_drop:
        return 1.0
    saw_restore = any(frame.state.value == "restoring" for frame in result.trace)
    if result.outcome == Outcome.NONE and not expected.should_start_drag:
        return 1.0
    return 1.0 if saw_restore and result.outcome == Outcome.CANCELLED else 0.0


def _smoothness_total(metrics: SmoothnessMetrics) -> float:
    anchor_component = max(0.0, 1.0 - metrics.overlay_anchor_error_pt / 20.0)
    jump_component = max(0.0, 1.0 - metrics.frame_jump_pt_p95 / 120.0)
    size_component = max(0.0, 1.0 - metrics.size_jump_ratio_p95 / 0.3)
    hover_component = max(0.0, 1.0 - metrics.hover_churn_per_sec / 4.0)
    restore_component = max(0.0, 1.0 - metrics.restore_duration_ms / 300.0)
    overshoot_component = max(0.0, 1.0 - metrics.restore_overshoot_pt / 80.0)
    scope_jump_component = max(0.0, 1.0 - metrics.scope_transition_jump_pt / 120.0)
    return mean(
        [
            anchor_component,
            jump_component,
            size_component,
            hover_component,
            restore_component,
            overshoot_component,
            scope_jump_component,
        ]
    )


def _overlay_anchor_error(session: SessionSpec, trace: Sequence[TraceFrame]) -> float:
    touch_frame = next((frame for frame in trace if frame.note == "touch_start"), None)
    if touch_frame is None or touch_frame.pointer_global is None:
        return 0.0
    anchor_x = touch_frame.pointer_global.x - session.item.frame_global.x
    anchor_y = touch_frame.pointer_global.y - session.item.frame_global.y

    errors = []
    for frame in trace:
        if frame.pointer_global is None or frame.overlay_frame_global is None:
            continue
        expected_pointer_x = frame.overlay_frame_global.x + anchor_x
        expected_pointer_y = frame.overlay_frame_global.y + anchor_y
        dx = frame.pointer_global.x - expected_pointer_x
        dy = frame.pointer_global.y - expected_pointer_y
        errors.append(math.sqrt(dx * dx + dy * dy))
    return mean(errors) if errors else 0.0


def _frame_distances(frames: Sequence) -> List[float]:
    distances: List[float] = []
    for left, right in zip(frames, frames[1:]):
        dx = right.x - left.x
        dy = right.y - left.y
        distances.append(math.sqrt(dx * dx + dy * dy))
    return distances


def _frame_size_ratios(frames: Sequence) -> List[float]:
    ratios: List[float] = []
    for left, right in zip(frames, frames[1:]):
        if left.width == 0 or left.height == 0:
            ratios.append(0.0)
            continue
        width_ratio = abs(right.width - left.width) / float(left.width)
        height_ratio = abs(right.height - left.height) / float(left.height)
        ratios.append(max(width_ratio, height_ratio))
    return ratios


def _hover_churn_per_second(trace: Sequence[TraceFrame]) -> float:
    changes = 0
    last_date = None
    first_ts = None
    last_ts = None
    for frame in trace:
        if frame.active_date != last_date and frame.active_date is not None:
            changes += 1
            last_date = frame.active_date
        if first_ts is None:
            first_ts = frame.ts_ms
        last_ts = frame.ts_ms
    if first_ts is None or last_ts is None or last_ts == first_ts:
        return 0.0
    return changes / ((last_ts - first_ts) / 1000.0)


def _restore_duration_ms(trace: Sequence[TraceFrame]) -> float:
    restore_ts = None
    for frame in trace:
        if frame.state.value == "restoring" and restore_ts is None:
            restore_ts = frame.ts_ms
        elif restore_ts is not None and frame.state.value == "idle":
            return float(frame.ts_ms - restore_ts)
    return 0.0


def _restore_overshoot(session: SessionSpec, trace: Sequence[TraceFrame]) -> float:
    for frame in trace:
        if frame.state.value == "restoring" and frame.overlay_frame_global is not None:
            dx = frame.overlay_frame_global.x - session.item.frame_global.x
            dy = frame.overlay_frame_global.y - session.item.frame_global.y
            return math.sqrt(dx * dx + dy * dy)
    return 0.0


def _scope_transition_jump(trace: Sequence[TraceFrame]) -> float:
    distances: List[float] = []
    for left, right in zip(trace, trace[1:]):
        if left.scope == right.scope:
            continue
        if left.overlay_frame_global is None or right.overlay_frame_global is None:
            continue
        dx = right.overlay_frame_global.x - left.overlay_frame_global.x
        dy = right.overlay_frame_global.y - left.overlay_frame_global.y
        distances.append(math.sqrt(dx * dx + dy * dy))
    return _p95(distances)


def _p95(values: Iterable[float]) -> float:
    ordered = sorted(values)
    if not ordered:
        return 0.0
    index = int(math.ceil(len(ordered) * 0.95)) - 1
    index = max(0, min(index, len(ordered) - 1))
    return ordered[index]
