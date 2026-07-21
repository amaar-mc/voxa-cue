# Voxa Cue Release Checklist

This checklist separates the closed M&TSI demonstration from a public App Store release. Version values currently declared in `ios/project.yml` are 1.0.0 (build 1), bundle identifier `com.amaarmc.voxacue`, and iOS 26.0 minimum.

## Closed M&TSI demo gate

- [ ] `pnpm install` completes from the repository root.
- [ ] `pnpm verify` passes API checks, Swift package and simulator app tests,
  Debug and credential-free Release generic-device iOS builds,
  privacy-manifest lint, haptic firmware tests/builds, standalone IMU lab
  tests/build, and the isolated gesture-model notebook pipeline.
- [ ] The VoxaCue iOS test target compiles with `xcodebuild build-for-testing` and its tests execute on the exact demonstration iPhone.
- [ ] A signed build installs and launches on the exact demonstration iPhone running iOS 26+.
- [ ] Microphone, Speech Recognition, and Bluetooth permission paths are exercised from a clean install.
- [ ] A 60-second live session produces finalized transcript text, local voice-activity timing, pace, contextual filler, pause, talk-ratio, pitch-range, and energy-range results without retaining an audio file.
- [ ] A complete phone-microphone session works with the API disabled.
- [ ] Authenticated `/readyz` confirms that the deployed OpenAI key can access the configured model without sending presentation content.
- [ ] Captured API traffic contains no raw audio, and representative direct
  audio-shaped keys, URLs, data URIs, encoded headers, and large base64 blocks
  are rejected before provider submission.
- [ ] AI coaching remains locked behind a confirmation dialog naming the transcript, aggregate metrics, and cue-delivery history.
- [ ] Roadmap generation requires its own confirmation and sends exactly one selected finalized transcript, deterministic session metrics and filler counts, and transcript-free historical aggregates; captured traffic contains no prior transcript text.
- [ ] Coach chat requires a separate confirmation and sends only that selected transcript, its roadmap and metrics, and the last one to ten typed turns. Closing chat or deleting any saved session clears the transient conversation.
- [ ] Roadmap output remains tied to its source session and is removed when any contributing session or all local data is deleted.
- [ ] `uvx --with pip platformio test -e native` passes all firmware tests.
- [ ] `uvx --with pip platformio run -e nano_33_iot` succeeds.
- [ ] `uvx --with pip platformio run -e nano_esp32` succeeds.
- [ ] The exact demo Nano, driver, motor, wiring, enclosure, and power source pass the 15-minute wear test in the firmware README.
- [ ] BLE smoke testing confirms accepted and completed acknowledgements, duplicate rejection, all nine physical haptic patterns, firmware 1.1 calm-wave/deadline support, firmware 1.2 session-light progress, pause, overtime, disconnect, and timeout behavior, and firmware 1.3 one-shot D9 buzzer timing without heartbeat retrigger.
- [ ] The app blocks entry to session setup until a Ready Cue Band is connected.
- [ ] Physical RGB verification confirms D6 red, D7 blue, and D8 green, with a
  green-to-yellow-to-orange-to-red progression and flashing red overtime.
- [ ] A forced DRV2605L fault confirms fail-low behavior and successful bounded
  one-second recovery attempts without a reboot.
- [ ] Airplane-mode testing confirms that live coaching and BLE haptics continue without the API.
- [ ] No real API key or bearer token is present in Git history, source, generated project files, logs, screenshots, or demo materials.
- [ ] `-demoScenario` screens and metrics are verbally identified as deterministic demo data whenever used.

## Required release inputs before public distribution

- [ ] Required release input — legal operator name and business address for the privacy policy and terms.
- [ ] Required release input — monitored support email address and escalation owner.
- [ ] Required release input — enable GitHub private vulnerability reporting or
  publish a monitored private security mailbox and response owner.
