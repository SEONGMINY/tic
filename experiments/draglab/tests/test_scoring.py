from __future__ import annotations

import unittest
from dataclasses import replace
from pathlib import Path

from draglab.contracts import load_config, load_dataset
from draglab.models import Outcome, TraceFrame
from draglab.replay import replay_dataset
from draglab.scoring import aggregate_scores, score_session


ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data"
BASELINE_PATH = ROOT / "configs" / "baseline.json"


class ScoringTest(unittest.TestCase):
    def setUp(self) -> None:
        self.dataset = load_dataset(DATA_DIR)
        self.config = load_config(BASELINE_PATH)
        self.results = replay_dataset(self.dataset, self.config)

    def test_matching_positive_session_scores_high(self) -> None:
        session = self.dataset.sessions_by_id["s002"]
        expected = self.dataset.expected_by_session_id["s002"]
        result = self.results["s002"]
        score = score_session(session, result, expected)
        self.assertGreater(score.correctness_total, 0.8)

    def test_wrong_drag_start_lowers_score(self) -> None:
        session = self.dataset.sessions_by_id["s002"]
        expected = self.dataset.expected_by_session_id["s002"]
        wrong_result = replace(self.results["s002"], drag_start_ts_ms=900)
        score = score_session(session, wrong_result, expected)
        self.assertLess(score.drag_start_score, 0.2)

    def test_invalid_drop_without_guard_lowers_score(self) -> None:
        session = self.dataset.sessions_by_id["s004"]
        expected = self.dataset.expected_by_session_id["s004"]
        wrong_result = replace(
            self.results["s004"],
            drop_accepted=True,
            outcome=Outcome.DROPPED,
        )
        score = score_session(session, wrong_result, expected)
        self.assertEqual(score.drop_guard_score, 0.0)

    def test_missing_restore_trace_lowers_restore_score(self) -> None:
        session = self.dataset.sessions_by_id["s004"]
        expected = self.dataset.expected_by_session_id["s004"]
        trace_without_restore = tuple(
            frame for frame in self.results["s004"].trace if frame.state.value != "restoring"
        )
        wrong_result = replace(self.results["s004"], trace=trace_without_restore)
        score = score_session(session, wrong_result, expected)
        self.assertEqual(score.restore_score, 0.0)

    def test_smoothness_metrics_are_deterministic(self) -> None:
        session = self.dataset.sessions_by_id["s002"]
        expected = self.dataset.expected_by_session_id["s002"]
        result = self.results["s002"]
        left = score_session(session, result, expected)
        right = score_session(session, result, expected)
        self.assertEqual(left.smoothness_metrics, right.smoothness_metrics)

    def test_aggregate_score_uses_mean(self) -> None:
        scored = [
            score_session(
                self.dataset.sessions_by_id[session_id],
                self.results[session_id],
                self.dataset.expected_by_session_id[session_id],
            )
            for session_id in ("s001", "s002", "s004")
        ]
        aggregate = aggregate_scores(scored)
        self.assertEqual(len(aggregate.session_scores), 3)
        self.assertGreater(aggregate.combined_total, 0.0)


if __name__ == "__main__":
    unittest.main()
