"""Shared deterministic fixtures for the gesture-classifier behavior tests."""

from __future__ import annotations

import pandas as pd
import pytest

from voxa_gesture.synthetic import generate_synthetic_dataset


@pytest.fixture(scope="session")
def synthetic_frame() -> pd.DataFrame:
    """A small, valid dataset with enough independent participant groups for CV."""

    return generate_synthetic_dataset(
        subject_count=3,
        session_count=1,
        trials_per_behavior=3,
        sample_rate_hz=50,
        duration_seconds=4.0,
        random_state=7301,
    )
