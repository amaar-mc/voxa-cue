"""Causal windowing and deterministic IMU feature extraction."""

from __future__ import annotations

from dataclasses import dataclass
from itertools import combinations

import numpy as np
import pandas as pd

SENSOR_COLUMNS = (
    "accel_x_g",
    "accel_y_g",
    "accel_z_g",
    "gyro_x_dps",
    "gyro_y_dps",
    "gyro_z_dps",
)

PROMPT_WINDOW_MIN_END_DELAY_MS = 350.0
PROMPT_WINDOW_MAX_END_DELAY_MS = 1_100.0

WINDOW_METADATA_COLUMNS = (
    "subject_id",
    "session_id",
    "trial_id",
    "behavior",
    "subtype",
    "wrist",
    "orientation",
    "window_index",
    "window_start_ms",
    "window_end_ms",
    "participant_group",
    "session_group",
)


@dataclass(frozen=True)
class WindowConfig:
    """All temporal assumptions required to reproduce model features."""

    sample_rate_hz: int
    window_seconds: float
    hop_seconds: float

    def validate(self) -> None:
        if self.sample_rate_hz <= 0:
            raise ValueError("sample_rate_hz must be positive")
        if self.window_seconds <= 0:
            raise ValueError("window_seconds must be positive")
        if self.hop_seconds <= 0 or self.hop_seconds > self.window_seconds:
            raise ValueError("hop_seconds must be positive and no larger than window_seconds")


def extract_window_features(frame: pd.DataFrame, config: WindowConfig) -> pd.DataFrame:
    """Resample each trial independently and create fixed causal feature windows."""

    config.validate()
    required = {
        "subject_id",
        "session_id",
        "trial_id",
        "behavior",
        "subtype",
        "wrist",
        "orientation",
        "prompt_event_ms",
        "elapsed_ms",
        *SENSOR_COLUMNS,
    }
    missing = sorted(required - set(frame.columns))
    if missing:
        raise ValueError(f"Feature input is missing columns: {', '.join(missing)}")

    feature_rows: list[dict[str, float | int | str]] = []
    trial_window_counts: dict[str, int] = {}
    trial_columns = ["subject_id", "session_id", "trial_id"]
    for trial_key, trial in frame.groupby(trial_columns, sort=False):
        resampled = _resample_trial(trial, config.sample_rate_hz)
        trial_rows = _window_trial(resampled, trial, config)
        trial_scope = "::".join(str(value) for value in trial_key)
        trial_window_counts[trial_scope] = len(trial_rows)
        feature_rows.extend(trial_rows)

    missing_trials = sorted(
        trial_scope for trial_scope, count in trial_window_counts.items() if count == 0
    )
    if missing_trials:
        raise ValueError(
            "Trials produced no prompt-aligned feature windows: "
            f"{', '.join(missing_trials)}. Retry or remove those trials."
        )
    distinct_window_counts = sorted(set(trial_window_counts.values()))
    if len(distinct_window_counts) != 1:
        raise ValueError(
            "Trials produced unequal prompt-aligned window counts "
            f"{distinct_window_counts}; retry incomplete trials before training."
        )
    features = pd.DataFrame(feature_rows)
    numeric_columns = [
        column for column in features.columns if column not in WINDOW_METADATA_COLUMNS
    ]
    numeric = features[numeric_columns].to_numpy(dtype=float)
    if not np.isfinite(numeric).all():
        raise ValueError("Feature extraction produced non-finite values.")
    return features


def model_feature_columns(features: pd.DataFrame) -> list[str]:
    """Return only sensor-derived columns; identifiers and timing never enter the model."""

    columns = [column for column in features.columns if column not in WINDOW_METADATA_COLUMNS]
    if not columns:
        raise ValueError("No model feature columns are available.")
    return columns


def _resample_trial(trial: pd.DataFrame, sample_rate_hz: int) -> pd.DataFrame:
    ordered = trial.sort_values("elapsed_ms", kind="stable")
    deduplicated = ordered.drop_duplicates(subset=["elapsed_ms"], keep="first")
    elapsed_seconds = deduplicated["elapsed_ms"].to_numpy(dtype=float) / 1_000
    elapsed_seconds -= elapsed_seconds[0]
    if len(elapsed_seconds) < 2 or elapsed_seconds[-1] <= 0:
        raise ValueError(f"Trial {trial['trial_id'].iloc[0]} has no usable time span.")

    step_seconds = 1 / sample_rate_hz
    uniform_time = np.arange(0, elapsed_seconds[-1] + step_seconds / 2, step_seconds)
    resampled: dict[str, np.ndarray] = {"elapsed_seconds": uniform_time}
    for column in SENSOR_COLUMNS:
        values = deduplicated[column].to_numpy(dtype=float)
        resampled[column] = np.interp(uniform_time, elapsed_seconds, values)
    return pd.DataFrame(resampled)


