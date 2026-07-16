# Voxa Cue Product Architecture

## Architectural decision

The iPhone is the only microphone, recorder, speech processor, real-time decision engine, session store, and BLE central in the MVP. There is no Raspberry Pi, external microphone, or phone-to-Pi transport.

AI is intentionally outside the live haptic loop. Live decisions are deterministic and on-device; the optional API prepares a presentation plan before a session and produces coaching after a presenter explicitly confirms transcript transmission. This keeps presentation feedback private, predictable, and independent of network latency.

## Runtime flow

```text
Built-in iPhone microphone
       |
       v
AVAudioEngine (record/measurement audio session)
       |
       +--> AVAudioConverter --> SpeechAnalyzer
       |                         +--> SpeechTranscriber: progressive, time-indexed text
       |                         +--> SpeechDetector: voiced-time events
       |
       +--> local DSP: RMS energy + autocorrelation pitch estimate
       |
       v
TranscriptAccumulator + rolling metrics
       |
       +--> SwiftData session history
       +--> local deck checkpoint matcher
       |
       v
CueEngine v1 (pace, fillers, elapsed time, deck progress)
       |
       v
CoreBluetooth central -- six-byte command --> Nano ESP32 peripheral
       ^                                      |
       |                                      v
seven-byte status <-- accepted/completed -- DRV2605L RTP state machine
                                              |
                                              v
                                            3 V LRA
```

## iPhone application

The SwiftUI app is generated from `ios/project.yml` and targets iPhone on iOS 26.0+. `VoxaCore` contains pure domain models and algorithms; `VoxaRuntime` contains platform integrations.

### Capture and speech

`LiveSpeechPipeline` configures `AVAudioSession` for built-in-microphone recording in measurement mode, requests a 48 kHz sample rate and 20 ms I/O buffer, and feeds copied buffers to an asynchronous pipeline. Audio is converted to the best format supported by `SpeechAnalyzer` modules and timestamped on a contiguous submitted-frame clock. Pausing a session gates microphone buffers and freezes the active presentation clock, so Q&A does not enter transcription, metrics, checkpoints, or cue decisions. `SpeechTranscriber` emits progressive time-indexed results; only finalized ranges enter session metrics. `SpeechDetector` contributes voiced duration.

Every fifth input buffer is sampled for local RMS energy and an 80–300 Hz autocorrelation pitch estimate. Raw buffers are bounded in asynchronous streams, consumed in memory, and discarded. No audio-file writer or audio upload path exists.

### Live metrics and cues

`TranscriptAccumulator` deduplicates finalized transcript ranges. `TranscriptMetrics` derives normalized words, high-confidence filler counts, a 20-second rolling words-per-minute value, talk ratio, pitch range, and energy range.

`CueEngine` evaluates those metrics against a `CoachingProfile`. Version 1 includes too-fast, too-slow, filler-burst, 75% time, 90% time, 100% time, and deck-behind cues. Persistence thresholds, cooldowns, enablement, intensity, and priority suppress noisy or conflicting feedback. The highest-priority eligible event becomes one semantic cue command.

### Presentation plans

For `.pptx` sessions, `PowerPointParser` opens the ZIP package locally and extracts slide text and speaker notes from Office XML. It does not retain the original binary. If the optional API client is configured, the extracted strings and target duration request schema-constrained timed checkpoints. Otherwise, `LocalDeckPlanner` weights slide word counts and produces a local plan.

During the presentation, `SemanticMatcher` combines Apple's sentence embedding similarity with anchor-term matching. A checkpoint requires repeated confidence before it advances. A deck-behind cue is eligible only when the evidence and configured timing rule meet the local threshold.

### Local persistence

SwiftData stores session summaries, finalized transcript segments, metric samples, cue events, and generated coaching insights. The schema supports deck records, although the current import flow keeps extracted deck content in session-setup memory and does not invoke deck persistence. The app has no account and no remote application database. `VoxaDataStore.deleteAllLocalData()` removes every app model type in one local operation.

## BLE and wearable

The app is the BLE central; the Nano ESP32 advertises as `Voxa Cue`. The v1 GATT service has one write-with-response command characteristic and one read/notify status characteristic. UUIDs and byte layouts are normative in `contracts/ble-v1.md`.

A command is exactly six little-endian bytes: protocol version, monotonic 16-bit sequence, semantic pattern ID, intensity, and repeat count. The firmware validates version, range, driver readiness, busy state, and sequence freshness. It sends a seven-byte accepted status before playback and a completed status after playback. Duplicate completed sequences are rejected so reconnects cannot replay a vibration.

The Nano drives a 3 V LRA through a DRV2605L in real-time playback mode. `millis()` advances a fixed-size pulse state machine; the main loop never blocks for a full pattern and allocates no Arduino `String` in the command or playback path.

## Optional API

The Hono API deploys from `api/` to Vercel. A shared prototype bearer token protects all routes. Zod validates strict requests and maximum body sizes; errors are sanitized. The service rejects audio-shaped payloads before they can reach model code.

- `POST /v1/deck-plans` accepts `en-US` slide text/notes and a target duration. It returns monotonically ordered checkpoints that end at the target.
- `POST /v1/insights` accepts a finalized transcript, aggregate metrics, checkpoint results, and cue-event summaries only after the user confirmation in the app. It returns a schema-constrained summary, strengths, priorities, and drills.

The server owns the OpenAI key. It calls the Responses API with strict JSON Schema output and `store: false`. The iPhone never receives the provider key or prompt implementation.

## Privacy and trust boundaries

| Boundary | Data crossing it | Data that never crosses it |
| --- | --- | --- |
| Microphone to app memory | PCM buffers during an active session | Retained audio files |
| App to Cue Band | Cue ID, intensity, repeat count, sequence | Audio, transcript, presentation text, identity |
| App to deck-plan API | User-initiated extracted slide text/notes, title, duration | Original PPTX binary, audio |
| App to insight API | Confirmed finalized transcript, metrics, checkpoint and cue summaries | Raw audio |
| API to OpenAI | Text needed for the requested structured result | App bearer token, BLE data, raw audio |

## Failure behavior

- Microphone or speech permission denied: the app fails before recording and explains the missing access.
- On-device speech assets unavailable: the live session does not start; there is no cloud-audio fallback.
- Cue Band disconnected: speech processing, metrics, and persistence continue; haptic delivery reports failure.
- DRV2605L unavailable: BLE remains available but the firmware returns a driver-fault rejection.
- API unavailable: real-time coaching is unaffected, deck planning falls back locally, and new AI insight generation reports unavailable.
- Invalid model output: the API rejects it with a sanitized 502 response rather than returning unvalidated coaching.
- App leaves the active session path: the current prototype requires the screen to remain open and does not claim background recording.

## Verification surfaces

- Core behavior: Swift package tests under `ios/Packages/VoxaKit/Tests`
- iPhone integration: generated `VoxaCue` Xcode scheme and device walkthrough
- API contracts and errors: Vitest suite under `api/test`
- BLE wire contract: `contracts/ble-v1.md` and runtime packet tests
- Firmware protocol and pulse state machine: native PlatformIO Unity tests
- Physical integration: BLE smoke test, motor calibration, and wear test in `firmware/voxa-wearable/README.md`
