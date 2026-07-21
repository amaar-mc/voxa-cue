"""Versioned ingestion and quality checks for labeled Voxa IMU recordings."""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

import numpy as np
import pandas as pd

SCHEMA_VERSION = 1
EXPECTED_SENSOR_KIND = "LSM6 family"
EXPECTED_SENSOR_ADDRESS = "0x6A"
EXPECTED_FIRMWARE_VERSION = "1.1"
EXPECTED_SAMPLE_RATE_HZ = 50
MINIMUM_TRIAL_DURATION_SECONDS = 2.0
IDENTIFIER_PATTERN = r"[A-Za-z0-9][A-Za-z0-9_-]{0,39}"
RFC3339_PATTERN = r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})"
ALLOWED_BEHAVIORS = frozenset({"rest", "intentional_gesture", "fidget"})
ALLOWED_SUBTYPES_BY_BEHAVIOR = {
    "rest": frozenset({"still"}),
    "intentional_gesture": frozenset({"beat", "open_palm", "point", "sweep", "count"}),
    "fidget": frozenset(
        {"wrist_twist", "strap_touch", "hand_clasp", "object_fidget", "self_touch"}
    ),
}
ALLOWED_WRISTS = frozenset({"left", "right"})
ALLOWED_ORIENTATIONS = frozenset({"usb_toward_hand", "usb_toward_elbow", "custom_consistent"})

REQUIRED_COLUMNS = (
    "schema_version",
    "subject_id",
    "session_id",
    "trial_id",
    "trial_started_at_utc",
    "behavior",
    "subtype",
    "wrist",
    "orientation",
    "repetition",
    "prompt_event_ms",
    "device_ms",
    "sequence",
    "sample_index",
    "elapsed_ms",
    "host_elapsed_ms",
    "accel_x_g",
    "accel_y_g",
    "accel_z_g",
    "gyro_x_dps",
    "gyro_y_dps",
    "gyro_z_dps",
    "sensor_kind",
    "sensor_address",
    "firmware",
    "target_sample_rate_hz",
    "healthy",
)

STRING_COLUMNS = (
    "subject_id",
    "session_id",
    "trial_id",
    "trial_started_at_utc",
    "behavior",
    "subtype",
    "wrist",
    "orientation",
    "sensor_kind",
    "sensor_address",
    "firmware",
)

NUMERIC_COLUMNS = (
    "schema_version",
    "repetition",
    "prompt_event_ms",
    "device_ms",
    "sequence",
    "sample_index",
    "elapsed_ms",
    "host_elapsed_ms",
    "accel_x_g",
    "accel_y_g",
    "accel_z_g",
    "gyro_x_dps",
    "gyro_y_dps",
    "gyro_z_dps",
    "target_sample_rate_hz",
)

INTEGER_COLUMNS = (
    "schema_version",
    "repetition",
    "prompt_event_ms",
    "device_ms",
    "sequence",
    "sample_index",
    "target_sample_rate_hz",
)

TRIAL_METADATA_COLUMNS = (
    "schema_version",
    "subject_id",
    "session_id",
    "trial_id",
    "trial_started_at_utc",
    "behavior",
    "subtype",
    "wrist",
    "orientation",
    "repetition",
    "prompt_event_ms",
    "sensor_kind",
    "sensor_address",
    "firmware",
    "target_sample_rate_hz",
)


@dataclass(frozen=True)
class QualityIssue:
    """One actionable dataset quality finding."""

    severity: Literal["error", "warning"]
    code: str
    message: str
    trial_id: str | None


