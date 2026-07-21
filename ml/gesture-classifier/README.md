# Voxa Gesture Classifier Lab

This lab records the Nano 33 IoT wrist IMU and trains an experimental classifier
for three behaviors:

- `rest`: the recorded wrist remains relaxed while the presenter speaks.
- `intentional_gesture`: one deliberate emphasis gesture, followed by rest.
- `fidget`: a brief self-directed movement not intended as audience emphasis.

The first model answers **gesture, fidget, or rest**. It does not know what a
gesture means. Subtype labels such as `open_palm` and `strap_touch` are retained
for a later hierarchical model, but they are not the v1 prediction target.

The ML lab is isolated from the production iOS and wearable paths. The recorder
never records audio, uploads samples, or changes live haptic decisions. If the
researcher chooses the optional Colab workflow, selecting files explicitly
uploads those CSVs to a Google-hosted runtime for that training session.

## System boundary

```text
Nano 33 IoT onboard LSM6DS3
  → standalone 50 Hz BLE diagnostic firmware
  → Chrome recorder with prompted labels
  → local schema-v1 CSV + manifest
  → validation → 2.0 s windows / 0.5 s hop
  → grouped dummy / logistic / random-forest evaluation
  → .skops model + JSON model card
```

The Nano 33 IoT includes a six-axis LSM6DS3 accelerometer and gyroscope. No
external IMU or A4/A5 wiring is required for this lab. The DRV2605L may remain on
the same I2C bus, but keep haptics idle during capture so the motor does not become
a label shortcut. The lab firmware uses the LSM6 accelerometer's ±4 g range to
avoid clipping ordinary fast gestures. See the [Nano 33 IoT hardware documentation][nano] and the
[official Arduino LSM6DS3 library][lsm-library].

## Record a dataset

### 1. Flash the standalone IMU firmware

Flashing this sketch temporarily replaces the wearable firmware. First find the
connected Nano port:

```sh
ls /dev/cu.usbmodem*
```

From the repository root, test, build, and upload. Replace the example port with
the one printed above.

```sh
uvx --with pip platformio test -e native -d firmware/imu-diagnostic
uvx --with pip platformio run -e nano_33_iot -d firmware/imu-diagnostic
uvx --with pip platformio run -e nano_33_iot -d firmware/imu-diagnostic \
  --target upload --upload-port /dev/cu.usbmodem1101
```

Power the Nano by battery or USB. The BLE device advertises as `Voxa IMU Lab`.
For final data, battery power is preferable because a USB cable changes wrist
motion.

### 2. Open the labeled recorder

Desktop Chrome is required. Web Bluetooth is not available in Safari or an
iPhone browser. The browser asks for the BLE device after a user click; there is
no OS-level pairing step.

```sh
ml/gesture-classifier/recorder/serve.sh
```

In Chrome:

1. Select **Connect Nano**, then choose **Voxa IMU Lab**.
2. Confirm the sensor reads `LSM6 family`, address `0x6A`, and the stream is
   healthy.
3. Enter a pseudonymous participant ID such as `P001`, a session ID such as
   `D01`, wrist, and fixed band orientation.
4. Build a randomized plan. Follow the prompt only after the three-second
   countdown.
5. Stay relaxed until the timed prompt appears about 1.5 seconds into capture.
   Follow it once: **Stay still**, **Gesture now**, or **Fidget now**.
6. Retry any trial flagged for packet loss, short duration, or sensor faults.
7. Export both the CSV and manifest. Place them under
   `ml/gesture-classifier/data/raw/`.

Samples stay in browser memory until export. The raw, processed, and artifact
directories are Git-ignored.

### 3. Restore the wearable firmware

After collection, restore haptics with the same physical port:

```sh
uvx --with pip platformio run -e nano_33_iot -d firmware/voxa-wearable \
  --target upload --upload-port /dev/cu.usbmodem1101
```

## Collection protocol

Use the same band, wrist, orientation, and strap tightness within a session.
Speak naturally during every trial. Change presentation topics across sessions
so the classifier does not memorize one delivery routine.

Each accepted trial is four seconds at a 50 Hz BLE target. The recorder shuffles
the prompts to reduce fatigue and ordering bias. The exported long-format CSV
contains one row per IMU packet and records participant, session, trial, label,
subtype, mount, timestamps, sequence, six sensor axes, sensor identity, firmware,
sample-rate target, health state, and the visual motion-prompt time.
`schemas/recording-v1.schema.json` is the normative row contract.

All behaviors use identical prompt timing. Labeling every two-second window in a
four-second trial would contaminate brief-motion classes with surrounding rest
and give classes different temporal shortcuts. The recorder stores the actual
`prompt_event_ms`, and the extractor retains only windows ending 350-1,100 ms
after that prompt for every behavior. This creates the same number and timing of
candidate windows per accepted trial. It does not measure the participant's true
reaction time or motion onset, so retry a trial when the requested behavior did
not closely follow the visual cue.

Collect these motions:

| Behavior | Include | Avoid |
| --- | --- | --- |
| Rest | Speaking with the recorded wrist relaxed | Holding the wrist unnaturally rigid |
| Intentional gesture | One beat, open palm, point, sweep, or count motion | Repeating the motion for the full trial |
| Fidget | Wrist twist, strap touch, hand clasp, object fidget, or self-touch | Deliberate audience emphasis |

Ambiguous or mistimed trials should be retried, not forced into a label. Capture
hard negatives: small intentional gestures, fast intentional gestures, slow
fidgets, and brief strap touches. They define the boundary the model actually
needs to learn.

