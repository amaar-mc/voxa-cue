# Voxa Cue Privacy Policy

Effective July 15, 2026

Voxa Cue is a closed prototype created by a student team for the University of Pennsylvania Management & Technology Summer Institute (M&TSI). This policy describes the behavior of the Voxa Cue iPhone app, optional Voxa Cue API, and BLE Cue Band in this repository. The prototype has no user accounts, advertising, analytics SDK, or payment flow.

## Information processed on the iPhone

During a session, Voxa Cue uses the iPhone's built-in microphone to process speech. Apple's on-device speech framework produces a live transcript and voice-activity timing. Local signal processing estimates sound energy and pitch. The app derives pace, filler-word count, talk ratio, elapsed-time progress, deck progress, and haptic cue decisions.

Raw microphone audio is transiently processed in memory. Voxa Cue does not record it to a file, retain it after the session, or upload it.

The following session data is saved locally with SwiftData so the presenter can review history:

- finalized transcript segments and session transcript;
- target and observed timing, pace, filler, talk-ratio, pitch-range, and energy-range metrics;
- haptic cue events and delivery status; and
- coaching insights the presenter chose to generate.

The app also stores the onboarding-completion preference in UserDefaults. A presenter can delete Voxa Cue's local session data from Settings. Deleting the app also removes app-local data through iOS.

## Optional server processing

Live audio and live haptic decisions never use the Voxa Cue API.

Two user-initiated features can send text through the API:

1. When a presenter selects Presentation mode and imports a PowerPoint file, the app extracts slide text and speaker notes locally. If the API is configured, that extracted text is sent to generate timed checkpoints; if it is unavailable, a local planner is used. The original `.pptx` binary is not retained or uploaded.
2. After a session, AI coaching is disabled until the presenter taps Generate AI coaching and confirms Send coaching context. Only then does the app send the finalized transcript, aggregate session metrics, checkpoint results, and cue-event summaries. Raw audio is never included.

The API authenticates requests with an app bearer token, validates payloads, rejects audio fields, and does not include a database. It sends the text request to OpenAI using the Responses API with response storage disabled (`store: false`). The API does not intentionally persist request bodies or generated responses. Infrastructure and AI providers may process limited operational or security telemetry under their own terms and retention controls.

## Bluetooth and permissions

Bluetooth is used only to discover the Cue Band, send versioned haptic pattern commands, and receive delivery acknowledgements. The wearable receives no audio or transcript text.

Microphone and Speech Recognition permissions are required for live coaching. Bluetooth permission is required only for wearable haptics. Denying microphone or speech access prevents a live recording session; the rest of the app and saved local history remain available.

## Sharing, sale, and tracking

Voxa Cue does not sell personal information, share data for cross-context behavioral advertising, track users across apps or websites, or use third-party advertising or analytics SDKs. The prototype does not access contacts, photos, precise location, health data, or motion data.

## Children and sensitive use

The prototype is intended for supervised M&TSI testing by students and professionals. It is not designed to collect children's data independently of that program. Presenters should not speak confidential, regulated, or third-party personal information while using a prototype build.

## Changes and questions

Material changes to collection or transmission behavior require an updated policy and consent copy before release. For questions about a distributed test build, contact the Voxa Cue team through the TestFlight invitation or the M&TSI project channel used to provide the build.
