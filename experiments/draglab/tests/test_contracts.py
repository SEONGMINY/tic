from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from draglab.contracts import ContractValidationError, load_dataset


ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data"


class ContractsTest(unittest.TestCase):
    def test_valid_fixture_loads(self) -> None:
        dataset = load_dataset(DATA_DIR)
        self.assertEqual(dataset.schema_version, 1)
        self.assertEqual(len(dataset.sessions), 6)
        self.assertIn("s002", dataset.sessions_by_id)
        self.assertEqual(dataset.expected_by_session_id["s003"].expected_outcome.value, "none")

    def test_missing_required_field_fails(self) -> None:
        sessions_doc, events_doc, expected_doc = self._load_docs()
        del sessions_doc["sessions"][0]["device"]
        with self.assertRaises(ContractValidationError) as ctx:
            self._load_mutated_dataset(sessions_doc, events_doc, expected_doc)
        self.assertIn("device", str(ctx.exception))

    def test_duplicate_session_id_fails(self) -> None:
        sessions_doc, events_doc, expected_doc = self._load_docs()
        sessions_doc["sessions"][1]["sessionId"] = sessions_doc["sessions"][0]["sessionId"]
        with self.assertRaises(ContractValidationError) as ctx:
            self._load_mutated_dataset(sessions_doc, events_doc, expected_doc)
        self.assertIn("duplicate sessionId", str(ctx.exception))

    def test_missing_expected_reference_fails(self) -> None:
        sessions_doc, events_doc, expected_doc = self._load_docs()
        expected_doc["sessions"] = expected_doc["sessions"][:-1]
        with self.assertRaises(ContractValidationError) as ctx:
            self._load_mutated_dataset(sessions_doc, events_doc, expected_doc)
        self.assertIn("expected.json missing sessions", str(ctx.exception))

    def test_negative_fixture_is_schema_valid(self) -> None:
        dataset = load_dataset(DATA_DIR)
        tags = dataset.sessions_by_id["s004"].scenario_tags
        self.assertIn("negative", tags)
        self.assertFalse(dataset.expected_by_session_id["s004"].should_accept_drop)

    def _load_docs(self) -> tuple[dict, dict, dict]:
        with (DATA_DIR / "sessions.json").open("r", encoding="utf-8") as handle:
            sessions_doc = json.load(handle)
        with (DATA_DIR / "events.json").open("r", encoding="utf-8") as handle:
            events_doc = json.load(handle)
        with (DATA_DIR / "expected.json").open("r", encoding="utf-8") as handle:
            expected_doc = json.load(handle)
        return sessions_doc, events_doc, expected_doc

    def _load_mutated_dataset(self, sessions_doc: dict, events_doc: dict, expected_doc: dict):
        with tempfile.TemporaryDirectory() as tmp_dir:
            root = Path(tmp_dir)
            (root / "sessions.json").write_text(
                json.dumps(sessions_doc, ensure_ascii=False),
                encoding="utf-8",
            )
            (root / "events.json").write_text(
                json.dumps(events_doc, ensure_ascii=False),
                encoding="utf-8",
            )
            (root / "expected.json").write_text(
                json.dumps(expected_doc, ensure_ascii=False),
                encoding="utf-8",
            )
            return load_dataset(root)


if __name__ == "__main__":
    unittest.main()
