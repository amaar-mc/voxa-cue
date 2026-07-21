"""Safe model export with a traceable model card."""

from __future__ import annotations

import hashlib
import json
from collections.abc import Sequence
from datetime import UTC, datetime
from importlib.metadata import version
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd
import skops.io as skops_io
from sklearn.base import BaseEstimator

from .features import (
    PROMPT_WINDOW_MAX_END_DELAY_MS,
    PROMPT_WINDOW_MIN_END_DELAY_MS,
    WindowConfig,
)

MINIMUM_MACRO_F1_UPLIFT = 0.05
DUMMY_MODEL_NAME = "dummy_prior"


def dataset_sha256(paths: Sequence[Path]) -> str:
    """Hash the ordered raw dataset bytes used for a training run."""

    digest = hashlib.sha256()
    for path in sorted(paths, key=lambda item: str(item)):
        digest.update(str(path.name).encode("utf-8"))
        digest.update(path.read_bytes())
    return digest.hexdigest()


def export_model_bundle(
    estimator: BaseEstimator,
    window_config: WindowConfig,
    output_directory: Path,
    model_name: str,
    feature_columns: Sequence[str],
    labels: Sequence[str],
    metrics: pd.DataFrame,
    dataset_hash: str,
    source_revision: str,
    source_dirty: bool,
    source_diff_sha256: str | None,
    execution_notebook_sha256: str,
    repository_notebook_sha256: str,
    rejection_threshold: float,
) -> tuple[Path, Path]:
    """Export a skops artifact and human-readable provenance metadata."""

    window_config.validate()
    if not 0 < rejection_threshold < 1:
        raise ValueError("rejection_threshold must be in (0, 1)")
    macro_f1_uplift = require_export_ready_model(metrics, model_name)
    _validate_source_provenance(source_revision, source_dirty, source_diff_sha256)
    if not _is_sha256(execution_notebook_sha256):
        raise ValueError("execution_notebook_sha256 must be a 64-character SHA-256.")
    if not _is_sha256(repository_notebook_sha256):
        raise ValueError("repository_notebook_sha256 must be a 64-character SHA-256.")
    selected_metrics = metrics.loc[metrics["model"] == model_name]
    dummy_metrics = metrics.loc[metrics["model"] == DUMMY_MODEL_NAME]
    if len(selected_metrics) != 1:
        raise ValueError("Metrics must contain exactly one row for the selected model.")
    if len(dummy_metrics) != 1:
        raise ValueError("Metrics must contain exactly one row for the dummy model.")
    selected_score = float(selected_metrics.iloc[0]["window_macro_f1"])
    dummy_score = float(dummy_metrics.iloc[0]["window_macro_f1"])
    candidate_metrics = [
        {str(key): value for key, value in record.items()}
        for record in metrics.to_dict(orient="records")
    ]
    output_directory.mkdir(parents=True, exist_ok=True)
    model_path = output_directory / "voxa_gesture_classifier_v1.skops"
    card_path = output_directory / "model-card.json"
    skops_io.dump(estimator, model_path)
    card: dict[str, Any] = {
        "artifact_version": 1,
        "created_at_utc": datetime.now(UTC).isoformat(),
        "purpose": "Experimental three-class wrist-motion classifier",
        "model_name": model_name,
        "labels": list(labels),
        "feature_columns": list(feature_columns),
        "preprocessing": {
            "sample_rate_hz": window_config.sample_rate_hz,
            "window_seconds": window_config.window_seconds,
            "hop_seconds": window_config.hop_seconds,
            "prompt_window_min_end_delay_ms": PROMPT_WINDOW_MIN_END_DELAY_MS,
            "prompt_window_max_end_delay_ms": PROMPT_WINDOW_MAX_END_DELAY_MS,
        },
        "rejection_threshold": rejection_threshold,
        "dataset_sha256": dataset_hash,
        "source_revision": source_revision,
        "source_dirty": source_dirty,
        "source_diff_sha256": source_diff_sha256,
        "execution_notebook_sha256": execution_notebook_sha256,
        "repository_notebook_sha256": repository_notebook_sha256,
        "execution_notebook_matches_repository": (
            execution_notebook_sha256 == repository_notebook_sha256
        ),
        "metrics": selected_metrics.iloc[0].to_dict(),
        "candidate_metrics": candidate_metrics,
        "export_gate": {
            "metric": "window_macro_f1",
            "minimum_exclusive_uplift": MINIMUM_MACRO_F1_UPLIFT,
            "selected_score": selected_score,
            "dummy_score": dummy_score,
            "measured_uplift": macro_f1_uplift,
        },
        "dependencies": {
            "numpy": version("numpy"),
            "pandas": version("pandas"),
            "scikit-learn": version("scikit-learn"),
            "skops": version("skops"),
        },
        "limitations": [
            "A single wrist IMU measures motion, not semantic intent.",
            "Do not make cross-person claims without held-out participant evaluation.",
            "Tune rejection and event smoothing on untouched validation sessions.",
        ],
    }
    card_path.write_text(json.dumps(card, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return model_path, card_path


def require_export_ready_model(metrics: pd.DataFrame, selected_model_name: str) -> float:
    """Reject artifacts that do not demonstrate useful grouped development signal."""

    required_columns = {"model", "window_macro_f1"}
    missing_columns = sorted(required_columns - set(metrics.columns))
    if missing_columns:
        raise ValueError(f"Metrics are missing required columns: {', '.join(missing_columns)}.")
    if selected_model_name == DUMMY_MODEL_NAME:
        raise ValueError("The dummy baseline cannot be exported as a gesture classifier.")

    selected_rows = metrics.loc[metrics["model"] == selected_model_name, "window_macro_f1"]
    dummy_rows = metrics.loc[metrics["model"] == DUMMY_MODEL_NAME, "window_macro_f1"]
    if len(selected_rows) != 1 or len(dummy_rows) != 1:
        raise ValueError("Metrics must contain exactly one selected-model and one dummy row.")

    selected_score = float(selected_rows.iloc[0])
    dummy_score = float(dummy_rows.iloc[0])
    if not np.isfinite(selected_score) or not np.isfinite(dummy_score):
        raise ValueError("Export metrics must be finite.")
    uplift = selected_score - dummy_score
    below_or_at_threshold = uplift < MINIMUM_MACRO_F1_UPLIFT or np.isclose(
        uplift,
        MINIMUM_MACRO_F1_UPLIFT,
        rtol=0,
        atol=1e-12,
    )
    if below_or_at_threshold:
        raise ValueError(
            "Selected model must exceed dummy window macro F1 by more than "
            f"{MINIMUM_MACRO_F1_UPLIFT:.2f}; measured uplift was {uplift:.3f}."
        )
    return uplift


def _validate_source_provenance(
    source_revision: str,
    source_dirty: bool,
    source_diff_sha256: str | None,
) -> None:
    if not source_revision.strip():
        raise ValueError("source_revision must be non-empty.")
    if source_dirty:
        if source_diff_sha256 is None or not _is_sha256(source_diff_sha256):
            raise ValueError("Dirty source requires a 64-character source_diff_sha256.")
    elif source_diff_sha256 is not None:
        raise ValueError("Clean source must use source_diff_sha256=None.")


def _is_sha256(value: str) -> bool:
    return len(value) == 64 and all(character in "0123456789abcdef" for character in value)
