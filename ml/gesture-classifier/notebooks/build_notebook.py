"""Generate the checked-in Voxa Gesture Classifier Colab tutorial."""

from __future__ import annotations

from pathlib import Path
from textwrap import dedent

import nbformat
from nbformat import NotebookNode

OUTPUT_PATH = Path(__file__).with_name("Voxa_Gesture_Classifier_Colab.ipynb")


def markdown(source: str) -> NotebookNode:
    """Build one concise tutorial markdown cell."""

    return nbformat.v4.new_markdown_cell(dedent(source).strip())


def code(source: str) -> NotebookNode:
    """Build one deterministic Python cell."""

    return nbformat.v4.new_code_cell(dedent(source).strip())


def build_notebook() -> NotebookNode:
    """Create the complete top-to-bottom tutorial notebook."""

    cells = [
        markdown(
            """
            # Voxa Cue wrist-motion classifier

            ## Goal

            Train a first-pass classifier that separates **rest**, **intentional gesture**,
            and **fidget** from the Nano 33 IoT wrist IMU. This is a behavior classifier,
            not a semantic gesture recognizer.

            Local runs default to `synthetic_demo`; Colab defaults to `uploaded_csv` and
            opens a deliberate file picker. Synthetic results only prove that the pipeline
            runs. They are never product evidence.
            """
        ),
        markdown(
            """
            ## Setup

            The setup cell uses the current checkout when run locally. In Colab it clones
            `amaar-mc/voxa-cue`, then installs the ML package and its pinned interface.
            Raw recordings and model artifacts stay inside the runtime unless you download
            them explicitly.
            """
        ),
        code(
            """
            from __future__ import annotations

            import hashlib
            import importlib.util
            import os
            import shutil
            import subprocess
            import sys
            from pathlib import Path

            REPOSITORY_URL = "https://github.com/amaar-mc/voxa-cue.git"
            COLAB_CHECKOUT = Path("/content/voxa-cue")


            def find_repository_root(start: Path) -> Path | None:
                candidates = (start.resolve(), *start.resolve().parents)
                for candidate in candidates:
                    marker = candidate / "ml" / "gesture-classifier" / "pyproject.toml"
                    if marker.is_file():
                        return candidate
                return None


            repository_root = find_repository_root(Path.cwd())
            if repository_root is None:
                if not (COLAB_CHECKOUT / ".git").is_dir():
                    subprocess.run(
                        ["git", "clone", "--depth", "1", REPOSITORY_URL, str(COLAB_CHECKOUT)],
                        check=True,
                    )
                repository_root = COLAB_CHECKOUT

            ml_root = repository_root / "ml" / "gesture-classifier"
            expected_package = (ml_root / "src" / "voxa_gesture").resolve()
            try:
                import voxa_gesture
            except ModuleNotFoundError:
                package_is_current = False
            else:
                installed_package = Path(voxa_gesture.__file__).resolve().parent
                package_is_current = (
                    installed_package == expected_package
                    and importlib.util.find_spec("skops") is not None
                )

            if not package_is_current:
                if importlib.util.find_spec("pip") is not None:
                    install_command = [
                        sys.executable,
                        "-m",
                        "pip",
                        "install",
                        "-q",
                        "--disable-pip-version-check",
                        "-e",
                        str(ml_root),
                    ]
                elif shutil.which("uv") is not None:
                    install_command = [
                        "uv",
                        "pip",
                        "install",
                        "--python",
                        sys.executable,
                        "-e",
                        str(ml_root),
                    ]
                else:
                    raise RuntimeError("Install pip or uv before running this notebook.")
                subprocess.run(install_command, check=True)

            print(f"Repository: {repository_root}")
            print(f"ML package: {ml_root}")
            """
        ),
        code(
            """
            import json
            from pathlib import Path

            import matplotlib.pyplot as plt
            import seaborn as sns
            from IPython.display import FileLink, display
            from sklearn.metrics import ConfusionMatrixDisplay

            from voxa_gesture.artifact import (
                MINIMUM_MACRO_F1_UPLIFT,
                dataset_sha256,
                export_model_bundle,
                require_export_ready_model,
            )
            from voxa_gesture.features import (
                WindowConfig,
                extract_window_features,
                model_feature_columns,
            )
            from voxa_gesture.modeling import evaluate_grouped_baselines, fit_selected_model
            from voxa_gesture.schema import DatasetValidationError, load_and_validate_dataset
            from voxa_gesture.synthetic import write_synthetic_dataset

            sns.set_theme(style="whitegrid", context="notebook")

            google_package_available = importlib.util.find_spec("google") is not None
            running_in_colab = (
                google_package_available
                and importlib.util.find_spec("google.colab") is not None
            )
            default_data_mode = "uploaded_csv" if running_in_colab else "synthetic_demo"
            DATA_MODE = os.environ.get("VOXA_DATA_MODE", default_data_mode)
            RANDOM_STATE = 42
            MODEL_SAMPLE_RATE_HZ = 50
            WINDOW_SECONDS = 2.0
            HOP_SECONDS = 0.5
            REJECTION_THRESHOLD = 0.65

            allowed_modes = {"synthetic_demo", "uploaded_csv"}
            if DATA_MODE not in allowed_modes:
                raise ValueError(f"DATA_MODE must be one of {sorted(allowed_modes)}")

            window_config = WindowConfig(
                sample_rate_hz=MODEL_SAMPLE_RATE_HZ,
                window_seconds=WINDOW_SECONDS,
                hop_seconds=HOP_SECONDS,
            )
            """
        ),
        markdown(
            """
            ## Steps

            ### 1. Load labeled recordings

            `synthetic_demo` creates deterministic, deliberately separable fixture data.
            Colab selects `uploaded_csv` automatically and opens a file picker. For a local
            real-data run, launch the notebook kernel with
            `VOXA_DATA_MODE=uploaded_csv`; it reads CSV files in `data/raw`. Do not edit a
            code cell to change modes. Start a fresh kernel and run all cells in order so
            the export gate can verify the executed code against Git `HEAD`.
            """
        ),
        code(
            """
            raw_directory = ml_root / "data" / "raw"
            raw_directory.mkdir(parents=True, exist_ok=True)

            if DATA_MODE == "synthetic_demo":
                dataset_paths = [
                    write_synthetic_dataset(
                        path=raw_directory / "SYNTHETIC_DEMO_NOT_EVIDENCE.csv",
                        subject_count=3,
                        session_count=2,
                        trials_per_behavior=4,
                        sample_rate_hz=50,
                        duration_seconds=4.0,
                        random_state=RANDOM_STATE,
                    )
                ]
                evidence_label = "SYNTHETIC DEMO — PIPELINE CHECK ONLY"
            else:
                try:
                    from google.colab import files
                except ModuleNotFoundError:
                    dataset_paths = sorted(
                        path
                        for path in raw_directory.glob("*.csv")
                        if "SYNTHETIC" not in path.name.upper()
                    )
                else:
                    uploaded = files.upload()
                    dataset_paths = []
                    for filename, contents in uploaded.items():
                        output_path = raw_directory / Path(filename).name
                        output_path.write_bytes(contents)
                        dataset_paths.append(output_path)
                if not dataset_paths:
                    raise FileNotFoundError(
                        "No real recorder CSVs were provided. "
                        "Export trials from the browser recorder first."
                    )
                evidence_label = "REAL RECORDER DATA — GROUPED DEVELOPMENT EVALUATION"

            print(evidence_label)
            print("Inputs:")
            for dataset_path in dataset_paths:
                print(f"- {dataset_path.name}")
            """
        ),
        markdown(
            """
            ### 2. Validate before modeling

            Validation rejects malformed rows, mixed trial labels, non-monotonic timestamps,
            invalid prompt times, implausible sensor values, unhealthy packets, and
            excessive packet loss. Warnings remain visible because small or weakly grouped
            datasets can run but cannot support strong claims.
            """
        ),
        code(
            """
            samples, quality_report = load_and_validate_dataset(dataset_paths)
            print(quality_report.render())
            if quality_report.errors:
                raise DatasetValidationError(
                    "Fix the dataset errors before training.\\n" + quality_report.render()
                )

            trial_labels = samples[
                ["subject_id", "session_id", "trial_id", "behavior", "subtype"]
            ].drop_duplicates()
            behavior_order = ["rest", "intentional_gesture", "fidget"]

            figure, axis = plt.subplots(figsize=(8, 3.6))
            sns.countplot(
                data=trial_labels,
                x="behavior",
                order=behavior_order,
                color="#0b756f",
                ax=axis,
            )
            axis.set(title=f"Trial balance · {evidence_label}", xlabel="Behavior", ylabel="Trials")
            axis.tick_params(axis="x", rotation=12)
            plt.tight_layout()
            plt.show()
            """
        ),
        markdown(
            """
            ### 3. Build causal windows and features

            Each trial is resampled independently to 50 Hz. The extractor creates two-second
            windows every 0.5 seconds, then calculates motion magnitude, variation, frequency,
            periodicity, activity, and axis-correlation features. It never creates a window
            across a trial boundary.

            Every behavior is visually prompted about 1.5 seconds into its four-second trial.
            The extractor keeps only windows ending 350-1,100 ms after the recorded prompt for
            all three classes. Equal alignment prevents the model from learning label-specific
            timing and removes clearly pre/post-prompt windows. The visual prompt is
            not a measured motion-onset annotation, so mistimed responses must still be retried.
            """
        ),
        code(
            """
            features = extract_window_features(samples, window_config)
            sensor_feature_columns = model_feature_columns(features)

            print(f"Windows: {len(features):,}")
            print(f"Trials represented: {features['trial_id'].nunique():,}")
            print(f"Sensor-derived features: {len(sensor_feature_columns):,}")
            print(
                "Window span:",
                f"{features['window_start_ms'].min():.0f}-"
                f"{features['window_end_ms'].max():.0f} ms",
            )
            display(
                features.groupby("behavior", as_index=False)
                .agg(windows=("window_index", "size"), trials=("trial_id", "nunique"))
                .sort_values("behavior")
            )

            forbidden_model_columns = {
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
            }
            assert forbidden_model_columns.isdisjoint(sensor_feature_columns)
            """
        ),
        markdown(
            """
            ### 4. Compare grouped baselines

            - Three or more participants: hold participant groups apart.
            - One or two participants with three or more sessions: hold complete sessions apart.

            Overlapping windows are correlated, so random window splitting would leak nearly
            identical motion into training and evaluation. The primary metric is macro F1;
            balanced accuracy and gesture/fidget crossover rates are shown beside it.
            """
        ),
        code(
            """
            if quality_report.subject_count >= 3:
                group_column = "participant_group"
                evaluation_scope = "held-out participant groups"
            elif quality_report.session_count >= 3:
                group_column = "session_group"
                evaluation_scope = "held-out sessions; personalized evidence only"
            else:
                raise ValueError(
                    "Collect at least three participants or three separate sessions "
                    "before evaluation."
                )

            evaluation = evaluate_grouped_baselines(
                features=features,
                target_column="behavior",
                group_column=group_column,
                random_state=RANDOM_STATE,
            )

            print(evidence_label)
            print(f"Split scope: {evaluation_scope}")
            print("These are grouped development metrics, not an untouched final test.")
            display(evaluation.summary.round(3))
            """
        ),
        code(
            """
            selected_name = evaluation.selected_model_name
            selected_windows = evaluation.window_predictions.query("model == @selected_name")
            selected_trials = evaluation.trial_predictions.query("model == @selected_name")

            figure, axes = plt.subplots(1, 2, figsize=(12, 4.4))
            for axis, predictions, level in (
                (axes[0], selected_windows, "Window"),
                (axes[1], selected_trials, "Trial vote"),
            ):
                ConfusionMatrixDisplay.from_predictions(
                    predictions["actual"],
                    predictions["predicted"],
                    labels=list(evaluation.labels),
                    normalize="true",
                    values_format=".2f",
                    colorbar=False,
                    cmap="GnBu",
                    ax=axis,
                )
                axis.set_title(f"{level} confusion")
                axis.tick_params(axis="x", rotation=25)
            figure.suptitle(f"{selected_name} · {evidence_label}", y=1.03)
            plt.tight_layout()
            plt.show()
            """
        ),
        markdown(
            """
            ## Checks

            The selected model must be read against the dummy baseline. Strong synthetic
            separation is expected and has no real-world meaning. For real data, inspect the
            fidget/gesture crossover rates and confusion plots before accepting aggregate scores.
            """
        ),
        code(
            """
            selected_metrics = evaluation.summary.query("model == @selected_name").iloc[0]
            dummy_metrics = evaluation.summary.query("model == 'dummy_prior'").iloc[0]
            macro_f1_uplift = float(
                selected_metrics["window_macro_f1"] - dummy_metrics["window_macro_f1"]
            )

            print(evidence_label)
            print(f"Selected model: {selected_name}")
            print(f"Window macro F1 uplift over dummy: {macro_f1_uplift:+.3f}")
            print(
                "Gesture→fidget error:",
                f"{float(selected_metrics['gesture_as_fidget_rate']):.1%}",
            )
            print(
                "Fidget→gesture error:",
                f"{float(selected_metrics['fidget_as_gesture_rate']):.1%}",
            )
            if macro_f1_uplift <= MINIMUM_MACRO_F1_UPLIFT:
                print(
                    "EXPORT BLOCKED: collect or relabel data; the model must exceed "
                    f"dummy macro F1 by more than {MINIMUM_MACRO_F1_UPLIFT:.2f}."
                )
            if DATA_MODE == "synthetic_demo":
                print("SYNTHETIC METRICS ARE NOT A PERFORMANCE CLAIM.")
            else:
                print("Reserve untouched natural-presentation sessions before any product claim.")
            """
        ),
        markdown(
            """
            ### 5. Fit and export the development artifact

            Export is blocked unless a non-dummy model exceeds dummy window macro F1 by more
            than 0.05. Real-data export also requires a clean Git checkout. Synthetic runs may
            export from a dirty checkout because their model card records the exact revision,
            dirty state, and deterministic source-diff hash. `.skops` avoids an opaque pickle,
            but the artifact must still be treated as untrusted input until reviewed.
            """
        ),
        code(
            """
            export_uplift = require_export_ready_model(
                evaluation.summary,
                selected_name,
            )


            def git_output(repository: Path, arguments: list[str]) -> bytes:
                result = subprocess.run(
                    ["git", "-C", str(repository), *arguments],
                    check=True,
                    capture_output=True,
                )
                return result.stdout


            def code_cell_sha256(cell_sources: list[str]) -> str:
                digest = hashlib.sha256()
                digest.update(b"voxa-notebook-code-v1\\0")
                for source in cell_sources:
                    normalized = source.replace("\\r\\n", "\\n").strip().encode("utf-8")
                    digest.update(len(normalized).to_bytes(8, "big"))
                    digest.update(normalized)
                return digest.hexdigest()


            def notebook_cell_source(cell: dict[str, object]) -> str:
                source = cell["source"]
                if isinstance(source, str):
                    return source
                if isinstance(source, list) and all(isinstance(line, str) for line in source):
                    return "".join(source)
                raise RuntimeError("Notebook code cell source has an unsupported shape.")


            notebook_relative_path = (
                "ml/gesture-classifier/notebooks/Voxa_Gesture_Classifier_Colab.ipynb"
            )
            notebook_at_head = subprocess.run(
                ["git", "-C", str(repository_root), "show", f"HEAD:{notebook_relative_path}"],
                check=False,
                capture_output=True,
            )
            if notebook_at_head.returncode != 0:
                if DATA_MODE == "uploaded_csv":
                    raise RuntimeError(
                        "Real-data export requires the notebook to exist at Git HEAD. "
                        "Commit the generated notebook before training."
                    )
                repository_notebook_bytes = (
                    ml_root / "notebooks" / "Voxa_Gesture_Classifier_Colab.ipynb"
                ).read_bytes()
            else:
                repository_notebook_bytes = notebook_at_head.stdout

            repository_notebook = json.loads(repository_notebook_bytes.decode("utf-8"))
            repository_code_cells = [
                notebook_cell_source(cell)
                for cell in repository_notebook["cells"]
                if cell["cell_type"] == "code"
            ]
            shell = get_ipython()
            if shell is None:
                raise RuntimeError("Notebook execution provenance requires an IPython kernel.")
            execution_history = shell.user_ns.get("In")
            if not isinstance(execution_history, list) or len(execution_history) <= 1:
                raise RuntimeError("Notebook execution history is unavailable.")
            execution_code_cells = [str(source) for source in execution_history[1:]]
            execution_notebook_sha256 = code_cell_sha256(execution_code_cells)
            repository_notebook_sha256 = code_cell_sha256(repository_code_cells)
            execution_notebook_matches_repository = (
                execution_notebook_sha256 == repository_notebook_sha256
            )
            if DATA_MODE == "uploaded_csv" and not execution_notebook_matches_repository:
                raise RuntimeError(
                    "Real-data export requires a fresh kernel and an unedited Run All of "
                    "the notebook at Git HEAD."
                )


            revision_bytes = git_output(repository_root, ["rev-parse", "--verify", "HEAD"])
            source_revision = revision_bytes.decode("ascii").strip()
            status_bytes = git_output(
                repository_root,
                [
                    "status",
                    "--porcelain=v1",
                    "--untracked-files=all",
                    "-z",
                    "--",
                    ".",
                    f":(exclude){notebook_relative_path}",
                ],
            )
            source_dirty = len(status_bytes) > 0
            source_diff_sha256 = None
            if source_dirty:
                tracked_diff = git_output(
                    repository_root,
                    [
                        "diff",
                        "--binary",
                        "--full-index",
                        "--no-color",
                        "--no-ext-diff",
                        "--no-textconv",
                        "HEAD",
                        "--",
                        ".",
                        f":(exclude){notebook_relative_path}",
                    ],
                )
                untracked_output = git_output(
                    repository_root,
                    [
                        "ls-files",
                        "--others",
                        "--exclude-standard",
                        "-z",
                        "--",
                        ".",
                        f":(exclude){notebook_relative_path}",
                    ],
                )
                untracked_paths = sorted(
                    path_bytes
                    for path_bytes in untracked_output.split(b"\\0")
                    if path_bytes
                )

                source_digest = hashlib.sha256()
                source_digest.update(b"voxa-source-diff-v1\\0")
                source_digest.update(len(tracked_diff).to_bytes(8, "big"))
                source_digest.update(tracked_diff)
                for path_bytes in untracked_paths:
                    source_path = repository_root / os.fsdecode(path_bytes)
                    if source_path.is_symlink():
                        content_bytes = os.fsencode(os.readlink(source_path))
                    else:
                        content_bytes = source_path.read_bytes()
                    source_digest.update(b"untracked\\0")
                    source_digest.update(len(path_bytes).to_bytes(8, "big"))
                    source_digest.update(path_bytes)
                    source_digest.update(len(content_bytes).to_bytes(8, "big"))
                    source_digest.update(content_bytes)
                source_diff_sha256 = source_digest.hexdigest()

            if DATA_MODE == "uploaded_csv" and source_dirty:
                raise RuntimeError(
                    "Real-data artifact export requires a clean Git checkout. "
                    "Commit or stash source changes, rerun from the top, and export again."
                )

            fitted_model = fit_selected_model(
                features=features,
                target_column="behavior",
                model_name=selected_name,
                random_state=RANDOM_STATE,
            )

            print(f"Export gate uplift over dummy: {export_uplift:+.3f}")
            print(f"Source revision: {source_revision}")
            print(f"Source dirty: {source_dirty}")
            print(f"Executed notebook SHA-256: {execution_notebook_sha256}")
            print(f"Notebook matches Git HEAD: {execution_notebook_matches_repository}")
            if source_diff_sha256 is not None:
                print(f"Source diff SHA-256: {source_diff_sha256}")

            artifact_directory = ml_root / "data" / "artifacts"
            model_path, model_card_path = export_model_bundle(
                estimator=fitted_model,
                window_config=window_config,
                output_directory=artifact_directory,
                model_name=selected_name,
                feature_columns=evaluation.feature_columns,
                labels=evaluation.labels,
                metrics=evaluation.summary,
                dataset_hash=dataset_sha256(dataset_paths),
                source_revision=source_revision,
                source_dirty=source_dirty,
                source_diff_sha256=source_diff_sha256,
                execution_notebook_sha256=execution_notebook_sha256,
                repository_notebook_sha256=repository_notebook_sha256,
                rejection_threshold=REJECTION_THRESHOLD,
            )

            model_card = json.loads(model_card_path.read_text(encoding="utf-8"))
            model_card["data_mode"] = DATA_MODE
            model_card["evaluation_scope"] = evaluation_scope
            model_card["prompt_alignment"] = (
                "All behavior windows end 350-1100 ms after each recorded visual prompt. "
                "Actual motion onset is not measured."
            )
            model_card["evidence_status"] = (
                "synthetic_demo_not_evidence"
                if DATA_MODE == "synthetic_demo"
                else "grouped_development_evaluation_not_untouched_test"
            )
            model_card_path.write_text(
                json.dumps(model_card, indent=2, sort_keys=True) + "\\n",
                encoding="utf-8",
            )

            print(evidence_label)
            print("Development artifact created. It is not approved for the iOS live path.")
            display(FileLink(str(model_path)))
            display(FileLink(str(model_card_path)))
            display(model_card)
            """
        ),
        markdown(
            """
            ## Next steps

            1. Replace synthetic fixtures with balanced, pseudonymous recorder exports.
            2. Repeat collection across separate days and presentation topics.
            3. Keep entire people or sessions out of each evaluation fold.
            4. Evaluate on untouched natural presentations and measure false alerts per hour.
            5. Tune rejection, temporal smoothing, and event latency before Core ML conversion.
            6. Add a second hierarchical model for gesture subtype only after the three-class
               behavior model works on held-out real sessions.

            A single wrist IMU observes movement, not intent, the other hand, or whether a
            gesture matched the spoken idea. Do not describe this artifact as semantic gesture
            understanding.
            """
        ),
    ]

    for index, cell in enumerate(cells):
        cell["id"] = f"voxa-{index:02d}"

    notebook = nbformat.v4.new_notebook(cells=cells)
    notebook.metadata = {
        "colab": {"name": OUTPUT_PATH.name, "provenance": []},
        "kernelspec": {
            "display_name": "Python 3",
            "language": "python",
            "name": "python3",
        },
        "language_info": {"name": "python", "version": "3.11"},
    }
    return notebook


def main() -> None:
    """Write a stable, unexecuted notebook for Git and Colab."""

    notebook = build_notebook()
    nbformat.validate(notebook)
    nbformat.write(notebook, OUTPUT_PATH)
    print(f"Wrote {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
