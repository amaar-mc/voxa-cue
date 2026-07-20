# Voxa Cue Engineering Guide

## Product boundary

Voxa Cue is phone-first. The iPhone built-in microphone is the only audio source. Live transcription, DSP, metrics, cue selection, presentation-file parsing, persistence, and BLE control run on-device. Do not add Raspberry Pi, external-microphone, cloud-audio, or network-dependent live-cue paths to the MVP. Guided presentation mode may import PDF or PowerPoint files locally and derive deterministic slide timings; presentation content must never enter the live API path. The optional API may process a finalized transcript only after explicit post-session consent.

The live haptic path is:

`AVAudioEngine → SpeechAnalyzer/local DSP → CueEngine → CoreBluetooth → Nano 33 IoT → DRV2605L → ERM`

`contracts/ble-v1.md` is normative for app/firmware transport. Keep both implementations compatible with it.

## Repository map

- `ios/VoxaCue`: SwiftUI application and feature screens.
- `ios/Packages/VoxaKit`: strict Swift 6 domain logic and platform integrations.
- `api`: Hono/Vercel TypeScript API using schema-constrained OpenAI Responses.
- `firmware/voxa-wearable`: Nano 33 IoT and Nano ESP32 firmware plus native protocol/pattern tests.
- `contracts`: shared BLE and JSON contracts.
- `docs`: architecture, privacy, support, and release gates.

Generate `ios/VoxaCue.xcodeproj` from `ios/project.yml`; never hand-edit the generated project. Put local API settings in ignored `ios/Local.xcconfig` and a physical-device development team in ignored `ios/LocalSigning.xcconfig`, copied from their examples under `ios/Config`.

## Verification

From the repository root, run `pnpm verify` for API checks, Swift package tests, a generic iPhone build, and firmware tests/build. Focused commands are `pnpm api:test`, `pnpm ios:test`, `pnpm ios:build`, `pnpm firmware:test`, and `pnpm firmware:build`.

Physical completion additionally requires the device walkthrough and BLE/motor calibration in `README.md` and `firmware/voxa-wearable/README.md`.

## Invariants

- Never persist or upload raw audio.
- Never expose the OpenAI key to iOS or firmware.
- Keep real-time cue decisions deterministic, versioned, and cooldown-gated.
- Reject malformed provider output and BLE packets; never fabricate success.
- Label deterministic demo fixtures in the UI and demonstrations.
- Preserve strict typing and behavior tests across Swift, TypeScript, and C++.
- Update contracts, both consumers, tests, privacy copy, and architecture docs together when a data boundary changes.
