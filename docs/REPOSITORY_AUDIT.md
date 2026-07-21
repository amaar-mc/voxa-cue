# Repository audit

Audit date: July 21, 2026

## Scope and method

This audit covered the tracked repository, Git history, generated-build and
secret boundaries, the SwiftUI application and Swift packages, the Hono API,
shared JSON and BLE contracts, Nano firmware, the IMU/gesture lab, dependency
manifests, tests, and operator documentation.

The review combined source inspection, contract tracing, dead-code searches,
targeted secret-history checks, dependency audits, and automated builds and
tests. It was not a penetration test, App Store review, radio-security
assessment, electrical-safety certification, or physical-device validation.

## Verdict

No P0 issue was found. After the fixes in this change set, the supervised,
closed, on-device prototype is acceptable for its M&TSI demonstration scope.
The live coaching path remains local and does not depend on the API.

Public API access, public wearable distribution, and unattended hardware use
are blocked by the P1 items below. Passing automated tests does not close those
identity, abuse, persistence, or physical-safety gaps.

## Verified controls

- The iPhone microphone is the only audio source. Transcription, acoustic
  analysis, live metrics, cue selection, presentation parsing, slide timing,
  persistence, and BLE control run on-device. Raw audio is neither persisted
  nor uploaded.
- The API receives bounded JSON only after explicit post-session consent. It
  has no audio, multipart, presentation-file, slide-content, or deck-plan
  route. The OpenAI key remains server-side, and Release iOS builds fail closed
  with AI disabled.
- API inputs use strict Zod contracts, bounded streaming request reads,
  defense-in-depth audio-content rejection, bounded model deadlines, zero SDK
  retries, sanitized errors, safe request IDs, no-store responses, restrictive
  browser headers, and metadata-only request logs.
- OpenAI Responses calls use the allowlisted `gpt-5.6-luna` model, explicit
  `none` reasoning, strict JSON Schema output, and `store: false`.
  Roadmap filler counts are checked against deterministic app-supplied
  evidence. This validates structure and selected facts, not every free-text
  coaching claim.
- Local PDF and PowerPoint parsing applies file, archive-entry, expansion, and
  text limits and rejects unsafe archive/XML relationships. Presentation text
  stays out of the network path.
- BLE packets are versioned and bounded. Firmware validates command shape,
  intensity, repeat count, sequence, light mode, and progress; reports accepted,
  completed, rejected, and driver-fault states; rejects duplicate completed
  sequences; and turns session outputs off after disconnect or heartbeat loss.
  These integrity checks are not device authentication.
- Local deletion covers sessions, transcript segments, metrics, cue events,
  checkpoints, insights, roadmaps, and imported deck records. Failed SwiftData
  mutations now roll back their pending changes instead of leaving a dirty
  context.
- Targeted tracked-file and history scans found placeholders and explicit test
  tokens, but no real OpenAI key, GitHub token, or private key. Local API and
  signing configuration files are ignored.

## Fixes made in this audit

