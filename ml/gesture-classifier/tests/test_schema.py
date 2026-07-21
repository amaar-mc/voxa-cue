"""Behavior tests for versioned dataset ingestion and quality evidence."""

from __future__ import annotations

import json
from pathlib import Path

import pandas as pd
import pytest

from voxa_gesture.schema import (
    ALLOWED_SUBTYPES_BY_BEHAVIOR,
    EXPECTED_FIRMWARE_VERSION,
    EXPECTED_SAMPLE_RATE_HZ,
    EXPECTED_SENSOR_ADDRESS,
    EXPECTED_SENSOR_KIND,
    REQUIRED_COLUMNS,
    DatasetValidationError,
    QualityReport,
    load_and_validate_dataset,
    validate_dataset,
)


def _issue_codes(report: QualityReport) -> set[str]:
    return {issue.code for issue in report.issues}


def test_deterministic_synthetic_dataset_is_trainable(
    synthetic_frame: pd.DataFrame,
) -> None:
    normalized, report = validate_dataset(synthetic_frame)

    assert report.is_trainable
    assert report.errors == ()
    assert report.row_count == len(synthetic_frame)
    assert report.trial_count == 27
    assert report.subject_count == 3
    assert report.session_count == 3
    assert report.behavior_trial_counts == {
        "fidget": 9,
        "intentional_gesture": 9,
        "rest": 9,
    }
    assert tuple(normalized.columns[: len(REQUIRED_COLUMNS)]) == REQUIRED_COLUMNS
    assert normalized["healthy"].eq(True).all()


def test_load_and_validate_combines_csv_exports(
    synthetic_frame: pd.DataFrame,
    tmp_path: Path,
) -> None:
    first_subject = synthetic_frame[synthetic_frame["subject_id"] == "SYN_P01"]
    second_subject = synthetic_frame[synthetic_frame["subject_id"] == "SYN_P02"]
    first_path = tmp_path / "capture-a.csv"
    second_path = tmp_path / "capture-b.csv"
    first_subject.to_csv(first_path, index=False)
    second_subject.to_csv(second_path, index=False)

    normalized, report = load_and_validate_dataset([second_path, first_path])

    assert report.is_trainable
    assert report.subject_count == 2
    assert set(normalized["source_file"].astype(str)) == {
        "capture-a.csv",
        "capture-b.csv",
    }


def test_missing_required_column_is_rejected(synthetic_frame: pd.DataFrame) -> None:
    malformed = synthetic_frame.drop(columns=["gyro_z_dps"])

    with pytest.raises(DatasetValidationError, match="gyro_z_dps"):
        validate_dataset(malformed)


@pytest.mark.parametrize(
    ("mutation", "expected_code"),
    [
        ("unknown_behavior", "unknown_behavior"),
        ("duplicate_sample", "duplicate_sample"),
        ("non_monotonic_time", "non_monotonic_time"),
        ("packet_loss", "packet_loss"),
        ("negative_prompt", "invalid_prompt"),
        ("late_prompt", "invalid_prompt"),
        ("invalid_subtype", "invalid_subtype"),
    ],
)
def test_corrupt_recording_is_not_trainable(
    synthetic_frame: pd.DataFrame,
    mutation: str,
    expected_code: str,
) -> None:
    malformed = synthetic_frame.copy()
    first_trial_id = str(malformed["trial_id"].iloc[0])
    trial_indices = malformed.index[malformed["trial_id"] == first_trial_id]

    if mutation == "unknown_behavior":
        malformed.loc[trial_indices, "behavior"] = "nervous_motion"
    elif mutation == "duplicate_sample":
        malformed = pd.concat([malformed, malformed.loc[[trial_indices[0]]]], ignore_index=True)
    elif mutation == "non_monotonic_time":
        malformed.loc[trial_indices[10], "elapsed_ms"] = malformed.loc[
            trial_indices[9], "elapsed_ms"
        ]
    elif mutation == "packet_loss":
        malformed.loc[trial_indices, "sequence"] = range(len(trial_indices))
        malformed.loc[trial_indices[10:], "sequence"] += 20
    elif mutation == "negative_prompt":
        malformed.loc[trial_indices, "prompt_event_ms"] = -1
    elif mutation == "late_prompt":
        malformed.loc[trial_indices, "prompt_event_ms"] = 3_900
    elif mutation == "invalid_subtype":
        malformed.loc[trial_indices, "subtype"] = "open_palm"
    else:
        raise AssertionError(f"Unhandled test mutation: {mutation}")

    _, report = validate_dataset(malformed)

    assert not report.is_trainable
    assert expected_code in _issue_codes(report)


