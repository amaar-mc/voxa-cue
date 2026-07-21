"""Grouped evaluation and conservative baseline selection."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import numpy as np
import pandas as pd
from sklearn.base import BaseEstimator, clone
from sklearn.dummy import DummyClassifier
from sklearn.ensemble import RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import balanced_accuracy_score, f1_score
from sklearn.model_selection import StratifiedGroupKFold
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

from .features import model_feature_columns
from .schema import ALLOWED_BEHAVIORS


@dataclass(frozen=True)
class EvaluationBundle:
    """Out-of-fold evidence plus the selected estimator definition."""

    summary: pd.DataFrame
    window_predictions: pd.DataFrame
    trial_predictions: pd.DataFrame
    selected_model_name: str
    feature_columns: tuple[str, ...]
    labels: tuple[str, ...]


def evaluate_grouped_baselines(
    features: pd.DataFrame,
    target_column: str,
    group_column: str,
    random_state: int,
) -> EvaluationBundle:
    """Compare dummy, linear, and random-forest models without group leakage."""

    if target_column not in features.columns:
        raise ValueError(f"Unknown target column: {target_column}")
    if group_column not in features.columns:
        raise ValueError(f"Unknown group column: {group_column}")

    feature_columns = model_feature_columns(features)
    x_values = features[feature_columns]
    y_values = features[target_column].astype(str)
    groups = features[group_column].astype(str)
    labels = tuple(sorted(y_values.unique()))
    if set(labels) != ALLOWED_BEHAVIORS:
        missing = sorted(ALLOWED_BEHAVIORS - set(labels))
        unexpected = sorted(set(labels) - ALLOWED_BEHAVIORS)
        details = []
        if missing:
            details.append(f"missing {', '.join(missing)}")
        if unexpected:
            details.append(f"unexpected {', '.join(unexpected)}")
        raise ValueError(
            f"Behavior target must contain the complete v1 label set: {'; '.join(details)}."
        )
    distinct_groups = groups.nunique()
    if distinct_groups < 3:
        raise ValueError(
            "Grouped evaluation requires at least three participant or session groups."
        )
    for label in labels:
        label_group_count = groups[y_values == label].nunique()
        if label_group_count < 2:
            raise ValueError(f"Label {label} appears in fewer than two evaluation groups.")

    n_splits = min(5, distinct_groups)
    splitter = StratifiedGroupKFold(
        n_splits=n_splits,
        shuffle=True,
        random_state=random_state,
    )
    models = candidate_models(random_state)
    summary_rows: list[dict[str, float | str]] = []
    all_window_predictions: list[pd.DataFrame] = []
    all_trial_predictions: list[pd.DataFrame] = []

    for model_name, estimator in models.items():
        predictions = np.full(len(features), "", dtype=object)
        confidence = np.zeros(len(features), dtype=float)
        fold_index = np.full(len(features), -1, dtype=int)
        for fold, (train_indices, test_indices) in enumerate(
            splitter.split(x_values, y_values, groups)
        ):
            fitted = clone(estimator)
            fitted.fit(x_values.iloc[train_indices], y_values.iloc[train_indices])
            predictions[test_indices] = fitted.predict(x_values.iloc[test_indices])
            if hasattr(fitted, "predict_proba"):
                probabilities = fitted.predict_proba(x_values.iloc[test_indices])
                confidence[test_indices] = np.max(probabilities, axis=1)
            else:
                confidence[test_indices] = 1
            fold_index[test_indices] = fold

        if np.any(fold_index < 0):
            raise RuntimeError(f"Grouped evaluation left windows unassigned for {model_name}.")

        window_predictions = features[
            ["subject_id", "session_id", "trial_id", target_column]
        ].copy()
        window_predictions = window_predictions.rename(columns={target_column: "actual"})
        window_predictions["predicted"] = predictions.astype(str)
        window_predictions["confidence"] = confidence
        window_predictions["fold"] = fold_index
        window_predictions["model"] = model_name
        trial_predictions = _aggregate_trial_predictions(window_predictions, labels)

        window_metrics = _classification_metrics(
            window_predictions["actual"], window_predictions["predicted"], labels
        )
        trial_metrics = _classification_metrics(
            trial_predictions["actual"], trial_predictions["predicted"], labels
        )
        summary_rows.append(
            {
                "model": model_name,
                "window_macro_f1": window_metrics["macro_f1"],
                "window_balanced_accuracy": window_metrics["balanced_accuracy"],
                "trial_macro_f1": trial_metrics["macro_f1"],
                "trial_balanced_accuracy": trial_metrics["balanced_accuracy"],
                "gesture_as_fidget_rate": window_metrics["gesture_as_fidget_rate"],
                "fidget_as_gesture_rate": window_metrics["fidget_as_gesture_rate"],
            }
        )
        all_window_predictions.append(window_predictions)
        all_trial_predictions.append(trial_predictions)

    summary = pd.DataFrame(summary_rows).sort_values(
        ["window_macro_f1", "trial_macro_f1", "window_balanced_accuracy"],
        ascending=False,
        kind="stable",
    )
    selected_model_name = str(summary.iloc[0]["model"])
    return EvaluationBundle(
        summary=summary.reset_index(drop=True),
        window_predictions=pd.concat(all_window_predictions, ignore_index=True),
        trial_predictions=pd.concat(all_trial_predictions, ignore_index=True),
        selected_model_name=selected_model_name,
        feature_columns=tuple(feature_columns),
        labels=labels,
    )


def fit_selected_model(
    features: pd.DataFrame,
    target_column: str,
    model_name: str,
    random_state: int,
) -> BaseEstimator:
    """Fit the chosen baseline on all currently approved training groups."""

    models = candidate_models(random_state)
    if model_name not in models:
        raise ValueError(f"Unknown model: {model_name}")
    columns = model_feature_columns(features)
    fitted = clone(models[model_name])
    fitted.fit(features[columns], features[target_column].astype(str))
    return fitted


def candidate_models(random_state: int) -> dict[str, BaseEstimator]:
    """Return deliberately small baselines suitable for the initial dataset."""

    return {
        "dummy_prior": DummyClassifier(strategy="prior", random_state=random_state),
        "logistic_regression": Pipeline(
            steps=[
                ("scale", StandardScaler(copy=True, with_mean=True, with_std=True)),
                (
                    "classifier",
                    LogisticRegression(
                        C=1.0,
                        class_weight="balanced",
                        max_iter=3_000,
                        random_state=random_state,
                        solver="lbfgs",
                    ),
                ),
            ]
        ),
        "random_forest": RandomForestClassifier(
            n_estimators=400,
            criterion="gini",
            max_depth=None,
            min_samples_split=4,
            min_samples_leaf=2,
            max_features="sqrt",
            bootstrap=True,
            class_weight="balanced_subsample",
            n_jobs=-1,
            random_state=random_state,
        ),
    }


def _aggregate_trial_predictions(
    window_predictions: pd.DataFrame,
    labels: tuple[str, ...],
) -> pd.DataFrame:
    rows: list[dict[str, Any]] = []
    group_columns = ["subject_id", "session_id", "trial_id", "model", "fold"]
    for group_values, trial in window_predictions.groupby(group_columns, sort=False):
        fold_value = group_values[4]
        if not isinstance(fold_value, (int, np.integer)):
            raise ValueError("A trial fold identifier must be an integer.")
        counts = trial["predicted"].value_counts()
        maximum_count = int(counts.max())
        tied = sorted(str(label) for label, count in counts.items() if count == maximum_count)
        predicted = tied[0]
        actual_values = trial["actual"].unique()
        if len(actual_values) != 1:
            raise ValueError("A trial contains multiple actual labels.")
        rows.append(
            {
                "subject_id": group_values[0],
                "session_id": group_values[1],
                "trial_id": group_values[2],
                "model": group_values[3],
                "fold": int(fold_value),
                "actual": str(actual_values[0]),
                "predicted": predicted,
                "confidence": float(
                    trial.loc[trial["predicted"] == predicted, "confidence"].mean()
                ),
                **{
                    f"vote_fraction_{label}": float(np.mean(trial["predicted"] == label))
                    for label in labels
                },
            }
        )
    return pd.DataFrame(rows)


def _classification_metrics(
    actual: pd.Series,
    predicted: pd.Series,
    labels: tuple[str, ...],
) -> dict[str, float]:
    actual_values = actual.astype(str).to_numpy()
    predicted_values = predicted.astype(str).to_numpy()
    gesture_mask = actual_values == "intentional_gesture"
    fidget_mask = actual_values == "fidget"
    return {
        "macro_f1": float(
            f1_score(
                actual_values,
                predicted_values,
                labels=list(labels),
                average="macro",
                zero_division=0,
            )
        ),
        "balanced_accuracy": float(balanced_accuracy_score(actual_values, predicted_values)),
        "gesture_as_fidget_rate": float(np.mean(predicted_values[gesture_mask] == "fidget"))
        if np.any(gesture_mask)
        else 0.0,
        "fidget_as_gesture_rate": float(
            np.mean(predicted_values[fidget_mask] == "intentional_gesture")
        )
        if np.any(fidget_mask)
        else 0.0,
    }
