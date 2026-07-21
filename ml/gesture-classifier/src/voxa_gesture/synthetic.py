"""Deterministic fixtures for tests and notebook execution, never product evidence."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd

from .schema import SCHEMA_VERSION

BEHAVIOR_SUBTYPES = {
    "rest": ("still",),
    "intentional_gesture": ("beat", "open_palm", "point", "sweep"),
    "fidget": ("wrist_twist", "strap_touch", "object_fidget", "hand_clasp"),
}


def generate_synthetic_dataset(
    subject_count: int,
    session_count: int,
    trials_per_behavior: int,
    sample_rate_hz: int,
    duration_seconds: float,
    random_state: int,
) -> pd.DataFrame:
    """Create separable but imperfect motion fixtures for pipeline smoke tests."""

    if min(subject_count, session_count, trials_per_behavior, sample_rate_hz) <= 0:
        raise ValueError("Synthetic dataset counts and sample rate must be positive.")
    if duration_seconds < 2:
        raise ValueError("Synthetic trials must be at least two seconds long.")

    generator = np.random.default_rng(random_state)
    sample_count = round(sample_rate_hz * duration_seconds)
    elapsed_seconds = np.arange(sample_count, dtype=float) / sample_rate_hz
    rows: list[dict[str, float | int | str | bool]] = []
    sequence = 0
    device_start_ms = 10_000

    for subject_index in range(subject_count):
        subject_id = f"SYN_P{subject_index + 1:02d}"
        for session_index in range(session_count):
            session_id = f"SYN_D{session_index + 1:02d}"
            for behavior, subtypes in BEHAVIOR_SUBTYPES.items():
                for repetition in range(1, trials_per_behavior + 1):
                    subtype = subtypes[(repetition - 1) % len(subtypes)]
                    trial_id = f"{subject_id}_{session_id}_{behavior}_{repetition:03d}"
                    acceleration, gyro = _synthetic_motion(
                        behavior,
                        subtype,
                        elapsed_seconds,
                        subject_index,
                        session_index,
                        generator,
                    )
                    for sample_index in range(sample_count):
                        sequence = (sequence + 1) % 65_536
                        elapsed_ms = round(elapsed_seconds[sample_index] * 1_000)
                        rows.append(
                            {
                                "schema_version": SCHEMA_VERSION,
                                "subject_id": subject_id,
                                "session_id": session_id,
                                "trial_id": trial_id,
                                "trial_started_at_utc": (
                                    f"2026-01-{session_index + 1:02d}T12:00:00+00:00"
                                ),
                                "behavior": behavior,
                                "subtype": subtype,
                                "wrist": "right" if subject_index % 2 == 0 else "left",
                                "orientation": "usb_toward_elbow",
                                "repetition": repetition,
                                "prompt_event_ms": 1_500,
                                "device_ms": device_start_ms + elapsed_ms,
                                "sequence": sequence,
                                "sample_index": sample_index,
                                "elapsed_ms": elapsed_ms,
                                "host_elapsed_ms": elapsed_ms,
                                "accel_x_g": acceleration[sample_index, 0],
                                "accel_y_g": acceleration[sample_index, 1],
                                "accel_z_g": acceleration[sample_index, 2],
                                "gyro_x_dps": gyro[sample_index, 0],
                                "gyro_y_dps": gyro[sample_index, 1],
                                "gyro_z_dps": gyro[sample_index, 2],
                                "sensor_kind": "LSM6 family",
                                "sensor_address": "0x6A",
                                "firmware": "1.1",
                                "target_sample_rate_hz": sample_rate_hz,
                                "healthy": True,
                            }
                        )
                    device_start_ms += round(duration_seconds * 1_000) + 500
    return pd.DataFrame(rows)


def write_synthetic_dataset(
    path: Path,
    subject_count: int,
    session_count: int,
    trials_per_behavior: int,
    sample_rate_hz: int,
    duration_seconds: float,
    random_state: int,
) -> Path:
    """Write a labeled fixture whose filename makes its non-real status explicit."""

    frame = generate_synthetic_dataset(
        subject_count,
        session_count,
        trials_per_behavior,
        sample_rate_hz,
        duration_seconds,
        random_state,
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(path, index=False)
    return path


def _synthetic_motion(
    behavior: str,
    subtype: str,
    elapsed_seconds: np.ndarray,
    subject_index: int,
    session_index: int,
    generator: np.random.Generator,
) -> tuple[np.ndarray, np.ndarray]:
    sample_count = len(elapsed_seconds)
    gravity = np.tile(np.array([0.0, 0.0, 1.0]), (sample_count, 1))
    acceleration = gravity + generator.normal(0, 0.009, size=(sample_count, 3))
    gyro = generator.normal(0, 1.8, size=(sample_count, 3))

    subject_scale = 0.88 + subject_index * 0.07
    session_scale = 0.94 + session_index * 0.04
    scale = subject_scale * session_scale
    if behavior == "intentional_gesture":
        center = 1.6 + generator.uniform(-0.25, 0.25)
        width = 0.28 + generator.uniform(0.02, 0.18)
        envelope = np.exp(-0.5 * np.square((elapsed_seconds - center) / width))
        gesture_frequency = {
            "beat": 1.2,
            "open_palm": 0.7,
            "point": 1.0,
            "sweep": 0.55,
        }[subtype]
        wave = np.sin(2 * np.pi * gesture_frequency * (elapsed_seconds - center))
        acceleration[:, 0] += scale * 0.42 * envelope * wave
        acceleration[:, 1] += scale * 0.25 * envelope
        gyro[:, 1] += scale * 150 * envelope * wave
        gyro[:, 2] += scale * 105 * envelope
    elif behavior == "fidget":
        fidget_frequency = {
            "wrist_twist": 2.4,
            "strap_touch": 3.3,
            "object_fidget": 4.1,
            "hand_clasp": 1.8,
        }[subtype]
        center = 1.65 + generator.uniform(-0.12, 0.12)
        width = 0.38 + generator.uniform(0.04, 0.14)
        envelope = np.exp(-0.5 * np.square((elapsed_seconds - center) / width))
        phase = generator.uniform(0, 2 * np.pi)
        periodic = envelope * np.sin(2 * np.pi * fidget_frequency * elapsed_seconds + phase)
        harmonic = envelope * np.sin(4 * np.pi * fidget_frequency * elapsed_seconds + phase / 2)
        acceleration[:, 0] += scale * (0.065 * periodic + 0.025 * harmonic)
        acceleration[:, 2] += scale * 0.04 * periodic
        gyro[:, 0] += scale * 38 * periodic
        gyro[:, 2] += scale * 24 * harmonic
    elif behavior != "rest":
        raise ValueError(f"Unknown synthetic behavior: {behavior}")

    rotation = _random_rotation(generator)
    return acceleration @ rotation.T, gyro @ rotation.T


def _random_rotation(generator: np.random.Generator) -> np.ndarray:
    angles = generator.normal(0, 0.12, size=3)
    cx, cy, cz = np.cos(angles)
    sx, sy, sz = np.sin(angles)
    rotation_x = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    rotation_y = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    rotation_z = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return np.asarray(rotation_z @ rotation_y @ rotation_x, dtype=float)
