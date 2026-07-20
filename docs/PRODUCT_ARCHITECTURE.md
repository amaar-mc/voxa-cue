# Voxa Cue Product Architecture

## Architectural decision

The iPhone is the only microphone, recorder, speech processor, real-time decision engine, session store, and BLE central in the MVP. There is no Raspberry Pi, external microphone, or phone-to-Pi transport.

AI is intentionally outside the live haptic loop. Live decisions are deterministic and on-device; the optional API produces coaching only after a presenter explicitly confirms transcript transmission. This keeps presentation feedback private, predictable, and independent of network latency.

Guided presentation mode is also local. The app can parse a PDF or PowerPoint
file, build either an even or presenter-authored per-slide schedule, and feed
slide boundaries into the same deterministic cue engine. No presentation file
or extracted slide text is uploaded.

## Runtime flow

```text
Built-in iPhone microphone
       |
       v
AVAudioEngine (record/measurement audio session)
       |
       +--> AVAudioConverter --> SpeechAnalyzer
       |                         +--> SpeechTranscriber: progressive, time-indexed text
       |                         +--> SpeechDetector: internal analyzer gating only
       |
       +--> local DSP: RMS voice activity + Accelerate-backed YIN pitch estimate
       |
       v
TranscriptAccumulator + rolling metrics
       |
       +--> SwiftData session history
       |
       v
CueEngine v1 (pace, fillers, elapsed time)
       |
       v
CoreBluetooth central -- haptic + timing --> Nano 33 IoT peripheral
       ^                                      |                 |
       |                                      v                 v
seven-byte status <-- accepted/completed -- DRV2605L RTP      RGB progress
                                              |                 light
                                              v
                                            3 V LRA
```

## iPhone application

The SwiftUI app is generated from `ios/project.yml` and targets iPhone on iOS 26.0+. `VoxaCore` contains pure domain models and algorithms; `VoxaRuntime` contains platform integrations.

### Capture and speech

`LiveSpeechPipeline` configures `AVAudioSession` for built-in-microphone recording in measurement mode, requests a 48 kHz sample rate and 20 ms I/O buffer, and feeds copied buffers to an asynchronous pipeline. Audio is converted to the best format supported by `SpeechAnalyzer` modules with converter priming disabled. Empty conversion output is discarded, and each analyzer input uses the framework's contiguous sequence timing instead of reconstructed floating-point timestamps. Pausing a session gates microphone buffers and freezes the active presentation clock, so Q&A does not enter transcription, metrics, or cue decisions. `SpeechTranscriber` emits progressive time-indexed results. The current volatile range can feed the live pace and filler snapshot, while only finalized ranges enter durable session metrics. `SpeechDetector` remains an internal analyzer module with result reporting disabled; Voxa Cue does not use it as a voice-activity data source.

The DSP path converts the built-in microphone stream to mono 16 kHz audio. A
calibrated RMS detector classifies 20 ms frames with attack/release hysteresis
and an adaptive noise floor. An Accelerate-backed YIN estimator analyzes
overlapping 40 ms frames every 20 ms,
accepting only confident voiced estimates from 75–350 Hz. It publishes bounded
rolling snapshots every 100 ms. Pitch span uses the 10th–90th percentile in
semitones, and saved energy span uses the voiced 10th–90th percentile in dB so
isolated noise spikes do not dominate a session. Raw buffers are bounded in
asynchronous streams, consumed in memory, and discarded. No audio-file writer
or audio upload path exists.

### Live metrics and cues

`TranscriptAccumulator` deduplicates finalized transcript ranges.
`TranscriptMetrics` derives normalized words, exact filled pauses, conservative
contextual uses of “like,” “you know,” and “I mean,” an eight-second rolling
words-per-minute value, and talk ratio. The pace window proportionally counts
segments that cross its boundary, starts its opening denominator at the first
recognized speech, and includes the current volatile transcript revision without
adding it to durable totals. Presentation pace includes pauses; filler rate is
separately normalized by speaking time. App-owned RMS activity ranges provide
internal pauses of at least 500 ms only when a 30-second session has at least 90%
activity-timeline coverage. Volatile transcript ranges may contribute to a live
cue but are never persisted or included in the final summary.

