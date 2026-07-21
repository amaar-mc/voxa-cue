"""Behavior tests for trial-isolated causal feature extraction."""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from voxa_gesture.features import (
    WINDOW_METADATA_COLUMNS,
    WindowConfig,
    extract_window_features,
    model_feature_columns,
)
from voxa_gesture.schema import validate_dataset


def _window_config() -> WindowConfig:
    return WindowConfig(
        sample_rate_hz=50,
        window_seconds=2.0,
        hop_seconds=0.5,
    )


def test_windows_never_cross_trial_boundaries(synthetic_frame: pd.DataFrame) -> None:
    normalized, report = validate_dataset(synthetic_frame)
    assert report.is_trainable

    features = extract_window_features(normalized, _window_config())

    source_keys = set(
        normalized[["subject_id", "session_id", "trial_id"]]
        .drop_duplicates()
        .itertuples(index=False, name=None)
    )
    feature_keys = set(
        features[["subject_id", "session_id", "trial_id"]].itertuples(
            index=False,
            name=None,
        )
    )
    assert feature_keys == source_keys
    windows_per_trial = features.groupby(["behavior", "trial_id"]).size()
    assert windows_per_trial.loc["rest"].eq(2).all()
    assert windows_per_trial.loc["fidget"].eq(2).all()
    assert windows_per_trial.loc["intentional_gesture"].eq(2).all()
    assert features.groupby("trial_id")["behavior"].nunique().eq(1).all()
    window_indices = features.groupby("trial_id")["window_index"].apply(list)
    assert window_indices.map(lambda indices: indices == [0, 1]).all()
    assert (features["window_end_ms"] - features["window_start_ms"] <= 2_000).all()


def test_all_behavior_windows_follow_the_recorded_prompt_event(
    synthetic_frame: pd.DataFrame,
) -> None:
    shifted_prompt = synthetic_frame.copy()
    shifted_prompt["prompt_event_ms"] = 2_000
    normalized, report = validate_dataset(shifted_prompt)
    assert report.is_trainable

    features = extract_window_features(normalized, _window_config())
    window_indices = features.groupby("trial_id")["window_index"].apply(list)
    assert window_indices.map(lambda indices: indices == [1, 2]).all()
    end_delay = features["window_end_ms"] - 2_000
    assert end_delay.between(350, 1_100, inclusive="both").all()


def test_features_are_finite_and_model_input_excludes_metadata(
    synthetic_frame: pd.DataFrame,
) -> None:
    normalized, _ = validate_dataset(synthetic_frame)
    features = extract_window_features(normalized, _window_config())
    feature_columns = model_feature_columns(features)

    assert set(feature_columns).isdisjoint(WINDOW_METADATA_COLUMNS)
    assert {
        "subject_id",
        "session_id",
        "trial_id",
        "behavior",
        "subtype",
        "wrist",
        "orientation",
        "participant_group",
        "session_group",
        "window_index",
        "window_start_ms",
        "window_end_ms",
    }.isdisjoint(feature_columns)
    assert np.isfinite(features[feature_columns].to_numpy(dtype=float)).all()


def test_periodic_fidget_has_stronger_motion_than_rest(
    synthetic_frame: pd.DataFrame,
) -> None:
    normalized, _ = validate_dataset(synthetic_frame)
    features = extract_window_features(normalized, _window_config())
    grouped = features.groupby("behavior")

    assert grouped["gyro_magnitude_energy"].median()["fidget"] > (
        grouped["gyro_magnitude_energy"].median()["rest"] * 20
    )
    assert (
        grouped["active_fraction"].median()["fidget"] > grouped["active_fraction"].median()["rest"]
    )


def test_incomplete_trial_cannot_borrow_samples_from_next_trial(
    synthetic_frame: pd.DataFrame,
) -> None:
    first_two_trials = synthetic_frame[
        synthetic_frame["trial_id"].isin(synthetic_frame["trial_id"].unique()[:2])
    ].copy()
    short_trial_id = str(first_two_trials["trial_id"].iloc[0])
    short_indices = first_two_trials.index[first_two_trials["trial_id"] == short_trial_id]
    shortened = first_two_trials.drop(index=short_indices[75:])

    with pytest.raises(ValueError, match="produced no prompt-aligned feature windows"):
        extract_window_features(shortened, _window_config())


@pytest.mark.parametrize(
    "config",
    [
        WindowConfig(0, 2.0, 0.5),
        WindowConfig(50, 0.0, 0.5),
        WindowConfig(50, 2.0, 2.5),
    ],
)
def test_invalid_window_configuration_is_rejected(config: WindowConfig) -> None:
    with pytest.raises(ValueError):
        config.validate()