def test_sequence_rollover_is_not_counted_as_packet_loss(
    synthetic_frame: pd.DataFrame,
) -> None:
    rollover = synthetic_frame.copy()
    first_trial_id = str(rollover["trial_id"].iloc[0])
    trial_indices = rollover.index[rollover["trial_id"] == first_trial_id]
    start = 65_500
    rollover.loc[trial_indices, "sequence"] = [
        (start + offset) % 65_536 for offset in range(len(trial_indices))
    ]

    _, report = validate_dataset(rollover)

    trial_packet_loss = [
        issue
        for issue in report.issues
        if issue.code == "packet_loss" and issue.trial_id is not None
    ]
    assert trial_packet_loss == []


def test_missing_behavior_is_not_trainable(synthetic_frame: pd.DataFrame) -> None:
    without_rest = synthetic_frame[synthetic_frame["behavior"] != "rest"]

    _, report = validate_dataset(without_rest)

    assert not report.is_trainable
    assert "missing_behavior" in _issue_codes(report)


def test_trial_shorter_than_model_window_is_not_trainable(
    synthetic_frame: pd.DataFrame,
) -> None:
    malformed = synthetic_frame.copy()
    first_trial_id = str(malformed["trial_id"].iloc[0])
    first_trial = malformed[malformed["trial_id"] == first_trial_id]
    malformed = malformed.drop(index=first_trial.index[first_trial["elapsed_ms"] > 1_900])
    malformed.loc[malformed["trial_id"] == first_trial_id, "prompt_event_ms"] = 1_000

    _, report = validate_dataset(malformed)

    assert not report.is_trainable
    assert "trial_too_short" in _issue_codes(report)


def test_severe_behavior_imbalance_is_reported(synthetic_frame: pd.DataFrame) -> None:
    rest_trial_id = str(
        synthetic_frame.loc[synthetic_frame["behavior"] == "rest", "trial_id"].iloc[0]
    )
    imbalanced = synthetic_frame[
        (synthetic_frame["behavior"] != "rest") | (synthetic_frame["trial_id"] == rest_trial_id)
    ]

    _, report = validate_dataset(imbalanced)

    assert report.is_trainable
    assert "class_imbalance" in _issue_codes(report)


def test_browser_label_config_matches_python_subtype_contract() -> None:
    config_path = Path(__file__).parents[1] / "configs" / "labels-v1.json"
    config = json.loads(config_path.read_text(encoding="utf-8"))
    configured = {
        behavior["id"]: frozenset(subtype["id"] for subtype in behavior["subtypes"])
        for behavior in config["behaviors"]
    }

    assert configured == ALLOWED_SUBTYPES_BY_BEHAVIOR


def test_normative_json_schema_matches_ingestion_constants() -> None:
    schema_path = Path(__file__).parents[1] / "schemas" / "recording-v1.schema.json"
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    properties = schema["properties"]

    assert schema["additionalProperties"] is False
    assert tuple(schema["required"]) == REQUIRED_COLUMNS
    assert set(properties["behavior"]["enum"]) == set(ALLOWED_SUBTYPES_BY_BEHAVIOR)
    assert properties["prompt_event_ms"] == {
        "type": "integer",
        "minimum": 0,
        "maximum": 3_500,
    }
    assert properties["sensor_kind"]["const"] == EXPECTED_SENSOR_KIND
    assert properties["sensor_address"]["const"] == EXPECTED_SENSOR_ADDRESS
    assert properties["firmware"]["const"] == EXPECTED_FIRMWARE_VERSION
    assert properties["target_sample_rate_hz"]["const"] == EXPECTED_SAMPLE_RATE_HZ


