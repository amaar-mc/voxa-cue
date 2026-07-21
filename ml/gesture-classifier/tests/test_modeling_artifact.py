"""Behavior tests for leakage-safe evaluation and traceable model artifacts."""

from __future__ import annotations

import json
from pathlib import Path

import pandas as pd
import pandas.testing as pdt
import pytest
import skops.io as skops_io
from sklearn.dummy import DummyClassifier

from voxa_gesture.artifact import (
    dataset_sha256,
    export_model_bundle,
    require_export_ready_model,
)
from voxa_gesture.features import (
    PROMPT_WINDOW_MAX_END_DELAY_MS,
    PROMPT_WINDOW_MIN_END_DELAY_MS,
    WindowConfig,
    extract_window_features,
)
from voxa_gesture.modeling import evaluate_grouped_baselines, fit_selected_model
from voxa_gesture.schema import validate_dataset


def _features(frame: pd.DataFrame) -> pd.DataFrame:
    normalized, report = validate_dataset(frame)
    assert report.is_trainable
    return extract_window_features(
        normalized,
        _window_config(),
    )


def _window_config() -> WindowConfig:
    return WindowConfig(
        sample_rate_hz=50,
        window_seconds=2.0,
        hop_seconds=0.5,
    )


def test_grouped_evaluation_is_deterministic_and_beats_dummy(
    synthetic_frame: pd.DataFrame,
) -> None:
    features = _features(synthetic_frame)

    first = evaluate_grouped_baselines(
        features,
        target_column="behavior",
        group_column="participant_group",
        random_state=41,
    )
    second = evaluate_grouped_baselines(
        features,
        target_column="behavior",
        group_column="participant_group",
        random_state=41,
    )

    pdt.assert_frame_equal(first.summary, second.summary)
    pdt.assert_frame_equal(first.window_predictions, second.window_predictions)
    assert first.feature_columns == second.feature_columns
    assert first.labels == ("fidget", "intentional_gesture", "rest")
    assert first.selected_model_name != "dummy_prior"

    scores = first.summary.set_index("model")["window_macro_f1"]
    assert scores[first.selected_model_name] >= scores["dummy_prior"] + 0.30
    assert first.window_predictions.groupby("trial_id")["fold"].nunique().eq(1).all()
    assert first.window_predictions.groupby("subject_id")["fold"].nunique().eq(1).all()
    assert first.window_predictions["fold"].ge(0).all()


def test_grouped_evaluation_rejects_insufficient_groups(
    synthetic_frame: pd.DataFrame,
) -> None:
    one_subject = synthetic_frame[synthetic_frame["subject_id"] == "SYN_P01"]
    features = _features(one_subject)

    try:
        evaluate_grouped_baselines(
            features,
            target_column="behavior",
            group_column="participant_group",
            random_state=41,
        )
    except ValueError as error:
        assert "at least three" in str(error)
    else:
        raise AssertionError("One participant must not pass grouped evaluation.")


def test_grouped_evaluation_requires_complete_behavior_set(
    synthetic_frame: pd.DataFrame,
) -> None:
    features = _features(synthetic_frame)
    without_rest = features[features["behavior"] != "rest"]

    with pytest.raises(ValueError, match="complete v1 label set"):
        evaluate_grouped_baselines(
            without_rest,
            target_column="behavior",
            group_column="participant_group",
            random_state=41,
        )


def test_model_bundle_round_trips_with_provenance(
    synthetic_frame: pd.DataFrame,
    tmp_path: Path,
) -> None:
    features = _features(synthetic_frame)
    evaluation = evaluate_grouped_baselines(
        features,
        target_column="behavior",
        group_column="participant_group",
        random_state=41,
    )
    estimator = fit_selected_model(
        features,
        target_column="behavior",
        model_name=evaluation.selected_model_name,
        random_state=41,
    )
    data_path = tmp_path / "synthetic.csv"
    synthetic_frame.to_csv(data_path, index=False)
    data_hash = dataset_sha256([data_path])

    model_path, card_path = export_model_bundle(
        estimator=estimator,
        window_config=_window_config(),
        output_directory=tmp_path / "artifacts",
        model_name=evaluation.selected_model_name,
        feature_columns=evaluation.feature_columns,
        labels=evaluation.labels,
        metrics=evaluation.summary,
        dataset_hash=data_hash,
        source_revision="test-revision",
        source_dirty=False,
        source_diff_sha256=None,
        execution_notebook_sha256="c" * 64,
        repository_notebook_sha256="c" * 64,
        rejection_threshold=0.65,
    )

    assert model_path.is_file()
    assert card_path.is_file()
    card = json.loads(card_path.read_text(encoding="utf-8"))
    assert card["artifact_version"] == 1
    assert card["model_name"] == evaluation.selected_model_name
    assert card["labels"] == list(evaluation.labels)
    assert card["feature_columns"] == list(evaluation.feature_columns)
    assert card["preprocessing"] == {
        "sample_rate_hz": 50,
        "window_seconds": 2.0,
        "hop_seconds": 0.5,
        "prompt_window_min_end_delay_ms": PROMPT_WINDOW_MIN_END_DELAY_MS,
        "prompt_window_max_end_delay_ms": PROMPT_WINDOW_MAX_END_DELAY_MS,
    }
    assert card["dataset_sha256"] == data_hash
    assert card["source_revision"] == "test-revision"
    assert card["source_dirty"] is False
    assert card["source_diff_sha256"] is None
    assert card["execution_notebook_sha256"] == "c" * 64
    assert card["repository_notebook_sha256"] == "c" * 64
    assert card["execution_notebook_matches_repository"] is True
    assert card["rejection_threshold"] == 0.65
    assert card["metrics"]["model"] == evaluation.selected_model_name
    assert {row["model"] for row in card["candidate_metrics"]} == {
        "dummy_prior",
        "logistic_regression",
        "random_forest",
    }
    selected_score = float(
        evaluation.summary.loc[
            evaluation.summary["model"] == evaluation.selected_model_name,
            "window_macro_f1",
        ].iloc[0]
    )
    dummy_score = float(
        evaluation.summary.loc[
            evaluation.summary["model"] == "dummy_prior",
            "window_macro_f1",
        ].iloc[0]
    )
    assert card["export_gate"] == {
        "metric": "window_macro_f1",
        "minimum_exclusive_uplift": 0.05,
        "selected_score": pytest.approx(selected_score),
        "dummy_score": pytest.approx(dummy_score),
        "measured_uplift": pytest.approx(selected_score - dummy_score),
    }

    untrusted_types = skops_io.get_untrusted_types(file=model_path)
    loaded = skops_io.load(model_path, trusted=untrusted_types)
    expected = estimator.predict(features[list(evaluation.feature_columns)])
    actual = loaded.predict(features[list(evaluation.feature_columns)])
    assert actual.tolist() == expected.tolist()


