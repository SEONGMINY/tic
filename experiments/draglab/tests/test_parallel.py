from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from draglab.search import run_random_search


ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data"
BASELINE_PATH = ROOT / "configs" / "baseline.json"
SEARCH_SPACE_PATH = ROOT / "configs" / "search_space.json"


class ParallelSearchTest(unittest.TestCase):
    def test_same_seed_is_reproducible(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            left = run_random_search(
                data_dir=str(DATA_DIR),
                baseline_path=str(BASELINE_PATH),
                search_space_path=str(SEARCH_SPACE_PATH),
                budget=4,
                workers=2,
                seed=7,
                output_path=str(Path(tmp_dir) / "left.jsonl"),
            )
            right = run_random_search(
                data_dir=str(DATA_DIR),
                baseline_path=str(BASELINE_PATH),
                search_space_path=str(SEARCH_SPACE_PATH),
                budget=4,
                workers=2,
                seed=7,
                output_path=str(Path(tmp_dir) / "right.jsonl"),
            )
            self.assertEqual(left["topCandidates"], right["topCandidates"])

    def test_worker_count_does_not_change_top_score(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            serial = run_random_search(
                data_dir=str(DATA_DIR),
                baseline_path=str(BASELINE_PATH),
                search_space_path=str(SEARCH_SPACE_PATH),
                budget=4,
                workers=1,
                seed=11,
                output_path=str(Path(tmp_dir) / "serial.jsonl"),
            )
            parallel = run_random_search(
                data_dir=str(DATA_DIR),
                baseline_path=str(BASELINE_PATH),
                search_space_path=str(SEARCH_SPACE_PATH),
                budget=4,
                workers=2,
                seed=11,
                output_path=str(Path(tmp_dir) / "parallel.jsonl"),
            )
            self.assertEqual(
                serial["topCandidates"][0]["summary"]["combinedTotal"],
                parallel["topCandidates"][0]["summary"]["combinedTotal"],
            )


if __name__ == "__main__":
    unittest.main()