@dataclass(frozen=True)
class QualityReport:
    """Compact evidence that a dataset is or is not safe to train on."""

    row_count: int
    trial_count: int
    subject_count: int
    session_count: int
    behavior_trial_counts: dict[str, int]
    issues: tuple[QualityIssue, ...]

    @property
    def errors(self) -> tuple[QualityIssue, ...]:
        return tuple(issue for issue in self.issues if issue.severity == "error")

    @property
    def warnings(self) -> tuple[QualityIssue, ...]:
        return tuple(issue for issue in self.issues if issue.severity == "warning")

    @property
    def is_trainable(self) -> bool:
        return len(self.errors) == 0

    def render(self) -> str:
        lines = [
            f"Rows: {self.row_count}",
            f"Trials: {self.trial_count}",
            f"Subjects: {self.subject_count}",
            f"Sessions: {self.session_count}",
            "Behavior trials: "
            + ", ".join(
                f"{label}={count}" for label, count in sorted(self.behavior_trial_counts.items())
            ),
        ]
        if not self.issues:
            lines.append("Quality checks: passed")
        for issue in self.issues:
            scope = f" [{issue.trial_id}]" if issue.trial_id is not None else ""
            lines.append(f"{issue.severity.upper()} {issue.code}{scope}: {issue.message}")
        return "\n".join(lines)


class DatasetValidationError(ValueError):
    """Raised when a recording cannot be interpreted as schema v1."""


def load_and_validate_dataset(paths: Sequence[Path]) -> tuple[pd.DataFrame, QualityReport]:
    """Load one or more recorder CSV exports and run trial-level quality checks."""

    if len(paths) == 0:
        raise DatasetValidationError("At least one dataset CSV path is required.")

    frames: list[pd.DataFrame] = []
    for path in paths:
        if not path.is_file():
            raise DatasetValidationError(f"Dataset file does not exist: {path}")
        frame = pd.read_csv(path)
        frame["source_file"] = path.name
        frames.append(frame)

    combined = pd.concat(frames, ignore_index=True)
    return validate_dataset(combined)


