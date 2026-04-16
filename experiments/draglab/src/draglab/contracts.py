from __future__ import annotations

import json
from datetime import date
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple, Union

from .models import (
    CalendarCellSpec,
    CalendarGridLayoutSpec,
    ConfigSpec,
    Dataset,
    DayLayoutSpec,
    DeviceSpec,
    DropResultExpectation,
    EventRecord,
    EventType,
    ExpectedSession,
    ItemSpec,
    LayoutsSpec,
    Outcome,
    Point,
    Rect,
    SafeArea,
    Scope,
    SearchSpaceSpec,
    SessionEvents,
    SessionSpec,
    StableHoverExpectation,
    TargetSpec,
)


class ContractValidationError(ValueError):
    def __init__(self, errors: List[str]):
        self.errors = errors
        super().__init__("\n".join(errors))


def load_json(path: Union[str, Path]) -> Dict[str, Any]:
    with Path(path).open("r", encoding="utf-8") as handle:
        return json.load(handle)


def load_dataset(data_dir: Union[str, Path]) -> Dataset:
    root = Path(data_dir)
    sessions_doc = load_json(root / "sessions.json")
    events_doc = load_json(root / "events.json")
    expected_doc = load_json(root / "expected.json")

    errors = validate_dataset_documents(sessions_doc, events_doc, expected_doc)
    if errors:
        raise ContractValidationError(errors)

    schema_version = int(sessions_doc["schemaVersion"])
    sessions = tuple(_parse_session(entry) for entry in sessions_doc["sessions"])
    session_events = tuple(_parse_session_events(entry) for entry in events_doc["sessions"])
    expected_sessions = tuple(
        _parse_expected_session(entry) for entry in expected_doc["sessions"]
    )
    return Dataset(
        schema_version=schema_version,
        sessions=sessions,
        session_events=session_events,
        expected_sessions=expected_sessions,
    )


def load_config(path: Union[str, Path]) -> ConfigSpec:
    doc = load_json(path)
    return config_from_dict(doc)


def config_from_dict(doc: Dict[str, Any]) -> ConfigSpec:
    required = {
        "schemaVersion",
        "longPressMinMs",
        "pressSlopPt",
        "dragStartMinDistancePt",
        "hoverActivationMs",
        "hoverExitMs",
        "cellHitInsetPt",
        "cellHysteresisPt",
        "timelineDropInsetPt",
        "minuteSnapStep",
        "minimumDurationMinute",
        "restoreAnimationMs",
        "reanchorBlendMs",
        "invalidDropPolicy",
    }
    missing = sorted(required - doc.keys())
    if missing:
        raise ContractValidationError([f"config missing required fields: {', '.join(missing)}"])
    return ConfigSpec(
        schema_version=int(doc["schemaVersion"]),
        long_press_min_ms=int(doc["longPressMinMs"]),
        press_slop_pt=float(doc["pressSlopPt"]),
        drag_start_min_distance_pt=float(doc["dragStartMinDistancePt"]),
        hover_activation_ms=int(doc["hoverActivationMs"]),
        hover_exit_ms=int(doc["hoverExitMs"]),
        cell_hit_inset_pt=float(doc["cellHitInsetPt"]),
        cell_hysteresis_pt=float(doc["cellHysteresisPt"]),
        timeline_drop_inset_pt=float(doc["timelineDropInsetPt"]),
        minute_snap_step=int(doc["minuteSnapStep"]),
        minimum_duration_minute=int(doc["minimumDurationMinute"]),
        restore_animation_ms=int(doc["restoreAnimationMs"]),
        reanchor_blend_ms=int(doc["reanchorBlendMs"]),
        invalid_drop_policy=str(doc["invalidDropPolicy"]),
    )


def load_search_space(path: Union[str, Path]) -> SearchSpaceSpec:
    doc = load_json(path)
    search_space = {
        key: tuple(values) for key, values in dict(doc.get("searchSpace", {})).items()
    }
    if not search_space:
        raise ContractValidationError(["search space must define at least one parameter"])
    return SearchSpaceSpec(
        schema_version=int(doc["schemaVersion"]),
        search_space=search_space,
    )


