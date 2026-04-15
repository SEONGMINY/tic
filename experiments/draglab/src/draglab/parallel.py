from __future__ import annotations

from concurrent.futures import ProcessPoolExecutor
from typing import Dict, List, Sequence, Tuple

from .contracts import config_from_dict, load_dataset
from .report import build_aggregate_summary
from .replay import replay_dataset
from .scoring import aggregate_scores, score_session


def evaluate_candidates(
    data_dir: str,
    candidate_docs: Sequence[Dict[str, object]],
    workers: int = 1,
) -> List[Dict[str, object]]:
    indexed_docs = list(enumerate(candidate_docs))
    if workers <= 1:
        evaluated = [_evaluate_candidate(index, data_dir, candidate) for index, candidate in indexed_docs]
    else:
        with ProcessPoolExecutor(max_workers=workers) as pool:
            futures = [
                pool.submit(_evaluate_candidate, index, data_dir, candidate)
                for index, candidate in indexed_docs
            ]
            evaluated = [future.result() for future in futures]
    return sorted(evaluated, key=lambda item: item["index"])


def _evaluate_candidate(index: int, data_dir: str, candidate_doc: Dict[str, object]) -> Dict[str, object]:
    dataset = load_dataset(data_dir)
    config = config_from_dict(candidate_doc)
    replay_results = replay_dataset(dataset, config)
    session_scores = [
        score_session(
            dataset.sessions_by_id[session.session_id],
            replay_results[session.session_id],
            dataset.expected_by_session_id[session.session_id],
        )
        for session in dataset.sessions
    ]
    aggregate = aggregate_scores(session_scores)
    return {
        "index": index,
        "config": candidate_doc,
        "summary": build_aggregate_summary(aggregate),
    }