- [ ] Required release input — public HTTPS privacy-policy, terms, and support URLs that render without authentication.
- [ ] Required release input — Apple Developer team ID, distribution certificate, provisioning profile, and final App Store Connect app record.
- [ ] Required release input — stable production API origin, hosting owner, alerting owner, and incident-response contact.
- [ ] Required release input — production per-user or per-device authentication with revocation and key rotation. The embedded shared demo bearer token is acceptable only for the closed prototype.
- [ ] Required release input — authenticated BLE enrollment, trusted peripheral
  identity, replay-resistant commands, an explicit re-pair/reset path, and
  connection, command-rate, and motor duty-cycle limits.
- [ ] Required release input — OpenAI production project, approved structured-output model, per-user rate limits, abuse controls, spend ceilings, budget alerts, and a documented decision between default abuse-monitoring retention, Modified Abuse Monitoring, or Zero Data Retention.
- [ ] Required release input — final App Store name, subtitle, description, keywords, category, age rating, copyright, review contact, screenshots, and optional preview video.
- [ ] Required release input — named hardware manufacturer, final bill of materials, battery and charger design, enclosure, labeling, warranty, return path, and applicable electrical/product compliance evidence.
- [ ] Required release input — supported locales. Current transcription and API contracts are fixed to `en-US`.

## App Store and privacy gate

- [ ] Replace the closed-prototype contact language in the privacy policy, terms, and support page with the final operator and monitored contact.
- [ ] Verify App Store privacy answers against the deployed API, hosting logs, OpenAI controls, crash reporting, and any SDKs present in the submitted binary.
- [ ] Verify `PrivacyInfo.xcprivacy` reasons and collected-data declarations against the final binary and current Apple requirements.
- [ ] Confirm the insight, roadmap, and coach-chat confirmation text matches each exact request body and clearly distinguishes the selected transcript from transcript-free history.
- [ ] Keep Release AI compile-disabled until production authentication, rate limits, and spend ceilings pass review.
- [ ] Publish an account-deletion flow only if accounts are introduced. The current app has no account to delete.
- [ ] Replace or remove the Debug-only local StoreKit and Demo Pro preview before public distribution. If payments are introduced, configure production products, restoration, entitlement validation, subscription terms, and App Store disclosures.
- [ ] Complete export-compliance, content-rights, age-rating, and hardware-accessory questionnaires with final production facts.
- [ ] Remove development-only arguments, fixtures, verbose logs, and non-production API credentials from the archive.
- [ ] Archive a Release build, run Xcode validation, upload it, and test the processed build through internal TestFlight before review.

## Product and hardware gate

- [ ] Measure cue-to-vibration latency on the supported iPhone and production band across a full session; record median, p95, and failure rate.
- [ ] Validate transcription and filler metrics across representative voices, accents, room noise, phone distances, and speaking styles; document limitations in product copy.
- [ ] Validate that acoustic features are not represented as medical, emotion, identity, or disability judgments.
- [ ] Calibrate Soft, Medium, and Strong on the production ERM and enclosure while preserving `soft < medium < strong <= 127`.
- [ ] Test BLE reconnect, sequence rollover, band reboot, driver fault, command burst, and phone interruption behavior.
- [ ] Require a recent successful haptic-driver health or actuation check before
  session start and fail closed after a reported driver fault.
- [ ] Add and validate an independent hardware watchdog, current and thermal
  protection, and a hard motor cut-off for the final power path.
- [ ] Version the SwiftData schema; test migrations, file-protection class,
  backup exclusions, restore behavior, and non-destructive store recovery on a
  shipping build.
- [ ] Complete battery runtime, charging, thermal, skin-contact, drop, ingress, and continuous-wear testing before distributing an untethered wearable.
- [ ] Confirm support can diagnose a failure without requesting presentation transcripts or secrets.

## Release record

For every distributed build, record the git commit, marketing version, build number, Xcode version, iOS SDK, API deployment identifier, API model, firmware commit/version, hardware revision, test device/OS, verification command output, known limitations, and approving team member in the release artifact.