def validate_dataset_documents(
    sessions_doc: Dict[str, Any],
    events_doc: Dict[str, Any],
    expected_doc: Dict[str, Any],
) -> List[str]:
    errors: List[str] = []

    sessions = sessions_doc.get("sessions")
    events = events_doc.get("sessions")
    expected = expected_doc.get("sessions")

    errors.extend(_require_top_level(sessions_doc, "sessions.json", {"schemaVersion", "sessions"}))
    errors.extend(_require_top_level(events_doc, "events.json", {"schemaVersion", "sessions"}))
    errors.extend(_require_top_level(expected_doc, "expected.json", {"schemaVersion", "sessions"}))

    if not isinstance(sessions, list):
        errors.append("sessions.json.sessions must be a list")
        sessions = []
    if not isinstance(events, list):
        errors.append("events.json.sessions must be a list")
        events = []
    if not isinstance(expected, list):
        errors.append("expected.json.sessions must be a list")
        expected = []

    session_ids = _collect_ids(sessions, "sessions.json", errors)
    event_ids = _collect_ids(events, "events.json", errors)
    expected_ids = _collect_ids(expected, "expected.json", errors)

    missing_events = sorted(set(session_ids) - set(event_ids))
    if missing_events:
        errors.append(f"events.json missing sessions: {', '.join(missing_events)}")

    missing_expected = sorted(set(session_ids) - set(expected_ids))
    if missing_expected:
        errors.append(f"expected.json missing sessions: {', '.join(missing_expected)}")

    unknown_event_sessions = sorted(set(event_ids) - set(session_ids))
    if unknown_event_sessions:
        errors.append(f"events.json references unknown sessions: {', '.join(unknown_event_sessions)}")

    unknown_expected_sessions = sorted(set(expected_ids) - set(session_ids))
    if unknown_expected_sessions:
        errors.append(
            f"expected.json references unknown sessions: {', '.join(unknown_expected_sessions)}"
        )

    for idx, session in enumerate(sessions):
        errors.extend(_validate_session_dict(session, idx))
    for idx, session_events in enumerate(events):
        errors.extend(_validate_session_events_dict(session_events, idx))
    for idx, expected_session in enumerate(expected):
        errors.extend(_validate_expected_session_dict(expected_session, idx))

    return errors


def _require_top_level(doc: Dict[str, Any], name: str, fields: Set[str]) -> List[str]:
    missing = sorted(field for field in fields if field not in doc)
    if not missing:
        return []
    return [f"{name} missing required fields: {', '.join(missing)}"]


def _collect_ids(entries: List[Dict[str, Any]], filename: str, errors: List[str]) -> List[str]:
    ids: List[str] = []
    seen: Set[str] = set()
    for idx, entry in enumerate(entries):
        session_id = entry.get("sessionId")
        if not isinstance(session_id, str) or not session_id:
            errors.append(f"{filename}[{idx}] missing sessionId")
            continue
        if session_id in seen:
            errors.append(f"{filename} duplicate sessionId: {session_id}")
        seen.add(session_id)
        ids.append(session_id)
    return ids


def _validate_session_dict(session: Dict[str, Any], idx: int) -> List[str]:
    prefix = f"sessions.json[{idx}]"
    required = {
        "sessionId",
        "scenarioTags",
        "timezone",
        "initialScope",
        "device",
        "item",
        "layouts",
        "split",
    }
    errors = _missing_field_errors(session, prefix, required)
    if errors:
        return errors
    if session["initialScope"] not in {scope.value for scope in Scope}:
        errors.append(f"{prefix}.initialScope must be one of day/month/year")
    if not isinstance(session["scenarioTags"], list):
        errors.append(f"{prefix}.scenarioTags must be a list")
    errors.extend(_validate_rect_dict(session["item"].get("frameGlobal"), f"{prefix}.item.frameGlobal"))
    errors.extend(_validate_day_layout_dict(session["layouts"].get("day"), f"{prefix}.layouts.day"))
    errors.extend(
        _validate_grid_layout_dict(session["layouts"].get("month"), f"{prefix}.layouts.month")
    )
    errors.extend(
        _validate_grid_layout_dict(session["layouts"].get("year"), f"{prefix}.layouts.year")
    )
    return errors


