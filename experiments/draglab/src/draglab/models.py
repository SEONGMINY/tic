from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from enum import Enum
from typing import Dict, Optional, Tuple


class Scope(str, Enum):
    DAY = "day"
    MONTH = "month"
    YEAR = "year"


class EventType(str, Enum):
    TOUCH_START = "touch_start"
    LONG_PRESS_RECOGNIZED = "long_press_recognized"
    DRAG_START = "drag_start"
    DRAG_MOVE = "drag_move"
    CALENDAR_MODE_ENTER = "calendar_mode_enter"
    HOVER_DATE = "hover_date"
    DROP = "drop"
    CANCEL = "cancel"


class Outcome(str, Enum):
    NONE = "none"
    DROPPED = "dropped"
    CANCELLED = "cancelled"


class DragState(str, Enum):
    IDLE = "idle"
    PRESSING = "pressing"
    DRAG_READY = "drag_ready"
    DRAGGING_TIMELINE = "dragging_timeline"
    DRAGGING_CALENDAR = "dragging_calendar"
    RESTORING = "restoring"


@dataclass(frozen=True)
class Point:
    x: float
    y: float


@dataclass(frozen=True)
class Rect:
    x: float
    y: float
    width: float
    height: float


@dataclass(frozen=True)
class SafeArea:
    top: float
    left: float
    right: float
    bottom: float


@dataclass(frozen=True)
class DeviceSpec:
    width_pt: float
    height_pt: float
    safe_area: SafeArea


@dataclass(frozen=True)
class CalendarCellSpec:
    date: date
    frame_global: Rect


@dataclass(frozen=True)
class DayLayoutSpec:
    timeline_frame_global: Rect
    scroll_offset_y: float
    hour_height: float
    time_column_width: float
    event_area_leading_inset: float


@dataclass(frozen=True)
class CalendarGridLayoutSpec:
    grid_frame_global: Rect
    cells: Tuple[CalendarCellSpec, ...]


@dataclass(frozen=True)
class LayoutsSpec:
    day: DayLayoutSpec
    month: CalendarGridLayoutSpec
    year: CalendarGridLayoutSpec


@dataclass(frozen=True)
class ItemSpec:
    item_id: str
    date: date
    start_minute: int
    end_minute: int
    frame_global: Rect


@dataclass(frozen=True)
class SessionSpec:
    session_id: str
    scenario_tags: Tuple[str, ...]
    timezone: str
    initial_scope: Scope
    device: DeviceSpec
    item: ItemSpec
    layouts: LayoutsSpec
    split: str


@dataclass(frozen=True)
class TargetSpec:
    kind: str
    item_id: Optional[str] = None
    part: Optional[str] = None


@dataclass(frozen=True)
class EventRecord:
    ts_ms: int
    type: EventType
    global_point: Optional[Point] = None
    target: Optional[TargetSpec] = None
    scope: Optional[Scope] = None
    date: Optional[date] = None
    from_scope: Optional[Scope] = None
    to_scope: Optional[Scope] = None


@dataclass(frozen=True)
class SessionEvents:
    session_id: str
    events: Tuple[EventRecord, ...]


@dataclass(frozen=True)
class StableHoverExpectation:
    date: date
    from_ts_ms: int


@dataclass(frozen=True)
class DropResultExpectation:
    date: date
    start_minute: int
    end_minute: int


@dataclass(frozen=True)
class ExpectedSession:
    session_id: str
    should_start_drag: bool
    expected_drag_start_ts_ms: Optional[int]
    expected_stable_hover_dates: Tuple[StableHoverExpectation, ...]
    should_accept_drop: bool
    expected_result: Optional[DropResultExpectation]
    expected_outcome: Outcome


@dataclass(frozen=True)
class ConfigSpec:
    schema_version: int
    long_press_min_ms: int
    press_slop_pt: float
    drag_start_min_distance_pt: float
    hover_activation_ms: int
    hover_exit_ms: int
    cell_hit_inset_pt: float
    cell_hysteresis_pt: float
    timeline_drop_inset_pt: float
    minute_snap_step: int
    minimum_duration_minute: int
    restore_animation_ms: int
    reanchor_blend_ms: int
    invalid_drop_policy: str


@dataclass(frozen=True)
class SearchSpaceSpec:
    schema_version: int
    search_space: Dict[str, Tuple[object, ...]]


@dataclass(frozen=True)
class FinalDropResult:
    date: date
    start_minute: int
    end_minute: int


@dataclass(frozen=True)
class TraceFrame:
    ts_ms: int
    state: DragState
    outcome: Outcome
    scope: Scope
    droppable: bool
    pointer_global: Optional[Point]
    overlay_frame_global: Optional[Rect]
    date_candidate: Optional[date]
    minute_candidate: Optional[int]
    active_date: Optional[date]
    invalid_reason: Optional[str]
    note: Optional[str]


@dataclass(frozen=True)
class SessionResult:
    session_id: str
    drag_started: bool
    drag_start_ts_ms: Optional[int]
    final_state: DragState
    outcome: Outcome
    drop_accepted: bool
    date_candidate: Optional[date]
    minute_candidate: Optional[int]
    final_drop_result: Optional[FinalDropResult]
    trace: Tuple[TraceFrame, ...]


@dataclass(frozen=True)
class SmoothnessMetrics:
    overlay_anchor_error_pt: float
    frame_jump_pt_p95: float
    size_jump_ratio_p95: float
    hover_churn_per_sec: float
    restore_duration_ms: float
    restore_overshoot_pt: float
    scope_transition_jump_pt: float


@dataclass(frozen=True)
class SessionScore:
    session_id: str
    drag_start_score: float
    session_continuity_score: float
    hover_score: float
    drop_guard_score: float
    final_result_score: float
    restore_score: float
    correctness_total: float
    smoothness_total: float
    combined_total: float
    smoothness_metrics: SmoothnessMetrics


@dataclass(frozen=True)
class AggregateScore:
    session_scores: Tuple[SessionScore, ...]
    correctness_total: float
    smoothness_total: float
    combined_total: float


@dataclass(frozen=True)
class Dataset:
    schema_version: int
    sessions: Tuple[SessionSpec, ...]
    session_events: Tuple[SessionEvents, ...]
    expected_sessions: Tuple[ExpectedSession, ...]

    @property
    def sessions_by_id(self) -> Dict[str, SessionSpec]:
        return {session.session_id: session for session in self.sessions}

    @property
    def events_by_session_id(self) -> Dict[str, SessionEvents]:
        return {entry.session_id: entry for entry in self.session_events}

    @property
    def expected_by_session_id(self) -> Dict[str, ExpectedSession]:
        return {entry.session_id: entry for entry in self.expected_sessions}
