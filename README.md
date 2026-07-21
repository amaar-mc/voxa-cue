<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="design/brand/02_primary_logo_white_text.png" />
    <source media="(prefers-color-scheme: light)" srcset="design/brand/01_primary_logo_dark_text.png" />
    <img src="design/brand/01_primary_logo_dark_text.png" width="560" alt="Voxa Cue" />
  </picture>

  <p><strong>SPEAK · CONNECT · CONTROL</strong></p>
  <p>
    Discreet guidance. Confident delivery.
  </p>
  <p>Voxa Cue is a phone-first speech coach measured on your iPhone and felt on your wrist.</p>

  <p>
    <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6.0-0B756F?style=for-the-badge&logo=swift&logoColor=white" />
    <img alt="iOS 26+" src="https://img.shields.io/badge/iOS-26%2B-071122?style=for-the-badge&logo=apple&logoColor=white" />
    <img alt="TypeScript strict" src="https://img.shields.io/badge/TypeScript-Strict-0B756F?style=for-the-badge&logo=typescript&logoColor=white" />
    <img alt="XIAO nRF54L15 Sense" src="https://img.shields.io/badge/XIAO_nRF54L15-Wearable-A85E24?style=for-the-badge&logo=seeedstudio&logoColor=white" />
  </p>

  <p>
    <a href="#the-product">Product</a> ·
    <a href="#architecture">Architecture</a> ·
    <a href="#brand-system">Brand</a> ·
    <a href="#quick-start">Quick start</a> ·
    <a href="#verification">Verification</a> ·
    <a href="#documentation">Docs</a>
  </p>
</div>

---

> [!IMPORTANT]
> Voxa Cue is phone-first. The built-in iPhone microphone is the only audio source, the live coaching loop runs entirely on-device, and raw audio is never uploaded. There is no Raspberry Pi or external microphone in the MVP.

## The product

Presenters often rush, repeat filler words, or lose track of time precisely when looking at another screen would be most distracting. Voxa Cue closes that feedback gap with a discreet coaching loop:

1. The iPhone listens during a presentation.
2. On-device speech and signal processing measure delivery in real time.
3. A deterministic cue engine decides whether feedback is warranted.
4. The phone maps that decision to a physical pulse and sends it over Bluetooth Low Energy.
5. The Cue Band delivers a distinct, discreet vibration.
6. The app saves the session and can turn it into an actionable practice plan.

<table>
  <tr>
    <td align="center" width="20%"><img src="design/brand/13_feature_icon_confidence.png" width="72" alt="Confidence waveform" /><br /><strong>Confidence</strong></td>
    <td align="center" width="20%"><img src="design/brand/14_feature_icon_timing.png" width="72" alt="Timing ring" /><br /><strong>Timing</strong></td>
    <td align="center" width="20%"><img src="design/brand/15_feature_icon_analytics.png" width="72" alt="Analytics bars" /><br /><strong>Analytics</strong></td>
    <td align="center" width="20%"><img src="design/brand/16_feature_icon_haptics.png" width="72" alt="Haptic rings" /><br /><strong>Haptics</strong></td>
    <td align="center" width="20%"><img src="design/brand/17_feature_icon_pace.png" width="72" alt="Pace wave" /><br /><strong>Pace</strong></td>
  </tr>
</table>

| Live coaching | Post-session improvement |
| --- | --- |
| Speaking pace and persistence | Evidence-based session summary |
| Contextual filler bursts | Pace, filler, pause, timing, and talk-ratio analytics |
| Even or per-slide presentation timing | Pause-aware slide guidance and cue history |
| 50% and target-time defaults; optional 75% and 90% cues | Descriptive intonation and energy trends |
| Haptic delivery acknowledgements | Longitudinal history, optional AI roadmap, and bounded coach chat |

### Guided presentations

Choose **Use a presentation** to import a `.pptx` or `.pdf` file. Voxa Cue reads
up to 100 slides locally, then offers two timing modes:

- **Even timing** divides the session target across every slide, including a deterministic remainder.
- **Per slide** lets the presenter assign each slide an explicit duration whose total must match the session target.

During the session, the app shows the current slide and its remaining time. At
each non-final boundary it can send a configurable long-short-long transition
pulse. The schedule uses the same pause-aware presentation clock as speech
metrics, so pausing for Q&A also pauses slide timing. Imported slide content is
never sent to the wearable or any API route.

### A configurable haptic language

| Cue | Meaning |
| --- | --- |
| Slow down | Pace has remained above the personalized range |
| Pick up the pace | Pace has remained below the personalized range |
| Filler cluster | A contextual filler burst was detected |
| Halfway point | Half of the target time has elapsed |
| 75% used | Three quarters of the target time has elapsed |
| 90% used | The presentation is entering its closing window |
| Target reached | The configured presentation time has elapsed |