def _validate_session_events_dict(session_events: Dict[str, Any], idx: int) -> List[str]:
    prefix = f"events.json[{idx}]"
    errors = _missing_field_errors(session_events, prefix, {"sessionId", "events"})
    if errors:
        return errors
    events = session_events["events"]
    if not isinstance(events, list):
        return [f"{prefix}.events must be a list"]
    for event_idx, event in enumerate(events):
        event_prefix = f"{prefix}.events[{event_idx}]"
        errors.extend(_missing_field_errors(event, event_prefix, {"tsMs", "type"}))
        event_type = event.get("type")
        if event_type not in {kind.value for kind in EventType}:
            errors.append(f"{event_prefix}.type has unsupported value: {event_type}")
        if "global" in event:
            errors.extend(_validate_point_dict(event["global"], f"{event_prefix}.global"))
    return errors


def _validate_expected_session_dict(expected: Dict[str, Any], idx: int) -> List[str]:
    prefix = f"expected.json[{idx}]"
    required = {
        "sessionId",
        "shouldStartDrag",
        "expectedDragStartTsMs",
        "expectedStableHoverDates",
        "shouldAcceptDrop",
        "expectedResult",
        "expectedOutcome",
    }
    errors = _missing_field_errors(expected, prefix, required)
    if errors:
        return errors
    outcome = expected["expectedOutcome"]
    if outcome not in {outcome.value for outcome in Outcome}:
        errors.append(f"{prefix}.expectedOutcome has unsupported value: {outcome}")
    stable_hover_dates = expected["expectedStableHoverDates"]
    if not isinstance(stable_hover_dates, list):
        errors.append(f"{prefix}.expectedStableHoverDates must be a list")
    result = expected["expectedResult"]
    if result is not None:
        errors.extend(_missing_field_errors(result, f"{prefix}.expectedResult", {"date", "startMinute", "endMinute"}))
    return errors


def _missing_field_errors(
    payload: Optional[Dict[str, Any]], prefix: str, fields: Set[str]
) -> List[str]:
    if not isinstance(payload, dict):
        return [f"{prefix} must be an object"]
    missing = sorted(field for field in fields if field not in payload)
    return [f"{prefix} missing required fields: {', '.join(missing)}"] if missing else []


def _validate_point_dict(payload: Optional[Dict[str, Any]], prefix: str) -> List[str]:
    return _missing_field_errors(payload, prefix, {"x", "y"})


def _validate_rect_dict(payload: Optional[Dict[str, Any]], prefix: str) -> List[str]:
    return _missing_field_errors(payload, prefix, {"x", "y", "width", "height"})


def _validate_day_layout_dict(payload: Optional[Dict[str, Any]], prefix: str) -> List[str]:
    required = {
        "timelineFrameGlobal",
        "scrollOffsetY",
        "hourHeight",
        "timeColumnWidth",
        "eventAreaLeadingInset",
    }
    errors = _missing_field_errors(payload, prefix, required)
    if errors:
        return errors
    return _validate_rect_dict(payload["timelineFrameGlobal"], f"{prefix}.timelineFrameGlobal")


def _validate_grid_layout_dict(payload: Optional[Dict[str, Any]], prefix: str) -> List[str]:
    errors = _missing_field_errors(payload, prefix, {"gridFrameGlobal", "cells"})
    if errors:
        return errors
    errors.extend(_validate_rect_dict(payload["gridFrameGlobal"], f"{prefix}.gridFrameGlobal"))
    cells = payload["cells"]
    if not isinstance(cells, list):
        return [f"{prefix}.cells must be a list"]
    for idx, cell in enumerate(cells):
        cell_prefix = f"{prefix}.cells[{idx}]"
        errors.extend(_missing_field_errors(cell, cell_prefix, {"date", "frameGlobal"}))
        if isinstance(cell, dict) and "frameGlobal" in cell:
            errors.extend(_validate_rect_dict(cell["frameGlobal"], f"{cell_prefix}.frameGlobal"))
    return errors


def _parse_session(entry: Dict[str, Any]) -> SessionSpec:
    return SessionSpec(
        session_id=entry["sessionId"],
        scenario_tags=tuple(entry["scenarioTags"]),
        timezone=entry["timezone"],
        initial_scope=Scope(entry["initialScope"]),
        device=_parse_device(entry["device"]),
        item=_parse_item(entry["item"]),
        layouts=_parse_layouts(entry["layouts"]),
        split=entry["split"],
    )