def _window_trial(
    resampled: pd.DataFrame,
    source_trial: pd.DataFrame,
    config: WindowConfig,
) -> list[dict[str, float | int | str]]:
    window_samples = round(config.window_seconds * config.sample_rate_hz)
    hop_samples = round(config.hop_seconds * config.sample_rate_hz)
    if window_samples < 4 or hop_samples < 1:
        raise ValueError("Window configuration produces too few samples.")

    metadata = source_trial.iloc[0]
    behavior = str(metadata["behavior"])
    prompt_event_ms = float(metadata["prompt_event_ms"])
    rows: list[dict[str, float | int | str]] = []
    for window_index, start in enumerate(range(0, len(resampled), hop_samples)):
        stop = start + window_samples
        if stop > len(resampled):
            break
        window = resampled.iloc[start:stop]
        window_start_ms = float(window["elapsed_seconds"].iloc[0] * 1_000)
        window_end_ms = float(window["elapsed_seconds"].iloc[-1] * 1_000)
        end_delay_ms = window_end_ms - prompt_event_ms
        if not (PROMPT_WINDOW_MIN_END_DELAY_MS <= end_delay_ms <= PROMPT_WINDOW_MAX_END_DELAY_MS):
            continue
        feature_row: dict[str, float | int | str] = {
            "subject_id": str(metadata["subject_id"]),
            "session_id": str(metadata["session_id"]),
            "trial_id": str(metadata["trial_id"]),
            "behavior": behavior,
            "subtype": str(metadata["subtype"]),
            "wrist": str(metadata["wrist"]),
            "orientation": str(metadata["orientation"]),
            "window_index": window_index,
            "window_start_ms": window_start_ms,
            "window_end_ms": window_end_ms,
            "participant_group": str(metadata["subject_id"]),
            "session_group": f"{metadata['subject_id']}::{metadata['session_id']}",
        }
        feature_row.update(_features_for_window(window, config.sample_rate_hz))
        rows.append(feature_row)
    return rows


def _features_for_window(window: pd.DataFrame, sample_rate_hz: int) -> dict[str, float]:
    acceleration = window[["accel_x_g", "accel_y_g", "accel_z_g"]].to_numpy(dtype=float)
    gyro = window[["gyro_x_dps", "gyro_y_dps", "gyro_z_dps"]].to_numpy(dtype=float)
    acceleration_magnitude = np.linalg.norm(acceleration, axis=1)
    gyro_bias_corrected = gyro - np.median(gyro, axis=0)
    gyro_magnitude = np.linalg.norm(gyro_bias_corrected, axis=1)
    dynamic_acceleration = np.abs(acceleration_magnitude - 1)
    jerk = np.gradient(acceleration, axis=0) * sample_rate_hz
    jerk_magnitude = np.linalg.norm(jerk, axis=1)

    channels = {
        "accel_x": acceleration[:, 0],
        "accel_y": acceleration[:, 1],
        "accel_z": acceleration[:, 2],
        "gyro_x": gyro[:, 0],
        "gyro_y": gyro[:, 1],
        "gyro_z": gyro[:, 2],
        "accel_magnitude": acceleration_magnitude,
        "dynamic_accel": dynamic_acceleration,
        "gyro_magnitude": gyro_magnitude,
        "jerk_magnitude": jerk_magnitude,
    }
    output: dict[str, float] = {}
    for name, values in channels.items():
        output.update(_channel_features(name, values, sample_rate_hz))

    output["active_fraction"] = float(
        np.mean((dynamic_acceleration >= 0.08) | (gyro_magnitude >= 35))
    )
    output["high_motion_fraction"] = float(
        np.mean((dynamic_acceleration >= 0.25) | (gyro_magnitude >= 120))
    )

    combined = np.column_stack((acceleration, gyro))
    combined_names = ("ax", "ay", "az", "gx", "gy", "gz")
    for (left_index, left_name), (right_index, right_name) in combinations(
        enumerate(combined_names), 2
    ):
        output[f"corr_{left_name}_{right_name}"] = _safe_correlation(
            combined[:, left_index], combined[:, right_index]
        )
    return output


