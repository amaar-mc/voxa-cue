# Voxa Cue Privacy Policy

Effective July 15, 2026

Voxa Cue is a closed prototype created by a student team for the University of Pennsylvania Management & Technology Summer Institute (M&TSI). This policy describes the behavior of the Voxa Cue iPhone app, optional Voxa Cue API, and BLE Cue Band in this repository. The prototype has no user accounts, advertising, analytics SDK, or production payment flow. Debug builds include a clearly labeled local StoreKit test and Demo Pro switch; neither makes a charge.

## Information processed on the iPhone

During a session, Voxa Cue uses the iPhone's built-in microphone to process speech. Apple's on-device speech framework produces a live transcript. Local 16 kHz signal processing estimates voice activity, voiced energy, and pitch. The app derives pace, contextual filler count, talk ratio, internal pauses, pace variability, elapsed-time progress, and haptic cue decisions.

Raw microphone audio is transiently processed in memory. Voxa Cue does not record it to a file, retain it after the session, or upload it.

The following session data is saved locally with SwiftData so the presenter can review history:

- finalized transcript segments and session transcript;
- target and observed timing, pace, filler, talk-ratio, pause, pace-variability, pitch-range, and energy-range metrics;
- haptic cue events and delivery status; and
- coaching insights the presenter chose to generate.

The app also stores onboarding completion and haptic preferences in UserDefaults. Debug builds may store a local Demo Pro preference. Release builds ignore and remove that demo preference. A presenter can delete Voxa Cue's local session data from Settings. Deleting the app also removes app-local data through iOS.

## Optional server processing

Live audio and live haptic decisions never use the Voxa Cue API.

One user-initiated feature can send text through the API. After a session, AI coaching is disabled until the presenter taps Generate AI coaching and confirms Send coaching context. Only then does the app send the finalized transcript, aggregate session metrics, and cue-event summaries. Raw audio is never included.

The API authenticates requests with an app bearer token, validates payloads, rejects audio fields, strips the app's session identifier before provider processing, and does not include a database. It sends the remaining text request to OpenAI using the Responses API with application-state storage disabled (`store: false`). The Voxa Cue API does not intentionally persist request bodies or generated responses.

`store: false` is not a zero-retention guarantee. Under OpenAI's default API controls, abuse-monitoring logs may include prompts, responses, and derived metadata for up to 30 days unless the production project is approved and configured for Zero Data Retention or Modified Abuse Monitoring. Hosting providers may also retain request metadata under their configured logging and security controls. The team must verify and disclose the deployed provider settings before any public release. See [OpenAI's API data controls](https://platform.openai.com/docs/guides/your-data).

## Bluetooth and permissions

Bluetooth is used only to discover the Cue Band, send versioned haptic pattern commands, send a bounded session mode and elapsed-time percentage for the RGB progress light, and receive delivery acknowledgements. The wearable receives no audio, transcript text, presentation content, or identity.

Microphone and Speech Recognition permissions are required for live coaching. Bluetooth permission is required only for wearable haptics. Denying microphone or speech access prevents a live recording session; the rest of the app and saved local history remain available.

## Sharing, sale, and tracking

Voxa Cue does not sell personal information, share data for cross-context behavioral advertising, track users across apps or websites, or use third-party advertising or analytics SDKs. The iPhone app does not access contacts, photos, precise location, health data, or motion data. A separate developer-only IMU lab can stream an attached sensor directly to a local desktop Chrome page; it is not part of the distributed iPhone app and does not upload that data.

## Children and sensitive use

The prototype is intended for supervised M&TSI testing by students and professionals. It is not designed to collect children's data independently of that program. Presenters should not speak confidential, regulated, or third-party personal information while using a prototype build.

## Changes and questions

Material changes to collection or transmission behavior require an updated policy and consent copy before release. For questions about a distributed test build, contact the Voxa Cue team through the TestFlight invitation or the M&TSI project channel used to provide the build.
