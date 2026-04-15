from __future__ import annotations

from typing import Dict, List, Sequence

from .models import AggregateScore, SessionResult, SessionScore


def worst_sessions(scores: Sequence[SessionScore], limit: int = 3) -> List[SessionScore]:
    return sorted(scores, key=lambda score: score.combined_total)[:limit]


def build_session_breakdown(score: SessionScore, result: SessionResult) -> Dict[str, object]:
    return {
        "sessionId": score.session_id,
        "dragStarted": result.drag_started,
        "outcome": result.outcome.value,
        "dropAccepted": result.drop_accepted,
        "correctness": round(score.correctness_total, 4),
        "smoothness": round(score.smoothness_total, 4),
        "combined": round(score.combined_total, 4),
        "metrics": {
            "overlayAnchorErrorPt": round(score.smoothness_metrics.overlay_anchor_error_pt, 3),
            "frameJumpPtP95": round(score.smoothness_metrics.frame_jump_pt_p95, 3),
            "sizeJumpRatioP95": round(score.smoothness_metrics.size_jump_ratio_p95, 3),
            "hoverChurnPerSec": round(score.smoothness_metrics.hover_churn_per_sec, 3),
            "restoreDurationMs": round(score.smoothness_metrics.restore_duration_ms, 3),
            "restoreOvershootPt": round(score.smoothness_metrics.restore_overshoot_pt, 3),
            "scopeTransitionJumpPt": round(score.smoothness_metrics.scope_transition_jump_pt, 3),
        },
    }


def build_aggregate_summary(aggregate: AggregateScore) -> Dict[str, object]:
    return {
        "sessionCount": len(aggregate.session_scores),
        "correctnessTotal": round(aggregate.correctness_total, 4),
        "smoothnessTotal": round(aggregate.smoothness_total, 4),
        "combinedTotal": round(aggregate.combined_total, 4),
    }


def build_compact_report(aggregate: AggregateScore) -> Dict[str, object]:
    return {
        "summary": build_aggregate_summary(aggregate),
        "worstSessions": [
            {
                "sessionId": score.session_id,
                "combined": round(score.combined_total, 4),
                "correctness": round(score.correctness_total, 4),
                "smoothness": round(score.smoothness_total, 4),
            }
            for score in worst_sessions(aggregate.session_scores)
        ],
    }
