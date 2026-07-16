<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="design/brand/02_primary_logo_white_text.png" />
    <source media="(prefers-color-scheme: light)" srcset="design/brand/01_primary_logo_dark_text.png" />
    <img src="design/brand/01_primary_logo_dark_text.png" width="560" alt="Voxa" />
  </picture>

  <p><strong>SPEAK · CONNECT · CONTROL</strong></p>
  <p>
    Discreet guidance. Confident delivery.
  </p>
  <p>Voxa Cue is an AI speech coach measured on your iPhone and felt on your wrist.</p>

  <p>
    <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6.0-775CF6?style=for-the-badge&logo=swift&logoColor=white" />
    <img alt="iOS 26+" src="https://img.shields.io/badge/iOS-26%2B-071122?style=for-the-badge&logo=apple&logoColor=white" />
    <img alt="TypeScript strict" src="https://img.shields.io/badge/TypeScript-Strict-6765FF?style=for-the-badge&logo=typescript&logoColor=white" />
    <img alt="Arduino Nano ESP32" src="https://img.shields.io/badge/Nano_ESP32-Wearable-8B8BFF?style=for-the-badge&logo=arduino&logoColor=071122" />
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

Presenters often rush, repeat filler words, or lose track of time precisely when looking at another screen would be most distracting. Voxa Cue closes that feedback gap with a private coaching loop:

1. The iPhone listens during a presentation.
2. On-device speech and signal processing measure delivery in real time.
3. A deterministic cue engine decides whether feedback is warranted.
4. The phone sends a semantic command over Bluetooth Low Energy.
5. The Cue Band delivers a distinct, discreet vibration.
6. The app saves the session and turns it into an actionable practice plan.

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
| Speaking pace and persistence | Session score and delivery summary |
| High-confidence filler bursts | Pace, filler, timing, and talk-ratio analytics |
| 75%, 90%, and 100% time milestones | Pitch and energy-range trends |
| Progress against an imported PowerPoint | Evidence-backed priorities and drills |
| Private haptic delivery acknowledgements | Longitudinal session history |

### The seven-cue haptic language

| Cue | Meaning |
| --- | --- |
| Slow down | Pace has remained above the personalized range |
| Pick up the pace | Pace has remained below the personalized range |
| Reset fillers | A high-confidence filler burst was detected |
| Move to the next idea | Presentation progress is behind the timed deck plan |
| 75% used | Three quarters of the target time has elapsed |
| 90% used | The presentation is entering its closing window |
| Target reached | The configured presentation time has elapsed |

Each cue has a fixed pulse shape and a user-selected soft, medium, or strong intensity. Cooldowns, persistence thresholds, and cue priority prevent noisy or conflicting feedback.

## Architecture

```mermaid
flowchart LR
    MIC["Built-in iPhone<br/>microphone"] --> SPEECH["SpeechAnalyzer<br/>+ local DSP"]
    SPEECH --> METRICS["Transcript, pace,<br/>fillers, pitch, energy"]
    METRICS --> ENGINE["Deterministic<br/>CueEngine"]
    ENGINE --> BLE["CoreBluetooth<br/>BLE v1"]
    BLE --> NANO["Nano ESP32"]
    NANO --> MOTOR["DRV2605L<br/>+ 3 V LRA"]
    METRICS --> STORE[("SwiftData<br/>session history")]
    STORE -. "explicit consent" .-> API["Voxa API<br/>post-session only"]

    classDef phone fill:#ECEFF7,stroke:#6765FF,color:#071122,stroke-width:2px;
    classDef band fill:#8B8BFF,stroke:#6765FF,color:#071122,stroke-width:2px;
    classDef optional fill:#775CF6,stroke:#6765FF,color:#ffffff,stroke-width:2px;
    class MIC,SPEECH,METRICS,ENGINE,BLE,STORE phone;
    class NANO,MOTOR band;
    class API optional;
```

