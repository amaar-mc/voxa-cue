"""Regenerate and execute the checked-in synthetic tutorial notebook."""

from __future__ import annotations

import json
import os
from pathlib import Path

import nbformat
from build_notebook import OUTPUT_PATH, build_notebook
from nbclient import NotebookClient
from nbformat import NotebookNode


def repository_root(script_path: Path) -> Path:
    """Resolve the repository without depending on the caller's directory."""

    root = script_path.resolve().parents[3]
    if not (root / "ml" / "gesture-classifier" / "pyproject.toml").is_file():
        raise FileNotFoundError("Could not locate the Voxa Cue repository root.")
    return root


def verify_generated_notebook_matches() -> NotebookNode:
    """Fail when the readable builder and checked-in notebook diverge."""

    generated = build_notebook()
    nbformat.validate(generated)
    checked_in = nbformat.read(OUTPUT_PATH, as_version=4)
    nbformat.validate(checked_in)
    if nbformat.writes(generated) != nbformat.writes(checked_in):
        raise RuntimeError("The checked-in notebook is stale. Run notebooks/build_notebook.py.")
    return checked_in


def execute_synthetic_notebook(
    notebook: NotebookNode,
    execution_directory: Path,
) -> None:
    """Execute every cell with the deterministic synthetic mode enabled."""

    code_source = "\n".join(str(cell.source) for cell in notebook.cells if cell.cell_type == "code")
    if 'os.environ.get("VOXA_DATA_MODE"' not in code_source:
        raise RuntimeError("Notebook data mode must come from the execution environment.")

    os.environ["MPLBACKEND"] = "Agg"
    os.environ["VOXA_DATA_MODE"] = "synthetic_demo"
    client = NotebookClient(
        notebook,
        timeout=300,
        kernel_name="python3",
        resources={"metadata": {"path": str(execution_directory)}},
        allow_errors=False,
    )
    executed = client.execute()
    executed_code_cells = [cell for cell in executed.cells if cell.cell_type == "code"]
    if any(cell.execution_count is None for cell in executed_code_cells):
        raise RuntimeError("At least one notebook code cell did not execute.")
    model_card_path = (
        execution_directory / "ml" / "gesture-classifier" / "data" / "artifacts" / "model-card.json"
    )
    model_card = json.loads(model_card_path.read_text(encoding="utf-8"))
    if model_card["execution_notebook_matches_repository"] is not True:
        raise RuntimeError("Executed notebook code does not match the generated notebook.")


def main() -> None:
    """Validate source parity and the complete synthetic execution path."""

    root = repository_root(Path(__file__))
    notebook = verify_generated_notebook_matches()
    execute_synthetic_notebook(notebook, root)
    print(f"Notebook passed: {len(notebook.cells)} cells, synthetic_demo, top-to-bottom execution.")


if __name__ == "__main__":
    main()