Slow down, filler cluster, halfway, and target reached are enabled by default. The
other cues are opt-in under Advanced. Every cue can use any pulse preset and a
soft, medium, or strong intensity. Filler clusters default to two detected
fillers within five seconds. The presenter can require one to six fillers and
choose a five- to 30-second lookback window. A 30-second filler reset,
persistence thresholds, and cue priority prevent noisy or conflicting feedback.

## Architecture

```mermaid
flowchart LR
    MIC["Built-in iPhone<br/>microphone"] --> SPEECH["SpeechAnalyzer<br/>+ local DSP"]
    DECK["PDF / PowerPoint<br/>local import"] --> TIMING["Even or per-slide<br/>timing plan"]
    SPEECH --> METRICS["Transcript, pace,<br/>fillers, pauses, intonation"]
    METRICS --> ENGINE["Deterministic<br/>CueEngine"]
    TIMING --> ENGINE
    ENGINE --> BLE["CoreBluetooth<br/>BLE v1"]
    BLE --> BAND["XIAO nRF54L15<br/>Zephyr"]
    BAND --> MOTOR["DRV2605L<br/>+ 3 V ERM"]
    BAND --> LIGHT["RGB session<br/>progress light"]
    METRICS --> STORE[("SwiftData<br/>session history")]
    STORE -. "explicit consent" .-> API["Voxa API<br/>post-session only"]

    classDef phone fill:#F3F4F1,stroke:#0B756F,color:#0B171B,stroke-width:2px;
    classDef band fill:#F3E7DC,stroke:#A85E24,color:#0B171B,stroke-width:2px;
    classDef optional fill:#0B756F,stroke:#07524E,color:#ffffff,stroke-width:2px;
    class MIC,DECK,TIMING,SPEECH,METRICS,ENGINE,BLE,STORE phone;
    class BAND,MOTOR,LIGHT band;
    class API optional;
```

The live path never waits for a network request. If Bluetooth disconnects, recording and analytics continue. The optional API is used only for user-triggered post-session coaching after a separate confirmation for each remote feature.

### Data boundaries

| Boundary | What crosses it | What never crosses it |
| --- | --- | --- |
| Microphone → app memory | PCM buffers during an active session | Retained audio files |
| Imported presentation → app memory | Slide order, local text, and selected timings | Network upload or wearable transfer |
| iPhone → Cue Band | Physical pattern ID, intensity, repeat count, sequence, session mode, timing percentage | Audio, transcript, identity |
| iPhone → insight API | One confirmed finalized transcript, aggregate session metrics, and cue summaries | Raw audio and prior transcript text |
| iPhone → roadmap API | One selected finalized transcript, its deterministic metrics and filler counts, and transcript-free historical aggregates | Raw audio and prior transcript text |
| iPhone → coach-chat API | That selected transcript, its roadmap and metrics, and at most 10 typed chat turns | Raw audio, prior transcript text, and a stored server conversation |
| Voxa API → OpenAI | Text required for the requested structured result | App bearer token, BLE data, raw audio |

The server owns the OpenAI key and calls the Responses API with the allowlisted `gpt-5.6-luna` model, explicit `none` reasoning for this bounded low-latency task, strict structured outputs, and `store: false`. The API accepts text-only coaching requests and rejects audio-shaped keys, direct audio references, recognized encoded-audio headers, and large base64 blocks before provider submission. `store: false` disables Responses application-state storage, not default abuse-monitoring retention; production retention remains a release decision.

## Technology

| Layer | Libraries and frameworks |
| --- | --- |
| iPhone app | SwiftUI, Observation, SwiftData, SpeechAnalyzer, AVAudioEngine, CoreBluetooth |
| Shared iOS logic | Swift 6 package with pure cue, transcript, timing, and analytics modules |
| API | Hono, strict TypeScript, Zod, OpenAI Responses API with `gpt-5.6-luna`, Vitest, Vercel |
| Wearable | Seeed Studio XIAO nRF54L15 Sense with Zephyr, DRV2605L, and PlatformIO; Nano 33 IoT and Nano ESP32 remain supported |
| Contracts | Post-session JSON Schemas plus a versioned six-byte command and seven-byte status BLE protocol |

## Brand system

The product system pairs the band’s industrial graphite with warm ivory surfaces, voice-signal teal, and haptic copper. Color communicates function instead of decorating generic “AI” surfaces.