`CueEngine` evaluates those metrics against a `CoachingProfile`. Slow-down,
filler-burst, 50%, and 100% cues are enabled by default; too-slow, 75%, and 90%
are opt-in. Filler-cluster configuration is snapshotted into the session
profile. It defaults to two detected fillers inside five seconds; the app lets
the presenter require one to six fillers and choose a five- to 30-second
lookback window. A 30-second per-rule cooldown prevents per-word buzzing.
Persistence, transcript freshness, three-second pace evaluation cadence, 5 WPM hysteresis,
global cooldown, enablement, intensity, pattern mapping, and priority suppress
noisy or conflicting feedback. The app maps the highest-priority semantic cue
to a physical BLE pattern.

### Guided presentation timing

`PresentationFileParser` accepts `.pptx` and `.pdf` files from the system file
picker. It validates file size and type, rejects malformed or encrypted input,
caps imports at 100 slides, bounds extracted text, and defends PowerPoint archive
and relationship paths before reading slide text. Imported files are parsed
under their security-scoped URL and are not copied into app storage.

`buildTimedDeckPlan` preserves slide order and creates cumulative boundaries.
Even mode divides the exact target duration deterministically; per-slide mode
requires one positive duration for every slide. The final slide ends at the
session target and never emits a false “next slide” cue. Non-final boundaries
use the pause-aware presentation clock and can emit the configurable BLE pattern
ID 4. Slide timing continues on screen when transition haptics are disabled or
the band is disconnected. A transition suppresses pace and filler cues in its
two-second approach window and takes priority over intermediate time milestones
to avoid stacked wrist feedback.

### Local persistence

SwiftData stores session summaries, finalized transcript segments, metric
samples, cue events, and generated coaching insights. Optional fields preserve
the difference between zero and “not measured” for pause, pace-variability, and
intonation metrics. Timed guidance does not claim that a presenter changed
slides, so it persists generic cue delivery evidence rather than fabricated
slide outcomes. Imported files, slide titles, and slide bodies are not
persisted. The app has no account and no remote application
database. `VoxaDataStore.deleteAllLocalData()` removes every app model type in
one local operation.

## BLE and wearable

The app is the BLE central; the Nano 33 IoT or supported Nano ESP32 advertises as `Voxa Cue`. The v1 GATT service has a write-with-response haptic command characteristic, a read/notify status characteristic, and an optional write-with-response session-light characteristic introduced in firmware 1.2. UUIDs and byte layouts are normative in `contracts/ble-v1.md`.

A command is exactly six little-endian bytes: protocol version, monotonic 16-bit
sequence, physical pattern ID, intensity, and repeat count. Firmware 1.1 adds
the calm-wave and deadline-hold patterns without changing protocol v1. When an
older 1.0 band is connected, the iPhone maps those two requests to the preserved
legacy filler and deadline signatures before encoding the packet. The firmware
validates version, range, driver readiness, busy state, and sequence freshness.
It sends a seven-byte accepted status before playback and a completed status
after playback. Duplicate completed sequences are rejected so reconnects cannot
replay a vibration.

The optional session-light command is exactly three bytes: protocol version,
mode, and elapsed-time percentage. During an active presentation the iPhone
sends a bounded 0–100% timing heartbeat. Firmware maps that value continuously
from green to yellow, orange, and red; overtime flashes red. Pausing freezes the
color. End, failure, BLE disconnect, or a stale heartbeat turns the LED off.
Firmware 1.1 bands omit the characteristic and remain fully compatible with
haptic delivery. Firmware 1.3 adds mode 4: when the per-session option is on,
the app sends it at 30 seconds overtime and D9 drives an active-buzzer signal
HIGH for exactly two seconds. The firmware latches that event so heartbeat
writes cannot retrigger it, while older firmware receives ordinary overtime
mode 3 instead.

