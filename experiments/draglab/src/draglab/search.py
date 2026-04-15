from __future__ import annotations

import json
import random
from dataclasses import asdict
from pathlib import Path
from typing import Dict, List, Optional

from .contracts import load_config, load_search_space
from .parallel import evaluate_candidates


def run_random_search(
    data_dir: str,
    baseline_path: str,
    search_space_path: str,
    budget: int,
    workers: int,
    seed: int,
    output_path: Optional[str] = None,
) -> Dict[str, object]:
    baseline = load_config(baseline_path)
    search_space = load_search_space(search_space_path)
    baseline_doc = config_to_doc(baseline)
    rng = random.Random(seed)

    candidate_docs: List[Dict[str, object]] = [baseline_doc]
    for _ in range(max(0, budget - 1)):
        candidate_docs.append(sample_candidate_doc(baseline_doc, search_space.search_space, rng))

    evaluated = evaluate_candidates(data_dir, candidate_docs, workers=workers)
    ranked = sorted(
        evaluated,
        key=lambda item: (-float(item["summary"]["combinedTotal"]), int(item["index"])),
    )
    resolved_output = Path(output_path) if output_path else Path(data_dir).parent / "runs" / "tune-results.jsonl"
    resolved_output.parent.mkdir(parents=True, exist_ok=True)
    with resolved_output.open("w", encoding="utf-8") as handle:
        for item in ranked:
            handle.write(json.dumps(item, ensure_ascii=False) + "\n")
    return {
        "outputPath": str(resolved_output),
        "topCandidates": ranked[: min(3, len(ranked))],
        "candidateCount": len(ranked),
        "seed": seed,
        "workers": workers,
    }


def config_to_doc(config) -> Dict[str, object]:
    return {
        "schemaVersion": config.schema_version,
        "longPressMinMs": config.long_press_min_ms,
        "pressSlopPt": config.press_slop_pt,
        "dragStartMinDistancePt": config.drag_start_min_distance_pt,
        "hoverActivationMs": config.hover_activation_ms,
        "hoverExitMs": config.hover_exit_ms,
        "cellHitInsetPt": config.cell_hit_inset_pt,
        "cellHysteresisPt": config.cell_hysteresis_pt,
        "timelineDropInsetPt": config.timeline_drop_inset_pt,
        "minuteSnapStep": config.minute_snap_step,
        "minimumDurationMinute": config.minimum_duration_minute,
        "restoreAnimationMs": config.restore_animation_ms,
        "reanchorBlendMs": config.reanchor_blend_ms,
        "invalidDropPolicy": config.invalid_drop_policy,
    }


def sample_candidate_doc(
    baseline_doc: Dict[str, object],
    search_space: Dict[str, tuple],
    rng: random.Random,
) -> Dict[str, object]:
    candidate = dict(baseline_doc)
    for key, values in search_space.items():
        candidate[key] = rng.choice(list(values))
    return candidate
