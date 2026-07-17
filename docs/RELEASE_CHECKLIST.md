# Voxa Cue Release Checklist

This checklist separates the closed M&TSI demonstration from a public App Store release. Version values currently declared in `ios/project.yml` are 1.0.0 (build 1), bundle identifier `com.amaarmc.voxacue`, and iOS 26.0 minimum.

## Closed M&TSI demo gate

- [ ] `pnpm install` completes from the repository root.
- [ ] `pnpm verify` passes API checks, Swift package and simulator app tests, Debug and credential-free Release generic-device iOS builds, privacy-manifest lint, haptic firmware tests/builds, and standalone IMU lab tests/build.
- [ ] The VoxaCue iOS test target compiles with `xcodebuild build-for-testing` and its tests execute on the exact demonstration iPhone.
- [ ] A signed build installs and launches on the exact demonstration iPhone running iOS 26+.
- [ ] Microphone, Speech Recognition, and Bluetooth permission paths are exercised from a clean install.
- [ ] A 60-second live session produces finalized transcript text, local voice-activity timing, pace, contextual filler, pause, talk-ratio, pitch-range, and energy-range results without retaining an audio file.
- [ ] A complete phone-microphone session works with the API disabled.
- [ ] Authenticated `/readyz` confirms that the deployed OpenAI key can access the configured model without sending presentation content.
- [ ] The API receives no raw-audio fields and rejects an attempted audio payload.
- [ ] AI coaching remains locked behind a confirmation dialog naming the transcript, aggregate metrics, and cue-delivery history.
- [ ] `uvx --with pip platformio test -e native` passes all firmware tests.
- [ ] `uvx --with pip platformio run -e nano_33_iot` succeeds.
- [ ] `uvx --with pip platformio run -e nano_esp32` succeeds.
- [ ] The exact demo Nano, driver, motor, wiring, enclosure, and power source pass the 15-minute wear test in the firmware README.
- [ ] BLE smoke testing confirms accepted and completed acknowledgements, duplicate rejection, all nine physical haptic patterns, firmware 1.1 calm-wave/deadline support, firmware 1.2 session-light progress, pause, overtime, disconnect, and timeout behavior, and firmware 1.3 one-shot D9 buzzer timing without heartbeat retrigger.
- [ ] Airplane-mode testing confirms that live coaching and BLE haptics continue without the API.
- [ ] No real API key or bearer token is present in Git history, source, generated project files, logs, screenshots, or demo materials.
- [ ] `-demoScenario` screens and metrics are verbally identified as deterministic demo data whenever used.

## Required release inputs before public distribution

- [ ] Required release input — legal operator name and business address for the privacy policy and terms.
- [ ] Required release input — monitored support email address and escalation owner.
- [ ] Required release input — public HTTPS privacy-policy, terms, and support URLs that render without authentication.
- [ ] Required release input — Apple Developer team ID, distribution certificate, provisioning profile, and final App Store Connect app record.
- [ ] Required release input — stable production API origin, hosting owner, alerting owner, and incident-response contact.
- [ ] Required release input — production authentication design. The embedded shared demo bearer token is acceptable only for the closed prototype and must not be treated as a user authentication or durable public secret.
- [ ] Required release input — OpenAI production project, approved structured-output model, usage limits, budget alerts, and a documented decision between default abuse-monitoring retention, Modified Abuse Monitoring, or Zero Data Retention.
- [ ] Required release input — final App Store name, subtitle, description, keywords, category, age rating, copyright, review contact, screenshots, and optional preview video.
- [ ] Required release input — named hardware manufacturer, final bill of materials, battery and charger design, enclosure, labeling, warranty, return path, and applicable electrical/product compliance evidence.
- [ ] Required release input — supported locales. Current transcription and API contracts are fixed to `en-US`.

## App Store and privacy gate

- [ ] Replace the closed-prototype contact language in the privacy policy, terms, and support page with the final operator and monitored contact.
- [ ] Verify App Store privacy answers against the deployed API, hosting logs, OpenAI controls, crash reporting, and any SDKs present in the submitted binary.
- [ ] Verify `PrivacyInfo.xcprivacy` reasons and collected-data declarations against the final binary and current Apple requirements.
- [ ] Confirm the post-session confirmation text still matches the exact insight request body.
- [ ] Publish an account-deletion flow only if accounts are introduced. The current app has no account to delete.
- [ ] Replace or remove the Debug-only local StoreKit and Demo Pro preview before public distribution. If payments are introduced, configure production products, restoration, entitlement validation, subscription terms, and App Store disclosures.
- [ ] Complete export-compliance, content-rights, age-rating, and hardware-accessory questionnaires with final production facts.
- [ ] Remove development-only arguments, fixtures, verbose logs, and non-production API credentials from the archive.
- [ ] Archive a Release build, run Xcode validation, upload it, and test the processed build through internal TestFlight before review.

## Product and hardware gate

- [ ] Measure cue-to-vibration latency on the supported iPhone and production band across a full session; record median, p95, and failure rate.
- [ ] Validate transcription and filler metrics across representative voices, accents, room noise, phone distances, and speaking styles; document limitations in product copy.
- [ ] Validate that acoustic features are not represented as medical, emotion, identity, or disability judgments.
- [ ] Calibrate Soft, Medium, and Strong on the production LRA and enclosure while preserving `soft < medium < strong <= 127`.
- [ ] Test BLE reconnect, sequence rollover, band reboot, driver fault, command burst, and phone interruption behavior.
- [ ] Complete battery runtime, charging, thermal, skin-contact, drop, ingress, and continuous-wear testing before distributing an untethered wearable.
- [ ] Confirm support can diagnose a failure without requesting presentation transcripts or secrets.

## Release record

For every distributed build, record the git commit, marketing version, build number, Xcode version, iOS SDK, API deployment identifier, API model, firmware commit/version, hardware revision, test device/OS, verification command output, known limitations, and approving team member in the release artifact.