The Nano drives a 3 V LRA through a DRV2605L in real-time playback mode. `millis()` advances a fixed-size pulse state machine; the main loop never blocks for a full pattern and allocates no Arduino `String` in the command or playback path.

## Optional API

The Hono API deploys from `api/` to Vercel. A shared closed-prototype bearer token protects readiness and AI routes; only the minimal liveness probe is public. The token is not production user authentication. Zod validates strict requests and maximum body sizes; errors are sanitized. The service rejects audio-shaped payloads before they can reach model code.

- `POST /v1/deck-plans` remains contract-tested for future use but is not called by the current app.
- `POST /v1/insights` accepts a finalized transcript, aggregate metrics, checkpoint results, and cue-event summaries only after the user confirmation in the app. It returns a schema-constrained summary, strengths, priorities, and drills.
- `GET /readyz` performs a bounded metadata-only check that the configured provider key can access the configured model. It sends no presentation content and performs no generation.

The server owns the OpenAI key. The current closed prototype uses
`gpt-5.6-luna` for cost-sensitive post-session structured coaching. It strips
the app's session identifier before provider processing, then calls the
Responses API with strict JSON Schema output, `store: false`, zero retries, and
a bounded abort signal. The iPhone never receives the provider key or prompt
implementation. Request telemetry is limited to a validated correlation ID,
method, path without query parameters, status, and latency; request bodies and
authorization values are excluded. `store: false` disables provider
application-state storage, but default abuse-monitoring retention remains a
separate production privacy decision documented in the release checklist.

## Prototype Pro access

Long-term Insights and optional AI review are presented behind a prototype Pro
gate. Debug builds can use a clearly labeled on-device Demo Pro switch or the
local Xcode StoreKit configuration; neither makes a charge. Release builds
ignore and remove the demo flag, start no prototype transaction listener, and
expose no unlock control. Production products, entitlement validation, terms,
and restoration remain release gates.

## Privacy and trust boundaries

| Boundary | Data crossing it | Data that never crosses it |
| --- | --- | --- |
| Microphone to app memory | PCM buffers during an active session | Retained audio files |
| Imported presentation to app memory | Slide order, bounded text, and selected timings | Network upload or wearable transfer |
| App to Cue Band | Cue ID, intensity, repeat count, sequence, session mode, timing percentage | Audio, transcript, identity |
| App to insight API | Confirmed finalized transcript, metrics, and cue summaries | Raw audio |
| API to OpenAI | Text needed for the requested structured result | App bearer token, BLE data, raw audio |

## Failure behavior

- Microphone or speech permission denied: the app fails before recording and explains the missing access.
- On-device speech assets unavailable: the live session does not start; there is no cloud-audio fallback.
- Cue Band disconnected: speech processing, metrics, and persistence continue; haptic delivery reports failure.
- DRV2605L unavailable: BLE remains available but the firmware returns a driver-fault rejection.
- API unavailable: real-time coaching is unaffected and new AI insight generation reports unavailable.
- API request budget exhausted: provider work is aborted and the API returns a sanitized typed 504 response.
- Invalid model output: the API rejects it with a sanitized 502 response rather than returning unvalidated coaching.
- App leaves the active session path: the current prototype requires the screen to remain open and does not claim background recording.

## Verification surfaces

- Core behavior: Swift package tests under `ios/Packages/VoxaKit/Tests`
- iPhone integration: generated `VoxaCue` Xcode scheme and device walkthrough
- API contracts and errors: Vitest suite under `api/test`
- BLE wire contract: `contracts/ble-v1.md` and runtime packet tests
- Firmware protocol and pulse state machine: native PlatformIO Unity tests
- Standalone IMU lab: native sensor/packet tests plus browser protocol and movement-classifier tests
- Physical integration: BLE smoke test, motor calibration, and wear test in `firmware/voxa-wearable/README.md`