def _parse_device(entry: Dict[str, Any]) -> DeviceSpec:
    safe = entry["safeArea"]
    return DeviceSpec(
        width_pt=float(entry["widthPt"]),
        height_pt=float(entry["heightPt"]),
        safe_area=SafeArea(
            top=float(safe["top"]),
            left=float(safe["left"]),
            right=float(safe["right"]),
            bottom=float(safe["bottom"]),
        ),
    )


def _parse_item(entry: Dict[str, Any]) -> ItemSpec:
    return ItemSpec(
        item_id=entry["itemId"],
        date=date.fromisoformat(entry["date"]),
        start_minute=int(entry["startMinute"]),
        end_minute=int(entry["endMinute"]),
        frame_global=_parse_rect(entry["frameGlobal"]),
    )


def _parse_layouts(entry: Dict[str, Any]) -> LayoutsSpec:
    return LayoutsSpec(
        day=DayLayoutSpec(
            timeline_frame_global=_parse_rect(entry["day"]["timelineFrameGlobal"]),
            scroll_offset_y=float(entry["day"]["scrollOffsetY"]),
            hour_height=float(entry["day"]["hourHeight"]),
            time_column_width=float(entry["day"]["timeColumnWidth"]),
            event_area_leading_inset=float(entry["day"]["eventAreaLeadingInset"]),
        ),
        month=_parse_grid_layout(entry["month"]),
        year=_parse_grid_layout(entry["year"]),
    )


def _parse_grid_layout(entry: Dict[str, Any]) -> CalendarGridLayoutSpec:
    cells = tuple(
        CalendarCellSpec(
            date=date.fromisoformat(cell["date"]),
            frame_global=_parse_rect(cell["frameGlobal"]),
        )
        for cell in entry["cells"]
    )
    return CalendarGridLayoutSpec(
        grid_frame_global=_parse_rect(entry["gridFrameGlobal"]),
        cells=cells,
    )


def _parse_rect(entry: Dict[str, Any]) -> Rect:
    return Rect(
        x=float(entry["x"]),
        y=float(entry["y"]),
        width=float(entry["width"]),
        height=float(entry["height"]),
    )


def _parse_session_events(entry: Dict[str, Any]) -> SessionEvents:
    return SessionEvents(
        session_id=entry["sessionId"],
        events=tuple(_parse_event(event) for event in entry["events"]),
    )


def _parse_event(entry: Dict[str, Any]) -> EventRecord:
    global_payload = entry.get("global")
    target_payload = entry.get("target")
    return EventRecord(
        ts_ms=int(entry["tsMs"]),
        type=EventType(entry["type"]),
        global_point=_parse_point(global_payload) if global_payload is not None else None,
        target=(
            TargetSpec(
                kind=target_payload["kind"],
                item_id=target_payload.get("itemId"),
                part=target_payload.get("part"),
            )
            if target_payload is not None
            else None
        ),
        scope=Scope(entry["scope"]) if entry.get("scope") else None,
        date=date.fromisoformat(entry["date"]) if entry.get("date") else None,
        from_scope=Scope(entry["from"]) if entry.get("from") else None,
        to_scope=Scope(entry["to"]) if entry.get("to") else None,
    )


def _parse_point(entry: Dict[str, Any]) -> Point:
    return Point(x=float(entry["x"]), y=float(entry["y"]))


def _parse_expected_session(entry: Dict[str, Any]) -> ExpectedSession:
    result = entry["expectedResult"]
    return ExpectedSession(
        session_id=entry["sessionId"],
        should_start_drag=bool(entry["shouldStartDrag"]),
        expected_drag_start_ts_ms=(
            int(entry["expectedDragStartTsMs"])
            if entry["expectedDragStartTsMs"] is not None
            else None
        ),
        expected_stable_hover_dates=tuple(
            StableHoverExpectation(
                date=date.fromisoformat(item["date"]),
                from_ts_ms=int(item["fromTsMs"]),
            )
            for item in entry["expectedStableHoverDates"]
        ),
        should_accept_drop=bool(entry["shouldAcceptDrop"]),
        expected_result=(
            DropResultExpectation(
                date=date.fromisoformat(result["date"]),
                start_minute=int(result["startMinute"]),
                end_minute=int(result["endMinute"]),
            )
            if result is not None
            else None
        ),
        expected_outcome=Outcome(entry["expectedOutcome"]),
    )