The live path never waits for a network request. If Bluetooth disconnects, recording and analytics continue. If the optional API is unavailable, live haptics remain unaffected and PowerPoint planning falls back to a local algorithm.

### Data boundaries

| Boundary | What crosses it | What never crosses it |
| --- | --- | --- |
| Microphone → app memory | PCM buffers during an active session | Retained audio files |
| iPhone → Cue Band | Cue ID, intensity, repeat count, sequence | Audio, transcript, deck text, identity |
| iPhone → deck-plan API | User-initiated slide text, notes, title, target time | Original PowerPoint binary, audio |
| iPhone → insight API | Confirmed transcript, aggregate metrics, cue and checkpoint summaries | Raw audio |
| Voxa API → OpenAI | Text required for the requested structured result | App bearer token, BLE data, raw audio |

The API rejects audio-shaped payloads and requests structured outputs with provider application-state storage disabled. OpenAI abuse-monitoring retention remains an explicit production release decision.

## Technology

| Layer | Libraries and frameworks |
| --- | --- |
| iPhone app | SwiftUI, Observation, SwiftData, SpeechAnalyzer, AVAudioEngine, CoreBluetooth |
| Shared iOS logic | Swift 6 package with pure cue, transcript, timing, and deck-matching modules |
| Presentation import | ZIPFoundation, local Office XML extraction, NaturalLanguage embeddings |
| API | Hono, strict TypeScript, Zod, OpenAI Responses API, Vitest, Vercel |
| Wearable | Arduino Nano ESP32, NimBLE-Arduino, Adafruit DRV2605, PlatformIO |
| Contracts | JSON Schema plus a versioned six-byte command and seven-byte status BLE protocol |

## Brand system

The README follows the supplied Concept 3 system: **haptic precision**, rhythmic geometry, Comfortaa-led display typography, and a high-contrast indigo palette.

| Token | Value | Role |
| --- | --- | --- |
| Haptic Indigo | `#6765FF` | Primary action and core mark |
| Signal Periwinkle | `#8B8BFF` | Secondary signal and soft emphasis |
| Pulse Violet | `#775CF6` | Energy, gradients, and active states |
| Midnight Navy | `#071122` | Wordmark and primary text |
| Interface Mist | `#ECEFF7` | Quiet surfaces and contrast |

The complete source toolkit—including light/dark marks, icons, pattern, palette, typography board, and overview—is versioned in [`design/brand`](design/brand). The language system is **“Speak · Connect · Control”**, **“Guided by rhythm. Powered by precision.”**, and **“Discreet guidance. Confident delivery.”**

## Repository

```text
voxa-cue/
├── api/                         Hono API and OpenAI integration
├── contracts/                   JSON schemas and normative BLE v1 contract
├── design/brand/                Complete Concept 3 brand toolkit
├── docs/                        Architecture, privacy, support, and release gates
├── firmware/voxa-wearable/      Nano ESP32 firmware and native tests
├── ios/
│   ├── Packages/VoxaKit/        Reusable VoxaCore and VoxaRuntime modules
│   ├── VoxaCue/                 SwiftUI application
│   ├── VoxaCueTests/            App coordination behavior tests
│   └── project.yml              XcodeGen project definition
└── package.json                 Unified build and verification commands
```

## Quick start

### Verify the entire system

Requirements: Xcode 27 with the iOS 26+ SDK, XcodeGen, Node.js 22+, pnpm 10.32.1, and `uvx`.

```sh
pnpm install --frozen-lockfile
pnpm verify
```

That single command type-checks, tests, and builds the API, runs package and simulator app tests, validates both Debug and credential-free Release iOS builds, lints the privacy manifest, and verifies native plus Nano ESP32 firmware.

### Launch the iPhone app

```sh
cd ios
xcodegen generate
open VoxaCue.xcodeproj
```

In Xcode:

