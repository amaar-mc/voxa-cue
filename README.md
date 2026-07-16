# Voxa Cue

Voxa Cue is a phone-first presentation coach for the M&TSI prototype. The iPhone records the presenter, performs live speech and vocal analysis on device, and sends private coaching patterns over Bluetooth Low Energy (BLE) to a Cue Band built from an Arduino Nano ESP32, DRV2605L haptic driver, and LRA motor.

The MVP does **not** use a Raspberry Pi, an external microphone, or a cloud audio stream. The iPhone's built-in microphone is the only presentation input.

## System

```text
iPhone microphone
  -> on-device transcription, voice activity, pitch, and energy
  -> local pace, filler, timing, and deck-progress rules
  -> BLE semantic cue command
  -> Nano ESP32 -> DRV2605L -> LRA vibration motor

Optional, outside the live cue loop:
  PowerPoint text -> Voxa API -> timed deck plan
  confirmed transcript + aggregate metrics + cue/checkpoint summaries -> Voxa API -> coaching insight
```

| Area | Implementation |
| --- | --- |
| iPhone app | SwiftUI, Observation, SwiftData, SpeechAnalyzer, AVAudioEngine, CoreBluetooth; iOS 26.0+ |
| Shared iOS logic | Local Swift package at `ios/Packages/VoxaKit` |
| API | Hono, strict TypeScript, Zod, OpenAI Responses API structured outputs, Vercel |
| Wearable | Arduino Nano ESP32, NimBLE, DRV2605L real-time playback, 3 V LRA |
| Contracts | Versioned JSON schemas and the six-byte/seven-byte BLE v1 protocol in `contracts/` |

Live cues are decided locally so network latency or an API outage cannot interrupt coaching. The API rejects audio fields and uses `store: false` for OpenAI requests. No account or payment system exists in this prototype.

## Prerequisites

- Xcode 27 with an iOS 26+ SDK, XcodeGen 2.45+, and an iPhone running iOS 26+
- Node.js 22+, pnpm 10.32.1, and a Vercel account for the optional API
- `uvx` for isolated PlatformIO execution
- Arduino Nano ESP32, DRV2605L breakout, 3 V LRA motor, and USB-C cable

## Install and verify

Install JavaScript dependencies and verify the API, iOS package/app, and firmware from the repository root:

```sh
pnpm install
pnpm verify
```

Verify the shared iOS package:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  swift test --package-path ios/Packages/VoxaKit
```

Generate and compile the iOS project without signing:

```sh
cd ios
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -project VoxaCue.xcodeproj \
  -scheme VoxaCue \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

Verify the firmware:

```sh
cd firmware/voxa-wearable
uvx --with pip platformio test -e native
uvx --with pip platformio run -e nano_esp32
```

## Run the optional API

The local coaching loop and local deck planner work without the API. AI deck planning and post-session coaching require a server-side OpenAI key.

```sh
cp api/.env.example api/.env.local
pnpm api:dev
```

Set all three values in `api/.env.local` before starting:

- `OPENAI_API_KEY`: server-side key; never add it to the iOS app
- `OPENAI_MODEL`: model used for schema-constrained deck plans and insights
- `VOXA_DEMO_API_TOKEN`: random bearer token of at least 32 characters

Every API endpoint, including `/health`, requires `Authorization: Bearer <token>`. Deploy with the `api` directory as the Vercel project root and configure the same environment variables there.

## Configure and run the iPhone app

1. Run `xcodegen generate` in `ios/`, then open `ios/VoxaCue.xcodeproj`.
2. Select the VoxaCue target and set a development team for device signing.
3. For AI-enabled builds, copy `ios/Config/BuildSettings.xcconfig.example` to ignored `ios/Local.xcconfig`, then set `VOXA_API_BASE_URL` to the deployed HTTPS origin and `VOXA_DEMO_API_TOKEN` to the matching server token. Real credentials must remain uncommitted.
4. Install on an iPhone running iOS 26+ and allow Microphone, Speech Recognition, and Bluetooth access when requested.

To run deterministic presentation fixtures without microphone input, add `-demoScenario` to the Xcode scheme's Run Arguments. This mode is for a labeled prototype demonstration, not product evaluation.

## Flash and pair the Cue Band

Wire and safety instructions are in `firmware/voxa-wearable/README.md`. With the Nano connected:

```sh
cd firmware/voxa-wearable
uvx --with pip platformio run -e nano_esp32 --target upload
uvx --with pip platformio device monitor --baud 115200
```

The serial monitor must print `Voxa Cue firmware 1.0 ready`. In the app, tap Connect Cue Band and wait for the `Voxa Cue` peripheral to reach Ready. The exact service, command, status UUIDs, packet bytes, and acknowledgements are defined in `contracts/ble-v1.md`.

## Demonstrate the product

1. Power the band and connect it from Voxa Cue.
2. Preview the cue patterns so the presenter knows their meanings.
3. Start a Free Speaking session or import a `.pptx` for Presentation mode.
4. Set target duration, pace range, enabled cues, and intensity.
5. Begin the session, leave the screen open, and place the phone nearby with its built-in microphone unobstructed.
6. Present normally. Pace, fillers, elapsed time, vocal features, and cue decisions update locally; accepted cue commands vibrate the band.
7. End the session to view locally saved analytics. AI coaching is generated only after the presenter confirms that the final transcript, aggregate metrics, cue-delivery history, and checkpoint outcomes may be sent.

The app remains usable for recording and analytics if the band is disconnected. If the optional API is unavailable, live coaching continues and PowerPoint timing falls back to the local planner.

## Documentation

- `docs/PRODUCT_ARCHITECTURE.md` — components, data flow, privacy boundaries, and failure behavior
- `docs/PRIVACY_POLICY.md` — prototype data practices
- `docs/TERMS_OF_USE.md` — closed-prototype terms
- `docs/SUPPORT.md` — compatibility and troubleshooting
- `docs/APP_REVIEW_NOTES.md` — reviewer walkthrough and feature disclosures
- `docs/RELEASE_CHECKLIST.md` — demo and public-release gates