| Token | Value | Role |
| --- | --- | --- |
| Voice Signal | `#0B756F` | Listening, analysis, and primary action |
| Haptic Copper | `#A85E24` | Physical wrist cues and tactile emphasis |
| Graphite | `#0B171B` | Hardware anchor, wordmark, and primary text |
| Warm Ivory | `#F3F4F1` | Quiet canvas |
| Signal Surface | `#E0EFEB` | Selected and secondary states |

The original source toolkit remains versioned in [`design/brand`](design/brand); the app’s current semantic palette is implemented in `CueTheme.swift`. The language system is **“Speak · Connect · Control”**, **“Guided by rhythm. Powered by precision.”**, and **“Discreet guidance. Confident delivery.”**

## Repository

```text
voxa-cue/
├── api/                         Hono API and OpenAI integration
├── contracts/                   JSON schemas and normative BLE v1 contract
├── design/brand/                Complete Concept 3 brand toolkit
├── docs/                        Architecture, privacy, support, and release gates
├── firmware/voxa-wearable/      Nano 33 IoT / Nano ESP32 haptic firmware
├── firmware/voxa-wearable-nrf54/ XIAO nRF54L15 Zephyr haptic firmware
├── firmware/imu-diagnostic/     Standalone Nano 33 IoT IMU lab firmware
├── ios/
│   ├── Packages/VoxaKit/        Reusable VoxaCore and VoxaRuntime modules
│   ├── VoxaCue/                 SwiftUI application
│   ├── VoxaCueTests/            App coordination behavior tests
│   └── project.yml              XcodeGen project definition
├── ml/gesture-classifier/       Local BLE recorder and experimental ML pipeline
├── tools/                       BLE and IMU browser diagnostics
└── package.json                 Unified build and verification commands
```

## Quick start

### Verify the entire system

Requirements: Xcode 27 with the iOS 26+ SDK, XcodeGen, Node.js 22+, pnpm 10.32.1, and `uvx`.

```sh
pnpm install --frozen-lockfile
pnpm verify
```

That single command type-checks, tests, and builds the API, runs package and
simulator app tests, validates both Debug and credential-free Release iOS
builds, lints the privacy manifest, verifies both Nano firmware paths and the
XIAO nRF54L15 Zephyr target, and executes the isolated gesture-model test and
notebook pipeline.

### Launch the iPhone app

```sh
pnpm ios:generate
open -a /Applications/Xcode-beta.app ios/VoxaCue.xcodeproj
```

In Xcode:

1. Select an iPhone running iOS 26+ or an iOS simulator.
2. For a physical device, connect and unlock it, trust the Mac, enable Developer Mode, and select an Apple development team under **Signing & Capabilities**.
3. Add `-demoScenario` under **Scheme → Run → Arguments** for deterministic, clearly labeled demo data.
4. Press **Run**.

The labeled demo requires no microphone, band, or API to inspect saved sessions, analytics, and AI UI fixtures. It does not bypass the live-session connection gate. Remove `-demoScenario`, connect a healthy Cue Band, and use a physical iPhone to exercise the real recording flow.

<details>
<summary><strong>Configure the optional AI API</strong></summary>

The app records, analyzes speech, and drives haptics without the API. Optional post-session roadmaps and coach chat require a server-side OpenAI key and explicit in-app confirmation before their context is sent.

```sh
cp api/.env.example api/.env.local
pnpm api:dev
```

Set:

- `OPENAI_API_KEY` to a server-side key
- `OPENAI_MODEL=gpt-5.6-luna`, the only reviewed model accepted by the current schema
- `VOXA_BUILD_ID` to the deployment commit SHA or release identifier
- `VOXA_DEMO_API_TOKEN` to a random bearer token of at least 32 characters

Deploy with `api/` as the Vercel project root. `GET /livez` is a public minimal liveness probe; `/health`, `/readyz`, and AI routes require `Authorization: Bearer <token>`. This shared token is only for the closed prototype. Release AI remains disabled until it is replaced with per-user authentication, rate limits, and spend ceilings.

For an AI-enabled app build, copy `ios/Config/BuildSettings.xcconfig.example` to ignored `ios/Local.xcconfig`, then set the deployed HTTPS origin and matching bearer token. Provider credentials never belong in the app.

</details>

<details>
<summary><strong>Flash and pair the Cue Band</strong></summary>

For the compact Cue Band, wire the XIAO nRF54L15 Sense at 3.3 V only: D4
(`P1.10`) to DRV2605L SDA, D5 (`P1.11`) to SCL, red to D6, blue to D7,
green to D8, and the optional active-buzzer signal to D9. Put a 220–330 Ω
resistor on every RGB leg. D9 may drive only a 3.3 V-compatible high-impedance
input or a correctly sized transistor stage. The ERM connects only to the
DRV2605L outputs, never to a GPIO or power rail. Keep every ground common and
confirm the breakout accepts 3.3 V before powering it.

