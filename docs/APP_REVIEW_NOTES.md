# App Review Notes

## App identity

- Name: Voxa Cue
- Version: 1.0.0
- Build: 1
- Bundle identifier: `com.amaarmc.voxacue`
- Minimum OS: iOS 26.0
- Device family: iPhone

Voxa Cue is a presentation coaching app. It uses the iPhone microphone for on-device speech analysis and can send discreet haptic cues over BLE to an optional Cue Band prototype.

## Access

No sign-in, user account, production subscription, purchase, or in-app payment exists in the submitted Release build. The local StoreKit configuration and Demo Pro switch are Debug-only test paths and are absent from Release. Reviewers do not need credentials. The Cue Band is optional; all recording, live metrics, session history, and local analytics can be reviewed without hardware. Features that require the optional API are clearly initiated by the user.

## Reviewer walkthrough without hardware

1. Launch the app and complete the four onboarding pages. Pairing does not block onboarding.
2. On Today, start a new session.
3. Enter a session name, choose a target duration and pace range, and leave at least one cue enabled.
4. Tap Begin presentation and grant Microphone and Speech Recognition permission.
5. Speak for at least 30 seconds. The live view shows elapsed time, rolling pace, filler count, talk ratio, transcript progress, and any locally decided cue.
6. End the session and inspect the local summary, transcript, vocal ranges, and metrics.
7. Open Sessions and Insights to inspect saved local history. Open Settings to inspect privacy controls and clear local data.

Without a band, haptic delivery cannot complete, but the session remains functional. A hardware review can connect to the BLE peripheral named `Voxa Cue` and use the documented semantic vibration patterns.

## Permissions

- Microphone: captures the presenter's voice during an active session.
- Speech Recognition: produces an on-device, time-indexed transcript for metrics.
- Bluetooth: discovers the optional Cue Band, writes haptic commands and bounded session-light timing state, and receives haptic acknowledgements.

Raw audio is processed transiently and is never saved or uploaded. The wearable receives only a six-byte physical haptic-pattern command and an optional three-byte session-light timing state; it never receives audio, presentation content, or transcript text.

## Network and AI behavior

Real-time transcription, metrics, cue selection, and BLE delivery run on the iPhone. Network access is not part of the live feedback loop.

Post-session AI coaching sends the final transcript, aggregate metrics, and cue-delivery history only after a confirmation dialog names the transmitted data. The API rejects audio payloads, does not have an application database, requests schema-constrained output, and sets OpenAI response storage to false.

## Additional disclosures

- The app has no advertising, tracking, analytics SDK, social feed, user-generated public content, or background recording.
- The app declares no non-exempt encryption; it uses operating-system BLE and HTTPS networking.
- Pitch and energy ranges are described as acoustic measurements, not evaluations of identity, health, or disability.
- `-demoScenario` loads labeled deterministic fixtures for an attended prototype demonstration. App Review should follow the live walkthrough above unless the submitted build is explicitly configured as a demo build.

Public privacy policy, support, and terms URLs plus a stable review API deployment are required release inputs before an App Store submission. They are tracked in `docs/RELEASE_CHECKLIST.md`.