def validate_dataset(frame: pd.DataFrame) -> tuple[pd.DataFrame, QualityReport]:
    """Normalize a recorder export and return concrete quality evidence."""

    missing_columns = [column for column in REQUIRED_COLUMNS if column not in frame.columns]
    if missing_columns:
        missing = ", ".join(missing_columns)
        raise DatasetValidationError(f"Dataset is missing required columns: {missing}")

    normalized = frame.copy()
    issues: list[QualityIssue] = []

    allowed_columns = {*REQUIRED_COLUMNS, "source_file"}
    unexpected_columns = sorted(set(normalized.columns) - allowed_columns)
    if unexpected_columns:
        issues.append(
            QualityIssue(
                "error",
                "unexpected_columns",
                f"Dataset contains non-schema columns: {', '.join(unexpected_columns)}.",
                None,
            )
        )

    for column in STRING_COLUMNS:
        normalized[column] = normalized[column].astype("string").str.strip()
    for column in NUMERIC_COLUMNS:
        normalized[column] = pd.to_numeric(normalized[column], errors="coerce")
    normalized["healthy"] = normalized["healthy"].map(_parse_boolean)

    numeric_values = normalized[list(NUMERIC_COLUMNS)].to_numpy(dtype=float, na_value=np.nan)
    invalid_numeric = pd.Series(
        ~np.isfinite(numeric_values).all(axis=1),
        index=normalized.index,
    )
    if invalid_numeric.any():
        issues.append(
            QualityIssue(
                "error",
                "non_numeric_sample",
                (
                    f"{int(invalid_numeric.sum())} rows contain missing, non-numeric, "
                    "or non-finite numeric values."
                ),
                None,
            )
        )
    invalid_health = normalized["healthy"].isna()
    if invalid_health.any():
        issues.append(
            QualityIssue(
                "error",
                "invalid_health_flag",
                f"{int(invalid_health.sum())} rows have an invalid healthy flag.",
                None,
            )
        )

    integer_masks = {column: _valid_integer_mask(normalized[column]) for column in INTEGER_COLUMNS}
    _append_mask_issue(
        issues,
        ~(integer_masks["schema_version"] & normalized["schema_version"].eq(SCHEMA_VERSION)),
        "schema_version",
        f"schema_version must be the integer {SCHEMA_VERSION}.",
    )
    _append_mask_issue(
        issues,
        ~(integer_masks["repetition"] & normalized["repetition"].ge(1)),
        "invalid_repetition",
        "repetition must be an integer greater than or equal to 1.",
    )
    _append_mask_issue(
        issues,
        ~(
            integer_masks["prompt_event_ms"]
            & normalized["prompt_event_ms"].between(0, 3_500, inclusive="both")
        ),
        "invalid_prompt",
        "prompt_event_ms must be an integer from 0 through 3500.",
    )
    _append_mask_issue(
        issues,
        ~(
            integer_masks["device_ms"]
            & normalized["device_ms"].between(0, 4_294_967_295, inclusive="both")
        ),
        "invalid_device_ms",
        "device_ms must be an integer from 0 through 4294967295.",
    )
    _append_mask_issue(
        issues,
        ~(integer_masks["sequence"] & normalized["sequence"].between(0, 65_535, inclusive="both")),
        "invalid_sequence",
        "sequence must be an integer from 0 through 65535.",
    )
    _append_mask_issue(
        issues,
        ~(integer_masks["sample_index"] & normalized["sample_index"].ge(0)),
        "invalid_sample_index",
        "sample_index must be a nonnegative integer.",
    )
    _append_mask_issue(
        issues,
        ~(
            integer_masks["target_sample_rate_hz"]
            & normalized["target_sample_rate_hz"].eq(EXPECTED_SAMPLE_RATE_HZ)
        ),
        "invalid_target_sample_rate",
        f"target_sample_rate_hz must be the integer {EXPECTED_SAMPLE_RATE_HZ}.",
    )

    identifier_validity = {
        "subject_id": normalized["subject_id"].str.fullmatch(IDENTIFIER_PATTERN, na=False),
        "session_id": normalized["session_id"].str.fullmatch(IDENTIFIER_PATTERN, na=False),
    }
    for column, valid in identifier_validity.items():
        _append_mask_issue(
            issues,
            ~valid,
            "invalid_identifier",
            (
                f"{column} must use 1-40 letters, numbers, underscores, or hyphens "
                "and begin with a letter or number."
            ),
        )
    _append_mask_issue(
        issues,
        ~normalized["trial_id"].str.len().between(1, 120, inclusive="both").fillna(False),
        "invalid_trial_id",
        "trial_id must contain 1-120 characters.",
    )

    timestamp_syntax = normalized["trial_started_at_utc"].str.fullmatch(
        RFC3339_PATTERN,
        na=False,
    )
    parsed_timestamps = pd.to_datetime(
        normalized["trial_started_at_utc"],
        errors="coerce",
        utc=True,
        format="ISO8601",
    )
    _append_mask_issue(
        issues,
        ~(timestamp_syntax & parsed_timestamps.notna()),
        "invalid_timestamp",
        "trial_started_at_utc must be a valid RFC3339 timestamp with a UTC offset.",
    )

    invalid_behaviors = sorted(set(normalized["behavior"].dropna()) - ALLOWED_BEHAVIORS)
    if invalid_behaviors:
        issues.append(
            QualityIssue(
                "error",
                "unknown_behavior",
                f"Unknown behavior labels: {', '.join(invalid_behaviors)}.",
                None,
            )
        )
    invalid_subtype_rows = ~normalized["behavior"].isin(ALLOWED_BEHAVIORS)
    for behavior, allowed_subtypes in ALLOWED_SUBTYPES_BY_BEHAVIOR.items():
        behavior_rows = normalized["behavior"].eq(behavior)
        invalid_subtype_rows |= behavior_rows & ~normalized["subtype"].isin(allowed_subtypes)
    if invalid_subtype_rows.any():
        invalid_pairs = sorted(
            {
                f"{row.behavior}/{row.subtype}"
                for row in normalized.loc[invalid_subtype_rows, ["behavior", "subtype"]].itertuples(
                    index=False
                )
            }
        )
        issues.append(
            QualityIssue(
                "error",
                "invalid_subtype",
                f"Invalid behavior/subtype pairs: {', '.join(invalid_pairs)}.",
                None,
            )
        )
    invalid_wrists = sorted(set(normalized["wrist"].dropna()) - ALLOWED_WRISTS)
    if invalid_wrists:
        issues.append(
            QualityIssue(
                "error",
                "unknown_wrist",
                f"Unknown wrist values: {', '.join(invalid_wrists)}.",
                None,
            )
        )
    invalid_orientations = sorted(set(normalized["orientation"].dropna()) - ALLOWED_ORIENTATIONS)
    if invalid_orientations:
        issues.append(
            QualityIssue(
                "error",
                "unknown_orientation",
                f"Unknown mount orientations: {', '.join(invalid_orientations)}.",
                None,
            )
        )

    _append_mask_issue(
        issues,
        ~normalized["sensor_kind"].eq(EXPECTED_SENSOR_KIND),
        "invalid_sensor_kind",
        f"sensor_kind must be {EXPECTED_SENSOR_KIND!r}.",
    )
    _append_mask_issue(
        issues,
        ~normalized["sensor_address"].eq(EXPECTED_SENSOR_ADDRESS),
        "invalid_sensor_address",
        f"sensor_address must be {EXPECTED_SENSOR_ADDRESS!r}.",
    )
    _append_mask_issue(
        issues,
        ~normalized["firmware"].eq(EXPECTED_FIRMWARE_VERSION),
        "invalid_firmware",
        f"firmware must be {EXPECTED_FIRMWARE_VERSION!r}.",
    )

    finite_elapsed = _finite_mask(normalized["elapsed_ms"])
    finite_host_elapsed = _finite_mask(normalized["host_elapsed_ms"])
    _append_mask_issue(
        issues,
        ~(finite_elapsed & normalized["elapsed_ms"].ge(0)),
        "invalid_elapsed_ms",
        "elapsed_ms must be finite and nonnegative.",
    )
    _append_mask_issue(
        issues,
        ~(finite_host_elapsed & normalized["host_elapsed_ms"].ge(0)),
        "invalid_host_elapsed_ms",
        "host_elapsed_ms must be finite and nonnegative.",
    )

    duplicate_key = normalized.duplicated(
        subset=["subject_id", "session_id", "trial_id", "sample_index"], keep=False
    )
    if duplicate_key.any():
        issues.append(
            QualityIssue(
                "error",
                "duplicate_sample",
                f"{int(duplicate_key.sum())} rows duplicate a trial sample index.",
                None,
            )
        )

    trial_group_columns = ["subject_id", "session_id", "trial_id"]
    sample_order = normalized.sort_values(
        [*trial_group_columns, "sample_index"],
        kind="stable",
        na_position="last",
    )
    expected_sample_index = sample_order.groupby(
        trial_group_columns,
        sort=False,
        dropna=False,
    ).cumcount()
    sequential_sample_index = integer_masks["sample_index"].reindex(
        sample_order.index
    ) & sample_order["sample_index"].eq(expected_sample_index)
    _append_mask_issue(
        issues,
        ~sequential_sample_index,
        "non_sequential_sample_index",
        "Each trial must contain sample_index values 0 through N-1 without gaps.",
    )

    acceleration_out_of_range = (
        normalized[["accel_x_g", "accel_y_g", "accel_z_g"]].abs().gt(16).any(axis=1)
    )
    gyro_out_of_range = (
        normalized[["gyro_x_dps", "gyro_y_dps", "gyro_z_dps"]].abs().gt(2_000).any(axis=1)
    )
    if acceleration_out_of_range.any() or gyro_out_of_range.any():
        issues.append(
            QualityIssue(
                "error",
                "physical_range",
                "At least one sample exceeds the supported ±16 g or ±2000 °/s range.",
                None,
            )
        )

    grouped = normalized.groupby(trial_group_columns, sort=False, dropna=False)
    for (subject_id, session_id, trial_id), trial in grouped:
        trial_scope = f"{subject_id}/{session_id}/{trial_id}"
        _validate_trial(trial, trial_scope, issues)

    trial_metadata = normalized[list(TRIAL_METADATA_COLUMNS)].drop_duplicates()
    behavior_counts = {
        str(label): int(count)
        for label, count in trial_metadata.groupby("behavior")["trial_id"].count().items()
    }
    missing_behaviors = sorted(ALLOWED_BEHAVIORS - set(behavior_counts))
    if missing_behaviors:
        issues.append(
            QualityIssue(
                "error",
                "missing_behavior",
                f"Dataset is missing required behaviors: {', '.join(missing_behaviors)}.",
                None,
            )
        )
    for behavior in sorted(ALLOWED_BEHAVIORS):
        count = behavior_counts.get(behavior, 0)
        if count < 20:
            issues.append(
                QualityIssue(
                    "warning",
                    "small_class",
                    (
                        f"{behavior} has {count} trials; collect at least 20 before "
                        "interpreting metrics."
                    ),
                    None,
                )
            )
    nonzero_behavior_counts = [
        behavior_counts[behavior]
        for behavior in ALLOWED_BEHAVIORS
        if behavior_counts.get(behavior, 0) > 0
    ]
    if (
        len(nonzero_behavior_counts) == len(ALLOWED_BEHAVIORS)
        and max(nonzero_behavior_counts) / min(nonzero_behavior_counts) > 1.5
    ):
        issues.append(
            QualityIssue(
                "warning",
                "class_imbalance",
                "Largest behavior class exceeds the smallest by more than 1.5x.",
                None,
            )
        )

    subject_count = int(normalized["subject_id"].nunique())
    session_count = int(normalized[["subject_id", "session_id"]].drop_duplicates().shape[0])
    if subject_count < 2 and session_count < 3:
        issues.append(
            QualityIssue(
                "warning",
                "insufficient_groups",
                (
                    "Use at least three separate sessions for a personalized evaluation, "
                    "or multiple subjects for cross-person claims."
                ),
                None,
            )
        )

    normalized = normalized.sort_values(
        ["subject_id", "session_id", "trial_id", "sample_index"], kind="stable"
    ).reset_index(drop=True)
    report = QualityReport(
        row_count=len(normalized),
        trial_count=int(normalized[trial_group_columns].drop_duplicates().shape[0]),
        subject_count=subject_count,
        session_count=session_count,
        behavior_trial_counts=behavior_counts,
        issues=tuple(issues),
    )
    return normalized, report


