from __future__ import annotations

import unittest
from pathlib import Path

from draglab.contracts import load_config, load_dataset
from draglab.models import DragState, Outcome
from draglab.replay import replay_dataset


ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data"
BASELINE_PATH = ROOT / "configs" / "baseline.json"


class StateMachineTest(unittest.TestCase):
    def setUp(self) -> None:
        self.dataset = load_dataset(DATA_DIR)
        self.config = load_config(BASELINE_PATH)
        self.results = replay_dataset(self.dataset, self.config)

    def test_false_start_does_not_start_drag(self) -> None:
        result = self.results["s003"]
        self.assertFalse(result.drag_started)
        self.assertEqual(result.drag_start_ts_ms, None)
        self.assertEqual(result.outcome, Outcome.NONE)
        self.assertEqual(result.final_state, DragState.IDLE)

    def test_timeline_drag_starts_after_long_press(self) -> None:
        result = self.results["s001"]
        self.assertTrue(result.drag_started)
        self.assertEqual(result.drag_start_ts_ms, 560)
        self.assertEqual(result.outcome, Outcome.DROPPED)

    def test_cross_scope_session_is_kept(self) -> None:
        result = self.results["s002"]
        scopes = [frame.scope.value for frame in result.trace]
        self.assertIn("day", scopes)
        self.assertIn("month", scopes)
        self.assertTrue(result.drop_accepted)
        self.assertEqual(str(result.final_drop_result.date), "2026-04-20")

    def test_invalid_drop_restores(self) -> None:
        result = self.results["s004"]
        states = [frame.state for frame in result.trace]
        self.assertIn(DragState.RESTORING, states)
        self.assertEqual(result.outcome, Outcome.CANCELLED)
        self.assertFalse(result.drop_accepted)

    def test_cancel_event_restores_and_ends_idle(self) -> None:
        result = self.results["s006"]
        self.assertEqual(result.final_state, DragState.IDLE)
        self.assertEqual(result.outcome, Outcome.CANCELLED)


if __name__ == "__main__":
    unittest.main()