1. Select an iPhone running iOS 26+ or an iOS simulator.
2. Set a development team when installing on a physical device.
3. Add `-demoScenario` under **Scheme → Run → Arguments** for deterministic, clearly labeled demo data.
4. Press **Run**.

The demo requires no microphone, band, or API. Remove `-demoScenario` to exercise the real recording flow.

<details>
<summary><strong>Configure the optional AI API</strong></summary>

The app records, analyzes speech, plans decks locally, and drives haptics without the API. AI-enhanced deck planning and post-session coaching require a server-side OpenAI key.

```sh
cp api/.env.example api/.env.local
pnpm api:dev
```

Set:

- `OPENAI_API_KEY` to a server-side key
- `OPENAI_MODEL` to the configured structured-output model
- `VOXA_BUILD_ID` to the deployment commit SHA or release identifier
- `VOXA_DEMO_API_TOKEN` to a random bearer token of at least 32 characters

Deploy with `api/` as the Vercel project root. `GET /livez` is a public minimal liveness probe; `/health`, `/readyz`, and both AI routes require `Authorization: Bearer <token>`. This shared token is only for the closed prototype and is not production user authentication.

For an AI-enabled app build, copy `ios/Config/BuildSettings.xcconfig.example` to ignored `ios/Local.xcconfig`, then set the deployed HTTPS origin and matching bearer token. Provider credentials never belong in the app.

</details>

<details>
<summary><strong>Flash and pair the Cue Band</strong></summary>

Wire the Nano ESP32, DRV2605L breakout, and 3 V LRA using the safety notes in [the firmware guide](firmware/voxa-wearable/README.md).

```sh
cd firmware/voxa-wearable
uvx --with pip platformio run -e nano_esp32 --target upload
uvx --with pip platformio device monitor --baud 115200
```

The serial monitor should print `Voxa Cue firmware 1.0 ready`. In the app, select **Connect Cue Band** and wait for the peripheral to reach **Ready**.

</details>

## Demonstration flow

1. Launch with `-demoScenario` for a software-only walkthrough, or connect the physical Cue Band.
2. Preview the seven haptic patterns from Settings.
3. Start a Free Speaking session or import a `.pptx`.
4. Set target time, pace range, enabled cues, and intensity.
5. Present while Voxa Cue measures delivery and acknowledges any haptic commands.
6. End the session to inspect analytics, transcript evidence, priorities, and drills.

## Verification

The current implementation is exercised across all three layers:

| Surface | Verified behavior |
| --- | --- |
| API | Strict TypeScript, production bundle, 24 Vitest contract and failure-path tests |
| VoxaCore + VoxaRuntime | 40 Swift tests for metrics, timing, cue logic, BLE bytes, persistence, and API payloads |
| iPhone application | 14 simulator behavior tests plus unsigned Debug and Release generic-device builds |
| Firmware | 15 native Unity tests plus a successful Nano ESP32 release build |
| Release configuration | Privacy manifest lint plus a built Info.plist check proving the shared demo token is empty |

Physical BLE, motor calibration, microphone placement, and wear testing are intentionally tracked as hardware gates in the release checklist.

## Documentation

| Document | Purpose |
| --- | --- |
| [Product architecture](docs/PRODUCT_ARCHITECTURE.md) | Runtime data flow, trust boundaries, and failure behavior |
| [BLE protocol v1](contracts/ble-v1.md) | Normative UUIDs, packet bytes, statuses, and replay rules |
| [Firmware guide](firmware/voxa-wearable/README.md) | Wiring, flashing, calibration, and safety |
| [Privacy policy](docs/PRIVACY_POLICY.md) | Prototype data practices |
| [Support](docs/SUPPORT.md) | Compatibility and troubleshooting |
| [App Review notes](docs/APP_REVIEW_NOTES.md) | Reviewer walkthrough and AI disclosures |
| [Release checklist](docs/RELEASE_CHECKLIST.md) | Demo, hardware, privacy, legal, and distribution gates |

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