def _validate_trial(
    trial: pd.DataFrame,
    trial_scope: str,
    issues: list[QualityIssue],
) -> None:
    for column in TRIAL_METADATA_COLUMNS:
        if trial[column].nunique(dropna=False) != 1:
            issues.append(
                QualityIssue(
                    "error",
                    "mixed_trial_metadata",
                    f"{column} changes within one trial.",
                    trial_scope,
                )
            )

    ordered = trial.sort_values("sample_index", kind="stable")
    elapsed = ordered["elapsed_ms"].to_numpy(dtype=float)
    if len(elapsed) < 2 or not np.isfinite(elapsed).all() or np.any(np.diff(elapsed) <= 0):
        issues.append(
            QualityIssue(
                "error",
                "non_monotonic_time",
                "Device-relative sample times must increase strictly.",
                trial_scope,
            )
        )
        return

    duration_seconds = (elapsed[-1] - elapsed[0]) / 1_000
    duration_milliseconds = elapsed[-1] - elapsed[0]
    measured_rate_hz = (len(elapsed) - 1) / duration_seconds if duration_seconds > 0 else 0
    target_rate_hz = float(ordered["target_sample_rate_hz"].iloc[0])
    prompt_event_ms = float(ordered["prompt_event_ms"].iloc[0])
    if (
        not np.isfinite(prompt_event_ms)
        or prompt_event_ms < 0
        or prompt_event_ms > duration_milliseconds - 500
    ):
        issues.append(
            QualityIssue(
                "error",
                "invalid_prompt",
                "Every trial requires a prompt at least 500 ms before the captured end.",
                trial_scope,
            )
        )
    if duration_seconds < MINIMUM_TRIAL_DURATION_SECONDS:
        issues.append(
            QualityIssue(
                "error",
                "trial_too_short",
                (
                    f"Only {duration_seconds:.2f} seconds were captured; at least "
                    f"{MINIMUM_TRIAL_DURATION_SECONDS:.1f} seconds is required for one "
                    "complete model window."
                ),
                trial_scope,
            )
        )
    elif duration_seconds < 3.5:
        issues.append(
            QualityIssue(
                "warning",
                "short_trial",
                (
                    f"Only {duration_seconds:.2f} seconds were captured; the collection "
                    "target is 4 seconds."
                ),
                trial_scope,
            )
        )
    if measured_rate_hz < 15 or measured_rate_hz > 70:
        issues.append(
            QualityIssue(
                "error",
                "sample_rate",
                f"Measured {measured_rate_hz:.1f} Hz, outside the supported 15-70 Hz range.",
                trial_scope,
            )
        )
    elif target_rate_hz > 0 and abs(measured_rate_hz - target_rate_hz) / target_rate_hz > 0.25:
        issues.append(
            QualityIssue(
                "warning",
                "sample_rate_drift",
                (
                    f"Measured {measured_rate_hz:.1f} Hz versus the {target_rate_hz:.1f} "
                    "Hz firmware target."
                ),
                trial_scope,
            )
        )

    valid_sequence = _valid_integer_mask(ordered["sequence"]) & ordered["sequence"].between(
        0,
        65_535,
        inclusive="both",
    )
    if valid_sequence.all():
        sequences = ordered["sequence"].to_numpy(dtype=np.uint32)
        sequence_steps = np.diff(sequences) % 65_536
        if np.any(sequence_steps == 0):
            issues.append(
                QualityIssue(
                    "error",
                    "duplicate_sequence",
                    "BLE sequence numbers must advance for every recorded packet.",
                    trial_scope,
                )
            )
        missing_packets = int(np.maximum(sequence_steps.astype(np.int64) - 1, 0).sum())
        expected_packets = len(sequences) + missing_packets
        loss_rate = missing_packets / expected_packets if expected_packets > 0 else 0
        if loss_rate > 0.05:
            issues.append(
                QualityIssue(
                    "error",
                    "packet_loss",
                    f"Estimated packet loss is {loss_rate:.1%}; retry this trial.",
                    trial_scope,
                )
            )
        elif loss_rate > 0.01:
            issues.append(
                QualityIssue(
                    "warning",
                    "packet_loss",
                    f"Estimated packet loss is {loss_rate:.1%}.",
                    trial_scope,
                )
            )

    healthy_values = ordered["healthy"].astype("boolean").fillna(False)
    if not bool(healthy_values.all()):
        issues.append(
            QualityIssue(
                "error",
                "sensor_fault",
                "At least one packet reported an unhealthy sensor.",
                trial_scope,
            )
        )


def _append_mask_issue(
    issues: list[QualityIssue],
    invalid_mask: pd.Series,
    code: str,
    message: str,
) -> None:
    invalid_count = int(invalid_mask.fillna(True).sum())
    if invalid_count == 0:
        return
    issues.append(
        QualityIssue(
            "error",
            code,
            f"{message} Invalid rows: {invalid_count}.",
            None,
        )
    )


def _finite_mask(values: pd.Series) -> pd.Series:
    numeric = values.to_numpy(dtype=float, na_value=np.nan)
    return pd.Series(np.isfinite(numeric), index=values.index)


def _valid_integer_mask(values: pd.Series) -> pd.Series:
    numeric = values.to_numpy(dtype=float, na_value=np.nan)
    finite = np.isfinite(numeric)
    valid = np.zeros(len(numeric), dtype=bool)
    valid[finite] = numeric[finite] == np.floor(numeric[finite])
    return pd.Series(valid, index=values.index)


def _parse_boolean(value: object) -> bool | None:
    if isinstance(value, (bool, np.bool_)):
        return bool(value)
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized == "true":
            return True
        if normalized == "false":
            return False
    return None