| Area | Change | Evidence |
| --- | --- | --- |
| Presentation privacy | Removed the remote deck-plan route, schemas, prompt, shared contract, dead iOS API client, and duplicate app planner. Local guided presentations now use the shared deterministic timing implementation only. | `api/src`, `api/test`, `contracts`, `ios/Packages/VoxaKit/Sources/VoxaRuntime/VoxaAPIClient.swift`, `ios/VoxaCue/App/AppModel.swift` |
| Request hardening | Replaced recursive JSON inspection with an iterative scan and rejected audio-shaped keys, data URIs, direct audio-file URLs, common encoded audio headers, and large base64 blocks. Added deep-nesting and audio-content regression coverage. | `api/src/http.ts`, `api/test/http.test.ts` |
| API operations | Preserved sanitized responses while mapping provider throttling to bounded `429` retry guidance and provider authentication or outage responses to `503`. | `api/src/app.ts`, `api/test/app.test.ts` |
| Model configuration | Restricted runtime configuration to the reviewed cost-sensitive `gpt-5.6-luna` model and made `none` reasoning explicit instead of inheriting a costlier model default. | `api/src/schemas.ts`, `api/src/openai.ts`, `api/test` |
| Data integrity | Added rollback on failed session, deck, insight, roadmap, per-session deletion, and all-data SwiftData mutations. | `ios/Packages/VoxaKit/Sources/VoxaRuntime/Persistence.swift` |
| Supply chain | Raised the gesture-classifier test dependency floor from vulnerable `pytest 8.4.2` to `pytest 9.0.3`; the refreshed lockfile resolves `9.1.1`. | `ml/gesture-classifier/pyproject.toml`, `ml/gesture-classifier/uv.lock` |
| Secret hygiene | Expanded root ignores from two filenames to all `.env*` variants while retaining checked-in `.env.example` templates. | `.gitignore` |
| Firmware correctness | Corrected the Nano RGB channel map to red D6, green D8, blue D7 and aligned its native assertion. | `firmware/voxa-wearable/include/voxa_session_light.hpp`, `firmware/voxa-wearable/test/test_session_light/test_main.cpp` |
| Driver resilience | On DRV2605L loss, firmware now disables output, rejects the command, and retries initialization at a bounded one-second interval with rollover-tested state logic. | `firmware/voxa-wearable/src/main.cpp`, `firmware/voxa-wearable/include/voxa_driver_health.hpp`, `firmware/voxa-wearable/test/test_driver_health` |
| Lifecycle privacy | Inactive app snapshots now receive a neutral privacy cover, and leaving the foreground during the visible countdown cancels startup without breaking the system permission-sheet phase. Session-name input is capped at 80 characters. | `ios/VoxaCue/App/VoxaCueApp.swift`, `ios/VoxaCue/App/AppModel.swift`, `ios/VoxaCue/Views/SessionSetupView.swift` |
| Disclosure | Added security-policy instructions that avoid public vulnerability details, direct reporters to request a private channel from the owner, and require a verified private reporting path before release. Documented BLE v1 as an unauthenticated prototype protocol and aligned progress validation wording with the implementation. | `SECURITY.md`, `contracts/ble-v1.md` |

## P1 public-release blockers

| Blocker | Why it blocks release | Required closure |
| --- | --- | --- |
| API identity and cost control | One shared demo bearer token authorizes every device. There is no per-user quota, rate limit, idempotency key, abuse control, or spend ceiling. | Deploy revocable user- or device-scoped authentication, rate limits, quotas, idempotency, budget alerts, spend ceilings, and verified provider-retention settings before enabling Release AI. |
| Production entitlement | The checked-in StoreKit flow is explicitly a local test product plus a demo override. | Configure the App Store Connect product, subscription disclosures, restore path, verified entitlement lifecycle, and remove the demo override from distributed builds. |
| BLE identity and actuation control | Protocol v1 has no pairing, bonding, encryption requirement, or application authentication. The app trusts the first compatible advertiser, and packet bounds do not impose a session-level motor duty limit. | Add authenticated enrollment and trusted peripheral identity, replay-resistant authenticated commands, connection/rate limits, motor duty-cycle limits, and an explicit re-pair/reset flow. |
| Band-health gating | CoreBluetooth can remain transport-ready after firmware rejects a command with `driverFault`; session setup gates on connection, not confirmed haptic-driver health. Firmware recovery alone cannot prove that a cue can actuate. | Track hardware health separately from link state, require a recent successful health/actuation check before session start, and fail closed after driver faults. |
| Hardware fail-safe | Software timeouts and driver retries do not replace an independent watchdog, current/thermal protection, or a hard motor cut-off. | Validate the final schematic and power path, add an independent fail-safe/watchdog, and complete current, thermal, battery, fault-injection, and continuous-wear testing. |
| Durable local-data lifecycle | SwiftData has no explicit production migration plan. File-protection class, backup behavior, restore behavior, and failure recovery have not been verified on the shipping device/build. | Version the schema and test migrations, verify iOS file protection and backup exclusions, define non-destructive recovery, and align the privacy disclosure with measured behavior. |

## P2 backlog

