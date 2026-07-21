# Voxa Cue Privacy Policy

Effective July 21, 2026

Voxa Cue is a closed prototype created by a student team for the University of Pennsylvania Management & Technology Summer Institute (M&TSI). This policy describes the behavior of the Voxa Cue iPhone app, optional Voxa Cue API, and BLE Cue Band in this repository. The prototype has no user accounts, advertising, analytics SDK, or production payment flow. Debug builds include a clearly labeled local StoreKit test and Demo Pro switch; neither makes a charge.

## Information processed on the iPhone

During a session, Voxa Cue uses the iPhone's built-in microphone to process speech. Apple's on-device speech framework produces a live transcript. Local 16 kHz signal processing estimates voice activity, voiced energy, and pitch. The app derives pace, contextual filler count, talk ratio, internal pauses, pace variability, elapsed-time progress, and haptic cue decisions.

Raw microphone audio is transiently processed in memory. Voxa Cue does not record it to a file, retain it after the session, or upload it.

When the presenter chooses guided presentation mode, Voxa Cue can read a PDF or
PowerPoint file selected through the iOS file picker. Slide order and bounded
text are processed locally to create an even or per-slide timing schedule. The
source file and full extracted slide bodies are not copied into Voxa Cue's local
database or uploaded. Local session history retains only generic transition-cue
events and their delivery status, not slide labels or claimed slide changes.

The following session data is saved locally with SwiftData so the presenter can review history:

- finalized transcript segments and session transcript;
- target and observed timing, pace, filler, talk-ratio, pause, pace-variability, pitch-range, and energy-range metrics;
- haptic cue events and delivery status; and
- coaching insights and the source-session practice roadmap the presenter chose to generate.

Chat turns are held only in memory while the chat sheet is open. They are not written to SwiftData and are cleared when chat closes, when any saved session is deleted, or when all local data is cleared. The app also stores onboarding completion and haptic preferences in UserDefaults. Debug builds may store a local Demo Pro preference. Release builds ignore and remove that demo preference. A presenter can delete Voxa Cue's local session data from Settings. Because a roadmap includes longitudinal aggregates, deleting any contributing session also deletes the saved roadmap; deleting the app removes app-local data through iOS.

## Optional server processing

Live audio and live haptic decisions never use the Voxa Cue API.

Remote coaching is never automatic. A per-session AI insight sends its finalized transcript, aggregate metrics, and cue-event summaries only after its confirmation. Building or refreshing a roadmap has a separate confirmation and sends exactly one user-selected finalized transcript, that session's deterministic metrics and filler counts, and transcript-free historical aggregates. It never sends prior transcript text. Opening coach chat requires another confirmation; each message then sends the selected transcript, its roadmap and metrics, and at most the last 10 turns the presenter typed or received. Raw audio is never included.

The API authenticates requests with an app bearer token, validates payloads,
rejects direct audio-shaped content, and does not include a database. The server
owns the OpenAI key; it is never shipped in the iPhone app or firmware. The
insight provider payload strips its session identifier, while roadmap and chat
requests contain no session identifier. The API sends only the required text to
the allowlisted `gpt-5.6-luna` model through the OpenAI Responses API with
explicit `none` reasoning and application-state storage disabled
(`store: false`). The Voxa Cue API does not intentionally persist request
bodies, generated roadmaps, or chat responses.

`store: false` is not a zero-retention guarantee. Under OpenAI's default API controls, abuse-monitoring logs may include prompts, responses, and derived metadata for up to 30 days unless the production project is approved and configured for Zero Data Retention or Modified Abuse Monitoring. Hosting providers may also retain request metadata under their configured logging and security controls. The team must verify and disclose the deployed provider settings before any public release. See [OpenAI's API data controls](https://platform.openai.com/docs/guides/your-data).

## Bluetooth and permissions

Bluetooth is used only to discover the Cue Band, send versioned haptic pattern commands, send a bounded session mode and elapsed-time percentage for the RGB progress light, and receive delivery acknowledgements. The wearable receives no audio, transcript text, presentation content, or identity.

Microphone, Speech Recognition, and Bluetooth permissions are required to start
a real live-coaching session, and the app requires a Ready Cue Band before
entering session setup. If the band disconnects after recording begins,
on-device speech processing continues while haptic deliveries report failure.
Denying microphone or speech access prevents live recording; saved local
history remains available. The `-demoScenario` development launch argument is
limited to labeled deterministic saved data for a UI walkthrough. It does not
bypass the Ready-band requirement or run a simulated live microphone session.

The closed prototype's BLE protocol does not require pairing, bonding, link
encryption, or application-layer authentication. The app and firmware use
service UUIDs and a sequence counter for compatibility and duplicate
suppression, not device identity or authorization. A nearby central that knows
the UUIDs could connect and send haptic or light commands while the band is
available. The BLE packets contain no audio, transcript, presentation content,
or user identity, but authenticated device enrollment and abuse limits are
required before public distribution.

## Sharing, sale, and tracking

Voxa Cue does not sell personal information, share data for cross-context behavioral advertising, track users across apps or websites, or use third-party advertising or analytics SDKs. The iPhone app does not access contacts, photos, precise location, health data, or motion data. A separate developer-only IMU lab can stream the Nano 33 IoT's onboard motion sensor directly to a local desktop Chrome page. Its labeled recorder creates local CSV and JSON files only after the researcher starts and accepts a trial, and it has no automatic upload path. The optional Google Colab training workflow uploads only files the researcher explicitly selects to a Google-hosted runtime, so participant consent must cover that transfer. The lab is not part of the distributed iPhone app.

## Children and sensitive use

The prototype is intended for supervised M&TSI testing by students and professionals. It is not designed to collect children's data independently of that program. Presenters should not speak confidential, regulated, or third-party personal information while using a prototype build.

## Changes and questions

Material changes to collection or transmission behavior require an updated policy and consent copy before release. For questions about a distributed test build, contact the Voxa Cue team through the TestFlight invitation or the M&TSI project channel used to provide the build.
