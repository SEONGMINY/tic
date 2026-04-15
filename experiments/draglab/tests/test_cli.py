from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data"
BASELINE_PATH = ROOT / "configs" / "baseline.json"
SEARCH_SPACE_PATH = ROOT / "configs" / "search_space.json"


class CliTest(unittest.TestCase):
    def test_validate_command(self) -> None:
        payload = self._run_cli(
            "validate",
            "--data",
            str(DATA_DIR),
        )
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["sessionCount"], 6)

    def test_replay_command(self) -> None:
        payload = self._run_cli(
            "replay",
            "--data",
            str(DATA_DIR),
            "--config",
            str(BASELINE_PATH),
            "--session",
            "s002",
        )
        self.assertEqual(payload["session_id"], "s002")
        self.assertGreater(len(payload["trace"]), 0)

    def test_score_command(self) -> None:
        payload = self._run_cli(
            "score",
            "--data",
            str(DATA_DIR),
            "--config",
            str(BASELINE_PATH),
        )
        self.assertIn("summary", payload)
        self.assertIn("combinedTotal", payload["summary"])

    def test_tune_command_writes_output(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            output_path = Path(tmp_dir) / "tune.jsonl"
            payload = self._run_cli(
                "tune",
                "--data",
                str(DATA_DIR),
                "--config",
                str(BASELINE_PATH),
                "--search-space",
                str(SEARCH_SPACE_PATH),
                "--budget",
                "4",
                "--workers",
                "2",
                "--seed",
                "7",
                "--output",
                str(output_path),
            )
            self.assertTrue(output_path.exists())
            self.assertEqual(payload["candidateCount"], 4)

    def _run_cli(self, *args: str):
        env = dict(os.environ)
        env["PYTHONPATH"] = str(ROOT / "src")
        command = [sys.executable, "-m", "draglab.cli", *args]
        result = subprocess.run(
            command,
            check=True,
            capture_output=True,
            text=True,
            env=env,
            cwd=str(ROOT.parent.parent),
        )
        return json.loads(result.stdout)


if __name__ == "__main__":
    unittest.main()