| Surface | Finding | Required work |
| --- | --- | --- |
| AI grounding | Strict structured output bounds shape, but insight and chat prose can still make unsupported qualitative claims. | Require machine-checkable evidence references for quantitative claims, reject unsupported values, and preserve uncertainty in the UI. |
| API operations | `/readyz` verifies model metadata access only. There is no private structured-generation canary, aggregate token/latency telemetry, or stable pseudonymous safety identifier. | Add a private scheduled canary, privacy-safe operational metrics, alerting, and a safety identifier after production identity exists. |
| Model change control | The runtime model is allowlisted, but the repository has no versioned evaluation corpus or rollout procedure for a future model change. | Add representative quality, latency, structured-output, and cost evaluations before changing the allowlist. |
| CI and dependencies | No checked-in CI runs verification, secret scanning, or dependency audits. Firmware platforms and libraries are pinned, but the PlatformIO CLI invoked through `uvx --with pip platformio` is not. | Add required CI gates and pin the PlatformIO CLI used by local and CI verification. |
| iOS network bounds | The API client checks its response cap after URLSession delivers the body. | Enforce the limit during transfer with a URLSession delegate or equivalent bounded transport. |
| Local privacy | The finalized transcript is stored in `SessionRecord` and again as timestamped segment records. | Remove redundant text storage or document why timestamped segment retention is necessary. App-switcher snapshots are now obscured. |
| Persistence failure UX | If the durable store cannot open, the app falls back to temporary in-memory storage for that launch. | Make the temporary mode unmistakable, prevent users from assuming sessions will persist, and test recovery without deleting the original store. |
| Analytics completeness | Timed slide sessions currently persist an empty checkpoint-result list even though checkpoint record and API surfaces remain. | Either populate deterministic checkpoint outcomes or remove the unused analytics contract and UI claims. |
| Filler trust | The live filler count shown to the user and the volatile, cooldown-gated cluster input that triggers a cue are not presented as distinct measurements. | Label the displayed count and cue window clearly and test that settings copy matches runtime behavior. |
| UI verification | Automated UI coverage does not adequately exercise Dynamic Type, VoiceOver, narrow screens, and destructive/privacy flows. | Add focused accessibility and UI tests. Countdown cancellation, an app-switcher privacy cover, and an 80-character session-name input cap are now implemented. |
| Firmware evidence | Native tests exercise extracted protocol/state helpers, not the Arduino `main.cpp`, CoreBluetooth exchange, I2C sensor/driver behavior, or electrical outputs. | Add hardware-in-loop smoke tests and record latency, reconnect, fault, LED, buzzer, and motor measurements on the exact release hardware. |
| IMU diagnostic | The separate IMU lab exposes readable BLE movement telemetry without authentication. | Keep the lab firmware out of production artifacts, label it diagnostic-only, and authenticate or remove telemetry before any field use. |

## P3 cleanup

- Remove the unused `DeckRecord`/`saveDeck` persistence surface and unused
  semantic matcher implementations, or restore a tested local consumer.
- Add an explicit repository license or a clear all-rights-reserved notice
  before accepting outside contributions. A public GitHub repository does not
  itself grant reuse rights.
- Keep the BLE contract, firmware README, architecture, privacy copy, API docs,
  and root README synchronized whenever a protocol or data boundary changes.

## Verification evidence

The following checks were run against the audit change set:

| Check | Result |
| --- | --- |
| `pnpm api:typecheck` | Passed |
| `pnpm api:test` | Passed: 4 files, 45 tests |
| `pnpm api:build` | Passed |
| `pnpm verify` | Passed: API, Swift packages, simulator app tests, Debug and Release iOS builds, privacy lint, BLE tools, both wearable targets, IMU lab, and gesture-classifier pipeline |
| Follow-up `pnpm ios:test` after deadline-semantics correction | Passed: 44 runtime and 73 core tests |
| `pnpm --dir api audit --prod --audit-level high` | No known vulnerabilities found |
| `uvx pip-audit --path ml/gesture-classifier/.venv/lib/python3.12/site-packages --progress-spinner off` | No known vulnerabilities found; the local non-PyPI project package was skipped |
| Tracked-file and Git-history secret scan | No real credential pattern found; placeholders and test tokens were reviewed as non-secrets |

`pnpm verify` is the authoritative repository-wide acceptance gate. It passed
on this change set and covers the API, Swift packages, simulator tests, generic
iPhone builds, Release configuration, BLE tools, firmware targets, the IMU lab,
and the gesture-classifier pipeline.

Automated evidence does not validate the exact iPhone, microphone permissions,
speech accuracy, radio environment, physical DRV2605L and ERM output, RGB pin
wiring, buzzer, recovery behavior, latency, battery, thermal behavior, or wear
safety. Those checks remain explicit physical gates in
`docs/RELEASE_CHECKLIST.md` and `firmware/voxa-wearable/README.md`.