def test_dataset_hash_is_order_independent_but_content_sensitive(tmp_path: Path) -> None:
    first = tmp_path / "a.csv"
    second = tmp_path / "b.csv"
    first.write_text("x\n1\n", encoding="utf-8")
    second.write_text("x\n2\n", encoding="utf-8")

    original = dataset_sha256([first, second])

    assert dataset_sha256([second, first]) == original
    second.write_text("x\n3\n", encoding="utf-8")
    assert dataset_sha256([first, second]) != original


def test_dirty_model_bundle_records_diff_provenance(tmp_path: Path) -> None:
    estimator = DummyClassifier(strategy="most_frequent")
    estimator.fit([[0.0], [1.0]], ["rest", "fidget"])
    metrics = pd.DataFrame(
        [
            {"model": "random_forest", "window_macro_f1": 0.70},
            {"model": "dummy_prior", "window_macro_f1": 0.30},
        ]
    )
    diff_hash = "a" * 64

    _, card_path = export_model_bundle(
        estimator=estimator,
        window_config=_window_config(),
        output_directory=tmp_path,
        model_name="random_forest",
        feature_columns=["x"],
        labels=["fidget", "intentional_gesture", "rest"],
        metrics=metrics,
        dataset_hash="b" * 64,
        source_revision="test-revision",
        source_dirty=True,
        source_diff_sha256=diff_hash,
        execution_notebook_sha256="c" * 64,
        repository_notebook_sha256="d" * 64,
        rejection_threshold=0.65,
    )

    card = json.loads(card_path.read_text(encoding="utf-8"))
    assert card["source_dirty"] is True
    assert card["source_diff_sha256"] == diff_hash
    assert card["execution_notebook_matches_repository"] is False


@pytest.mark.parametrize(
    ("selected_model", "selected_score", "dummy_score", "expected_message"),
    [
        ("dummy_prior", 0.80, 0.30, "dummy baseline"),
        ("random_forest", 0.35, 0.30, "more than 0.05"),
        ("random_forest", 0.349, 0.30, "more than 0.05"),
    ],
)
def test_export_readiness_rejects_dummy_or_insufficient_uplift(
    selected_model: str,
    selected_score: float,
    dummy_score: float,
    expected_message: str,
) -> None:
    metrics = pd.DataFrame(
        [
            {"model": selected_model, "window_macro_f1": selected_score},
            {"model": "dummy_prior", "window_macro_f1": dummy_score},
        ]
    ).drop_duplicates(subset="model", keep="first")

    with pytest.raises(ValueError, match=expected_message):
        require_export_ready_model(metrics, selected_model)


def test_export_readiness_returns_macro_f1_uplift() -> None:
    metrics = pd.DataFrame(
        [
            {"model": "random_forest", "window_macro_f1": 0.71},
            {"model": "dummy_prior", "window_macro_f1": 0.30},
        ]
    )

    uplift = require_export_ready_model(metrics, "random_forest")

    assert uplift == pytest.approx(0.41)


@pytest.mark.parametrize(
    ("source_dirty", "source_diff_sha256", "expected_message"),
    [
        (True, None, "Dirty source"),
        (True, "not-a-hash", "Dirty source"),
        (False, "a" * 64, "Clean source"),
    ],
)
def test_model_bundle_rejects_inconsistent_source_provenance(
    tmp_path: Path,
    source_dirty: bool,
    source_diff_sha256: str | None,
    expected_message: str,
) -> None:
    estimator = DummyClassifier(strategy="most_frequent")
    estimator.fit([[0.0], [1.0]], ["rest", "fidget"])
    metrics = pd.DataFrame(
        [
            {"model": "random_forest", "window_macro_f1": 0.70},
            {"model": "dummy_prior", "window_macro_f1": 0.30},
        ]
    )

    with pytest.raises(ValueError, match=expected_message):
        export_model_bundle(
            estimator=estimator,
            window_config=_window_config(),
            output_directory=tmp_path,
            model_name="random_forest",
            feature_columns=["x"],
            labels=["fidget", "intentional_gesture", "rest"],
            metrics=metrics,
            dataset_hash="b" * 64,
            source_revision="test-revision",
            source_dirty=source_dirty,
            source_diff_sha256=source_diff_sha256,
            execution_notebook_sha256="c" * 64,
            repository_notebook_sha256="c" * 64,
            rejection_threshold=0.65,
        )
    assert not (tmp_path / "voxa_gesture_classifier_v1.skops").exists()