@pytest.mark.parametrize(
    ("column", "invalid_value", "expected_code"),
    [
        ("schema_version", 1.5, "schema_version"),
        ("subject_id", "bad id", "invalid_identifier"),
        ("session_id", "x" * 41, "invalid_identifier"),
        ("trial_id", "", "invalid_trial_id"),
        ("trial_started_at_utc", "2026-01-01T12:00:00", "invalid_timestamp"),
        ("trial_started_at_utc", "2026-02-30T12:00:00Z", "invalid_timestamp"),
        ("repetition", 1.5, "invalid_repetition"),
        ("repetition", 0, "invalid_repetition"),
        ("prompt_event_ms", 1.5, "invalid_prompt"),
        ("prompt_event_ms", 3_501, "invalid_prompt"),
        ("device_ms", -1, "invalid_device_ms"),
        ("device_ms", 4_294_967_296, "invalid_device_ms"),
        ("sequence", 1.5, "invalid_sequence"),
        ("sequence", 65_536, "invalid_sequence"),
        ("sample_index", 1.5, "invalid_sample_index"),
        ("elapsed_ms", -0.1, "invalid_elapsed_ms"),
        ("elapsed_ms", float("inf"), "invalid_elapsed_ms"),
        ("host_elapsed_ms", -0.1, "invalid_host_elapsed_ms"),
        ("host_elapsed_ms", float("nan"), "invalid_host_elapsed_ms"),
        ("accel_x_g", 16.1, "physical_range"),
        ("gyro_x_dps", 2_000.1, "physical_range"),
        ("sensor_kind", "MPU-6050 family", "invalid_sensor_kind"),
        ("sensor_address", "0x6a", "invalid_sensor_address"),
        ("firmware", "1.0", "invalid_firmware"),
        ("target_sample_rate_hz", 49, "invalid_target_sample_rate"),
        ("healthy", "yes", "invalid_health_flag"),
        ("wrist", "center", "unknown_wrist"),
        ("orientation", "upside_down", "unknown_orientation"),
    ],
)
def test_normative_row_constraints_are_enforced(
    synthetic_frame: pd.DataFrame,
    column: str,
    invalid_value: object,
    expected_code: str,
) -> None:
    malformed = synthetic_frame.copy()
    first_trial_id = str(malformed["trial_id"].iloc[0])
    trial_indices = malformed.index[malformed["trial_id"] == first_trial_id]
    malformed[column] = malformed[column].astype("object")
    malformed.loc[trial_indices, column] = invalid_value

    _, report = validate_dataset(malformed)

    assert not report.is_trainable
    assert expected_code in _issue_codes(report)


def test_nonsequential_sample_indices_are_rejected(synthetic_frame: pd.DataFrame) -> None:
    malformed = synthetic_frame.copy()
    first_trial_id = str(malformed["trial_id"].iloc[0])
    trial_indices = malformed.index[malformed["trial_id"] == first_trial_id]
    malformed.loc[trial_indices, "sample_index"] += 1

    _, report = validate_dataset(malformed)

    assert not report.is_trainable
    assert "non_sequential_sample_index" in _issue_codes(report)


def test_duplicate_ble_sequence_is_rejected(synthetic_frame: pd.DataFrame) -> None:
    malformed = synthetic_frame.copy()
    first_trial_id = str(malformed["trial_id"].iloc[0])
    trial_indices = malformed.index[malformed["trial_id"] == first_trial_id]
    malformed.loc[trial_indices[10], "sequence"] = malformed.loc[trial_indices[9], "sequence"]

    _, report = validate_dataset(malformed)

    assert not report.is_trainable
    assert "duplicate_sequence" in _issue_codes(report)


def test_non_schema_column_is_rejected(synthetic_frame: pd.DataFrame) -> None:
    malformed = synthetic_frame.assign(participant_name="not allowed")

    _, report = validate_dataset(malformed)

    assert not report.is_trainable
    assert "unexpected_columns" in _issue_codes(report)
