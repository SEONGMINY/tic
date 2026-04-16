from __future__ import annotations

from typing import Dict

from .models import ConfigSpec, Dataset, SessionResult
from .state_machine import replay_session


def replay_dataset(dataset: Dataset, config: ConfigSpec) -> Dict[str, SessionResult]:
    results: Dict[str, SessionResult] = {}
    events_by_session = dataset.events_by_session_id
    for session in dataset.sessions:
        session_events = list(events_by_session[session.session_id].events)
        results[session.session_id] = replay_session(session, session_events, config)
    return results
