"""Small command-line entry point for pre-training dataset validation."""

from __future__ import annotations

import argparse
from collections.abc import Sequence
from pathlib import Path

from .schema import DatasetValidationError, load_and_validate_dataset


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="voxa-gesture-validate",
        description="Validate labeled Voxa Cue IMU recorder exports before training.",
    )
    parser.add_argument("csv", nargs="+", type=Path, help="One or more recorder CSV exports")
    return parser


def run(arguments: Sequence[str]) -> int:
    parsed = build_parser().parse_args(list(arguments))
    try:
        _, report = load_and_validate_dataset(parsed.csv)
    except DatasetValidationError as error:
        print(f"ERROR: {error}")
        return 2
    print(report.render())
    return 0 if report.is_trainable else 1


def main() -> None:
    import sys

    raise SystemExit(run(sys.argv[1:]))
