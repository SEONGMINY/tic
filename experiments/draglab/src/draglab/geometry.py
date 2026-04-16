from __future__ import annotations

import math
from datetime import date
from typing import Optional

from .models import CalendarGridLayoutSpec, DayLayoutSpec, FinalDropResult, Point, Rect


def inset_rect(rect: Rect, inset: float) -> Rect:
    width = max(0.0, rect.width - inset * 2)
    height = max(0.0, rect.height - inset * 2)
    return Rect(
        x=rect.x + inset,
        y=rect.y + inset,
        width=width,
        height=height,
    )


def expand_rect(rect: Rect, amount: float) -> Rect:
    return Rect(
        x=rect.x - amount,
        y=rect.y - amount,
        width=rect.width + amount * 2,
        height=rect.height + amount * 2,
    )


def point_in_rect(point: Point, rect: Rect) -> bool:
    return (
        rect.x <= point.x <= rect.x + rect.width
        and rect.y <= point.y <= rect.y + rect.height
    )


def timeline_local_y(pointer_global: Point, layout: DayLayoutSpec) -> float:
    return pointer_global.y - layout.timeline_frame_global.y + layout.scroll_offset_y


def raw_minute_from_local_y(local_y: float, hour_height: float) -> float:
    return (local_y / hour_height) * 60.0


def clamp_minute(minute_value: float) -> float:
    return min(1439.0, max(0.0, minute_value))


def snap_minute(minute_value: float, snap_step: int) -> int:
    scaled = minute_value / float(snap_step)
    snapped = math.floor(scaled + 0.5) * snap_step
    return int(snapped)


def minute_candidate_from_pointer(
    pointer_global: Point,
    layout: DayLayoutSpec,
    snap_step: int,
) -> int:
    local_y = timeline_local_y(pointer_global, layout)
    raw_minute = raw_minute_from_local_y(local_y, layout.hour_height)
    return snap_minute(clamp_minute(raw_minute), snap_step)


def overlay_frame_from_anchor(pointer_global: Point, anchor: Point, original_frame: Rect) -> Rect:
    return Rect(
        x=pointer_global.x - anchor.x,
        y=pointer_global.y - anchor.y,
        width=original_frame.width,
        height=original_frame.height,
    )


def find_active_date(
    pointer_global: Point,
    layout: CalendarGridLayoutSpec,
    cell_hit_inset_pt: float,
    previous_active_date: Optional[date] = None,
    cell_hysteresis_pt: float = 0.0,
) -> Optional[date]:
    previous_cell = None
    if previous_active_date is not None:
        for cell in layout.cells:
            if cell.date == previous_active_date:
                previous_cell = cell
                break
    if previous_cell is not None:
        if point_in_rect(pointer_global, expand_rect(previous_cell.frame_global, cell_hysteresis_pt)):
            return previous_active_date

    for cell in layout.cells:
        target_rect = inset_rect(cell.frame_global, cell_hit_inset_pt)
        if point_in_rect(pointer_global, target_rect):
            return cell.date
    return None


def build_final_drop_result(
    date_candidate: Optional[date],
    minute_candidate: Optional[int],
    duration_minute: int,
) -> Optional[FinalDropResult]:
    if date_candidate is None or minute_candidate is None:
        return None
    if minute_candidate < 0:
        return None
    end_minute = minute_candidate + duration_minute
    if end_minute > 1440:
        return None
    return FinalDropResult(
        date=date_candidate,
        start_minute=minute_candidate,
        end_minute=end_minute,
    )
