from __future__ import annotations

import unittest
from datetime import date
from pathlib import Path

from draglab.contracts import load_dataset
from draglab.geometry import (
    build_final_drop_result,
    find_active_date,
    minute_candidate_from_pointer,
    overlay_frame_from_anchor,
)
from draglab.models import Point


ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data"


class GeometryTest(unittest.TestCase):
    def setUp(self) -> None:
        self.dataset = load_dataset(DATA_DIR)
        self.session = self.dataset.sessions_by_id["s002"]

    def test_y_to_minute_and_snap(self) -> None:
        minute = minute_candidate_from_pointer(
            Point(x=180, y=412),
            self.session.layouts.day,
            snap_step=15,
        )
        self.assertEqual(minute, 510)

    def test_overlay_anchor_preserves_frame_size(self) -> None:
        frame = overlay_frame_from_anchor(
            pointer_global=Point(x=210, y=450),
            anchor=Point(x=120, y=40),
            original_frame=self.session.item.frame_global,
        )
        self.assertEqual(frame.width, self.session.item.frame_global.width)
        self.assertEqual(frame.height, self.session.item.frame_global.height)
        self.assertEqual(frame.x, 90)
        self.assertEqual(frame.y, 410)

    def test_find_active_date_prefers_hit_cell(self) -> None:
        active_date = find_active_date(
            pointer_global=Point(x=96, y=298),
            layout=self.session.layouts.month,
            cell_hit_inset_pt=6,
        )
        self.assertEqual(active_date, date(2026, 4, 20))

    def test_find_active_date_respects_hysteresis(self) -> None:
        active_date = find_active_date(
            pointer_global=Point(x=126, y=298),
            layout=self.session.layouts.month,
            cell_hit_inset_pt=6,
            previous_active_date=date(2026, 4, 20),
            cell_hysteresis_pt=12,
        )
        self.assertEqual(active_date, date(2026, 4, 20))

    def test_build_final_drop_result_rejects_overflow(self) -> None:
        result = build_final_drop_result(
            date_candidate=date(2026, 4, 20),
            minute_candidate=1410,
            duration_minute=60,
        )
        self.assertIsNone(result)


if __name__ == "__main__":
    unittest.main()