```sh
pnpm firmware:build:xiao
pnpm firmware:flash:xiao
```

The XIAO's onboard CMSIS-DAP probe handles flashing over its USB-C data cable;
do not double-press reset or look for a UF2 volume. In the app, open
**Settings → Device Lab**, scan, connect, and send a test command. The Zephyr
target advertises the same BLE v1 UUIDs and packets as the Nano targets, so the
iOS app needs no code or setting change. During a timed session, the RGB light
moves from green through yellow and orange to red, then flashes red overtime.
If a 3.3 V-compatible active buzzer is wired safely to D9, the opt-in
emergency-buzzer setting produces one two-second tone at 30 seconds overtime.

The legacy Nano 33 IoT and Nano ESP32 targets remain documented in
[the Nano firmware guide](firmware/voxa-wearable/README.md). The Nano 33 IoT
still requires NINA-W102 connectivity firmware 3.0.0 or newer.

</details>

## Demonstration flow

1. Launch with `-demoScenario` for a saved-data software walkthrough, or connect the physical Cue Band for a new live session.
2. Verify all nine physical haptic patterns in Device Lab.
3. Start a session using the iPhone microphone.
4. Set target time, pace range, enabled cues, and intensity.
5. Present while Voxa Cue measures delivery and acknowledges any haptic commands.
6. End the session to inspect analytics and transcript evidence.
7. In **Insights**, separately confirm roadmap generation or coach chat when demonstrating optional AI.

## Verification

The current implementation is exercised across all three layers:

| Surface | Verified behavior |
| --- | --- |
| API | Strict TypeScript plus contract and failure-path tests |
| VoxaCore + VoxaRuntime | Swift behavior tests for metrics, timing, cue logic, microphone-route enforcement, BLE bytes, persistence, and API payloads |
| iPhone application | Simulator behavior tests plus unsigned Debug and Release generic-device builds |
| Firmware | Native protocol, pattern, light, and driver-recovery tests plus successful XIAO nRF54L15, Nano 33 IoT, and Nano ESP32 builds |
| IMU lab | Native packet/sensor tests, labeled-recorder and model-pipeline tests, executable notebook, and a Nano 33 IoT build |
| Release configuration | Privacy manifest lint plus a built Info.plist check proving the shared demo token is empty |

Physical BLE, motor calibration, microphone placement, and wear testing are intentionally tracked as hardware gates in the release checklist.

## Documentation

| Document | Purpose |
| --- | --- |
| [Setup guide](docs/SETUP_GUIDE.md) | Exact tools, wiring, secrets, deployment, costs, and physical checks |
| [Repository audit](docs/REPOSITORY_AUDIT.md) | Security, privacy, UI, backend, firmware, and release findings |
| [Backend audit](docs/BACKEND_AUDIT.md) | Closed-prototype verdict and public-release gaps |
| [Product architecture](docs/PRODUCT_ARCHITECTURE.md) | Runtime data flow, trust boundaries, and failure behavior |
| [BLE protocol v1](contracts/ble-v1.md) | Normative UUIDs, packet bytes, statuses, and replay rules |
| [XIAO firmware](firmware/voxa-wearable-nrf54) | Primary Zephyr wearable target; wiring and CMSIS-DAP steps are in the setup guide |
| [Nano firmware](firmware/voxa-wearable/README.md) | Supported Nano wiring, flashing, calibration, and safety |
| [Gesture ML lab](ml/gesture-classifier/README.md) | Labeled collection, quality gates, grouped evaluation, and model export |
| [Privacy policy](docs/PRIVACY_POLICY.md) | Prototype data practices |
| [Support](docs/SUPPORT.md) | Compatibility and troubleshooting |
| [App Review notes](docs/APP_REVIEW_NOTES.md) | Reviewer walkthrough and AI disclosures |
| [Release checklist](docs/RELEASE_CHECKLIST.md) | Demo, hardware, privacy, legal, and distribution gates |
| [Security policy](SECURITY.md) | Private vulnerability reporting and supported scope |

---

<div align="center">
  <img src="design/brand/07_icon_gradient.png" width="52" alt="Voxa haptic ring" />
  <br />
  <strong>SPEAK · CONNECT · CONTROL</strong>
  <br />
  <strong>Built for the University of Pennsylvania Management & Technology Summer Institute.</strong>
  <br />
  Voxa Cue is a working MVP prototype, not a medical, safety, or accessibility device.
</div>
