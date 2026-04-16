from __future__ import annotations

import argparse
import json
from dataclasses import is_dataclass, fields
from datetime import date
from enum import Enum
from pathlib import Path
from typing import Any, Dict, List

from .contracts import ContractValidationError, load_config, load_dataset
from .replay import replay_dataset
from .report import build_aggregate_summary, build_compact_report, build_session_breakdown
from .scoring import aggregate_scores, score_session
from .search import run_random_search


def main(argv: List[str] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.command == "validate":
        dataset = load_dataset(args.data)
        payload = {
            "ok": True,
            "sessionCount": len(dataset.sessions),
            "splits": sorted({session.split for session in dataset.sessions}),
        }
        print(json.dumps(payload, ensure_ascii=False))
        return 0

    if args.command == "replay":
        dataset = load_dataset(args.data)
        config = load_config(args.config)
        results = replay_dataset(dataset, config)
        if args.session:
            result = results[args.session]
            print(json.dumps(_to_jsonable(result), ensure_ascii=False))
            return 0
        print(json.dumps({key: _to_jsonable(value) for key, value in results.items()}, ensure_ascii=False))
        return 0

    if args.command == "score":
        dataset = load_dataset(args.data)
        config = load_config(args.config)
        results = replay_dataset(dataset, config)
        session_scores = [
            score_session(
                dataset.sessions_by_id[session.session_id],
                results[session.session_id],
                dataset.expected_by_session_id[session.session_id],
            )
            for session in dataset.sessions
        ]
        aggregate = aggregate_scores(session_scores)
        payload = {
            "summary": build_aggregate_summary(aggregate),
            "worstSessions": build_compact_report(aggregate)["worstSessions"],
        }
        print(json.dumps(payload, ensure_ascii=False))
        return 0

    if args.command == "tune":
        payload = run_random_search(
            data_dir=args.data,
            baseline_path=args.config,
            search_space_path=args.search_space,
            budget=args.budget,
            workers=args.workers,
            seed=args.seed,
            output_path=args.output,
        )
        print(json.dumps(payload, ensure_ascii=False))
        return 0

    raise AssertionError("unreachable")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="draglab")
    subparsers = parser.add_subparsers(dest="command", required=True)

    validate = subparsers.add_parser("validate")
    validate.add_argument("--data", required=True)

    replay = subparsers.add_parser("replay")
    replay.add_argument("--data", required=True)
    replay.add_argument("--config", required=True)
    replay.add_argument("--session")

    score = subparsers.add_parser("score")
    score.add_argument("--data", required=True)
    score.add_argument("--config", required=True)

    tune = subparsers.add_parser("tune")
    tune.add_argument("--data", required=True)
    tune.add_argument("--config", required=True)
    tune.add_argument("--search-space", required=True)
    tune.add_argument("--budget", required=True, type=int)
    tune.add_argument("--workers", default=1, type=int)
    tune.add_argument("--seed", default=7, type=int)
    tune.add_argument("--output")

    return parser


def _to_jsonable(value: Any) -> Any:
    if is_dataclass(value):
        return {
            field.name: _to_jsonable(getattr(value, field.name))
            for field in fields(value)
        }
    if isinstance(value, Enum):
        return value.value
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, tuple):
        return [_to_jsonable(item) for item in value]
    if isinstance(value, list):
        return [_to_jsonable(item) for item in value]
    if isinstance(value, dict):
        return {key: _to_jsonable(item) for key, item in value.items()}
    return value


if __name__ == "__main__":
    raise SystemExit(main())