Class balance matters. The recorder automatically gives each selected top-level
behavior the same number of trials. When one behavior has fewer selected
subtypes, its motions repeat more often so `rest`, `intentional_gesture`, and
`fidget` remain balanced.

Recommended minimums:

- Personalized prototype: one participant, at least three sessions on separate
  days, with at least 20 accepted trials per behavior overall. Evaluate by whole
  session only.
- Cross-person prototype: at least eight participants and three sessions per
  participant, with balanced behavior totals. Evaluate by whole participant.
- Product claim: additionally reserve natural presentations that are never used
  for feature or model selection. Measure event precision/recall, false alerts
  per hour, and detection latency there.

These are engineering gates, not evidence that eight people are sufficient for
a population claim.

## Validate and train

Install with `uv`, then reject broken captures before opening the notebook:

```sh
uv sync --project ml/gesture-classifier --group dev
uv run --project ml/gesture-classifier voxa-gesture-validate \
  ml/gesture-classifier/data/raw/*.csv
```

Generate the checked-in notebook from its readable source:

```sh
uv run --project ml/gesture-classifier python \
  ml/gesture-classifier/notebooks/build_notebook.py
```

Verify that the generated file is current and execute every cell headlessly in
the explicitly synthetic mode:

```sh
uv run --project ml/gesture-classifier python \
  ml/gesture-classifier/notebooks/verify_notebook.py
```

Open [Voxa_Gesture_Classifier_Colab.ipynb][notebook] locally, or launch it in
[Google Colab][colab]. Local runs start in `synthetic_demo`; those metrics are
only an execution check. Colab selects `uploaded_csv` automatically and opens a
file picker. For local real-data training, launch the notebook kernel with
`VOXA_DATA_MODE=uploaded_csv` and place recorder exports in `data/raw`. Use a
fresh kernel and **Run All** without editing code cells. The artifact gate hashes
the executed cells and requires them to match the notebook at Git `HEAD`.

The notebook:

1. validates schema, prompt timing, packet continuity, health, ranges, and class
   counts;
2. resamples each trial independently to 50 Hz;
3. extracts causal two-second windows every 0.5 seconds;
4. compares a prior-only dummy, class-balanced logistic regression, and a
   400-tree class-balanced random forest;
5. selects by grouped window macro F1, then trial macro F1;
6. displays normalized window and trial-vote confusion matrices;
7. refuses export unless the selected model beats the dummy by more than 0.05
   macro F1, then fits the approved development model and exports
   `voxa_gesture_classifier_v1.skops` plus `model-card.json`.

Random forest is a good small-data baseline for nonlinear tabular motion
features. It is being compared, not assumed to win. A deep sequence model is not
justified until substantially more labeled, independent data exists. See the
[scikit-learn random-forest guide][random-forest].

## Leakage and evidence rules

Overlapping windows from one performance are highly correlated. Never use a
random window split. The notebook uses
[`StratifiedGroupKFold`][grouped-cv] with complete participants held out when at
least three participants exist; otherwise it holds complete sessions out and
labels the result personalized evidence. Research has demonstrated that window
overlap can inflate human-activity recognition evaluation when correlated
samples cross folds [in this validation study][overlap-study].

Grouped cross-validation is still development evidence because it also chooses
the model. Keep an untouched natural-presentation set for the final decision.
Do not report synthetic scores, in-sample scores, or session-grouped scores as
cross-person performance.

The `.skops` artifact records the dataset SHA-256, source revision and dirty-tree
state, executed and repository notebook hashes, exact feature order, all
candidate metrics, the dummy-baseline uplift gate, labels, dependency versions,
and limitations. Review
unknown types before loading any artifact obtained from another person, as
described in the [skops persistence documentation][skops]. The model remains out
of the iOS live path until event-level validation and Core ML parity tests pass.

## Privacy and limits

- Use IDs, never names, emails, or participant notes in filenames or labels.
- Obtain consent before recording or sharing movement data.
- Keep CSVs local by default. Optional Colab training deliberately uploads
  selected CSVs to a Google-hosted runtime; obtain consent for that transfer and
  delete runtime files afterward. Delete local exports and artifacts when
  consent is withdrawn.
- Do not record raw audio or video through this lab.
- A single wrist IMU cannot observe the other hand, body position, eye contact,
  audience response, or semantic intent.
- A wrist motion may be physically identical whether it is a gesture or a
  fidget. Prompt labels capture intended behavior, not ground truth about meaning.
- Named gesture recognition should be a later hierarchical model evaluated only
  after the three-class behavior boundary generalizes.

The 50 Hz resampling rate and fixed-window approach follow established wearable
activity-recognition practice, including the [UCI HAR dataset protocol][uci-har],
but the Voxa window length and labels are product-specific assumptions that must
be validated.

[colab]: https://colab.research.google.com/github/amaar-mc/voxa-cue/blob/main/ml/gesture-classifier/notebooks/Voxa_Gesture_Classifier_Colab.ipynb
[grouped-cv]: https://scikit-learn.org/stable/modules/cross_validation.html#cross-validation-iterators-for-grouped-data
[lsm-library]: https://github.com/arduino-libraries/Arduino_LSM6DS3
[nano]: https://docs.arduino.cc/hardware/nano-33-iot/
[notebook]: notebooks/Voxa_Gesture_Classifier_Colab.ipynb
[overlap-study]: https://pmc.ncbi.nlm.nih.gov/articles/PMC6891351/
[random-forest]: https://scikit-learn.org/stable/modules/ensemble.html#random-forests-and-other-randomized-tree-ensembles
[skops]: https://skops.readthedocs.io/en/stable/persistence.html
[uci-har]: https://archive.ics.uci.edu/dataset/240/human+activity+recognition+using+smartphones