def _channel_features(name: str, values: np.ndarray, sample_rate_hz: int) -> dict[str, float]:
    centered = values - np.mean(values)
    differences = np.diff(values)
    q25, q75 = np.quantile(values, [0.25, 0.75])
    power, frequencies = _power_spectrum(centered, sample_rate_hz)
    total_power = float(np.sum(power))
    positive_power = power[1:] if len(power) > 1 else np.array([], dtype=float)
    positive_frequencies = frequencies[1:] if len(frequencies) > 1 else np.array([], dtype=float)

    if len(positive_power) > 0 and float(np.sum(positive_power)) > 0:
        dominant_index = int(np.argmax(positive_power))
        dominant_frequency = float(positive_frequencies[dominant_index])
        probability = positive_power / np.sum(positive_power)
        spectral_entropy = (
            float(
                -np.sum(probability * np.log(probability + np.finfo(float).eps))
                / np.log(len(probability))
            )
            if len(probability) > 1
            else 0.0
        )
        spectral_peak_ratio = float(np.max(positive_power) / np.sum(positive_power))
    else:
        dominant_frequency = 0.0
        spectral_entropy = 0.0
        spectral_peak_ratio = 0.0

    autocorrelation_peak, autocorrelation_lag = _autocorrelation_features(centered, sample_rate_hz)
    return {
        f"{name}_mean": float(np.mean(values)),
        f"{name}_std": float(np.std(values)),
        f"{name}_median": float(np.median(values)),
        f"{name}_iqr": float(q75 - q25),
        f"{name}_min": float(np.min(values)),
        f"{name}_max": float(np.max(values)),
        f"{name}_range": float(np.max(values) - np.min(values)),
        f"{name}_rms": float(np.sqrt(np.mean(np.square(values)))),
        f"{name}_energy": float(np.mean(np.square(values))),
        f"{name}_mean_abs_diff": float(np.mean(np.abs(differences)))
        if len(differences) > 0
        else 0.0,
        f"{name}_zero_cross_rate": float(np.mean(np.diff(np.signbit(centered)) != 0))
        if len(centered) > 1
        else 0.0,
        f"{name}_peak_rate_hz": _peak_rate(values, sample_rate_hz),
        f"{name}_dominant_frequency_hz": dominant_frequency,
        f"{name}_spectral_entropy": spectral_entropy,
        f"{name}_spectral_peak_ratio": spectral_peak_ratio,
        f"{name}_low_band_power": _band_power(power, frequencies, 0.2, 1.5, total_power),
        f"{name}_mid_band_power": _band_power(power, frequencies, 1.5, 4.0, total_power),
        f"{name}_high_band_power": _band_power(
            power, frequencies, 4.0, sample_rate_hz / 2, total_power
        ),
        f"{name}_autocorr_peak": autocorrelation_peak,
        f"{name}_autocorr_lag_seconds": autocorrelation_lag,
    }


def _power_spectrum(values: np.ndarray, sample_rate_hz: int) -> tuple[np.ndarray, np.ndarray]:
    window = np.hanning(len(values))
    transformed = np.fft.rfft(values * window)
    power = np.abs(transformed) ** 2
    frequencies = np.fft.rfftfreq(len(values), d=1 / sample_rate_hz)
    return power, frequencies


def _band_power(
    power: np.ndarray,
    frequencies: np.ndarray,
    lower_hz: float,
    upper_hz: float,
    total_power: float,
) -> float:
    if total_power <= 0:
        return 0.0
    mask = (frequencies >= lower_hz) & (frequencies < upper_hz)
    return float(np.sum(power[mask]) / total_power)


def _peak_rate(values: np.ndarray, sample_rate_hz: int) -> float:
    if len(values) < 3:
        return 0.0
    centered = values - np.median(values)
    threshold = max(float(np.std(centered)) * 0.75, np.finfo(float).eps)
    peaks = (centered[1:-1] > centered[:-2]) & (centered[1:-1] >= centered[2:])
    peaks &= centered[1:-1] > threshold
    duration_seconds = len(values) / sample_rate_hz
    return float(np.sum(peaks) / duration_seconds)


def _autocorrelation_features(values: np.ndarray, sample_rate_hz: int) -> tuple[float, float]:
    denominator = float(np.dot(values, values))
    if denominator <= np.finfo(float).eps:
        return 0.0, 0.0
    correlation = np.correlate(values, values, mode="full")[len(values) - 1 :] / denominator
    minimum_lag = max(1, round(sample_rate_hz * 0.15))
    maximum_lag = min(len(values) // 2, round(sample_rate_hz * 1.5))
    if maximum_lag <= minimum_lag:
        return 0.0, 0.0
    search = correlation[minimum_lag : maximum_lag + 1]
    peak_offset = int(np.argmax(search))
    lag = minimum_lag + peak_offset
    return float(search[peak_offset]), float(lag / sample_rate_hz)


def _safe_correlation(left: np.ndarray, right: np.ndarray) -> float:
    if np.std(left) <= np.finfo(float).eps or np.std(right) <= np.finfo(float).eps:
        return 0.0
    correlation = float(np.corrcoef(left, right)[0, 1])
    return correlation if np.isfinite(correlation) else 0.0
