# Backend audit

Audit date: July 21, 2026

## Verdict

- **Closed M&TSI prototype:** approved. The API is typed, contract-validated, privacy-bounded, tested, and ready to connect after the four environment values are supplied.
- **Public production service:** not approved. The closed-demo bearer token is intentionally not a public authentication design, and Release builds intentionally disable AI coaching.

The backend is optional. A backend outage cannot interrupt transcription, analytics, cue decisions, BLE, or haptics because the live path runs entirely on the iPhone.

## Verified

- 45 API tests pass, including authentication, model allowlisting, input limits,
  audio-content filtering, deep-JSON handling, bounded provider retry responses,
  timeouts, malformed provider output, roadmap evidence checks, and chat-history
  validation.
- Strict TypeScript type-check and production bundle pass.
- `openai.responses.create` uses allowlisted `gpt-5.6-luna`, explicit `none`
  reasoning, strict JSON Schema output, `store: false`, zero SDK retries, and
  bounded timeouts.
- The API has no binary, multipart, audio-file, or presentation-file route. Before schema validation, its JSON guard rejects audio-shaped keys, audio data URIs, direct audio-file URLs, common encoded audio headers, and large base64 blocks. This targeted filter is defense in depth, not a semantic proof of arbitrary text content.
- Roadmaps submit exactly one confirmed finalized transcript, its deterministic metrics and filler counts, and transcript-free historical aggregates. Coach chat separately confirms and sends that selected transcript, its roadmap and metrics, and at most 10 recent typed turns. Neither path sends prior transcript text.
- PDF and PowerPoint parsing, extracted slide text, even timing, and custom per-slide timing stay on the iPhone. The API has no deck-plan route, prompt, request schema, or response contract.
- The API does not return or intentionally log provider bodies, credentials, bearer tokens, transcripts, or presentation content. Hosting-provider metadata retention remains deployment-dependent.
- Dependency audit reports no known production dependency vulnerabilities.

## Public-release gaps

| Severity | Gap | Evidence | Required public-release change |
| --- | --- | --- | --- |
| P1 | One shared bearer token protects every user and device | `api/src/app.ts`, `ios/VoxaCue/App/AppConfiguration.swift` | Replace it with user- or device-scoped authentication, revocation, and key rotation |
| P1 | No per-user rate limit, quota, spend ceiling, or idempotency protection | `api/src/app.ts` | Add rate limits, spend ceilings, abuse controls, quotas, and idempotency for generation routes |
| P1 | Release builds compile-disable AI coaching | `ios/VoxaCue/App/AppConfiguration.swift`, `ios/Config/ReleaseBuildSettings.xcconfig` | Enable only after public authentication exists; the current fail-closed behavior is correct |
| P2 | Provider authentication/configuration failures and provider outages share one sanitized 503 class | `api/src/app.ts` | Add privacy-safe operator telemetry that distinguishes configuration from outage; client-facing 429 retry windows are already preserved and bounded |
| P2 | `/readyz` checks model access but performs no structured generation canary | `api/src/openai.ts` | Add a private scheduled canary and alerting outside the request path |
| P2 | No aggregate token/latency metrics or stable safety identifier | `api/src/openai.ts` | Record privacy-safe usage metrics and pass a pseudonymous safety identifier after production identity exists |
| P2 | The iOS response-size cap is enforced after the body downloads | `ios/Packages/VoxaKit/Sources/VoxaRuntime/VoxaAPIClient.swift` | Enforce the cap while streaming or through URLSession delegate limits |
| P2 | JSON audio-content filtering is signature-based rather than a semantic guarantee | `api/src/http.ts` | Keep audio and presentation upload routes absent, test known encodings, monitor authenticated misuse, and avoid describing the filter as proof of arbitrary text provenance |
| P2 | Strict response schemas bound shape but do not prove every free-text coaching claim is supported | `api/src/app.ts`, `api/src/prompts.ts` | Add machine-checkable evidence references for quantitative claims and retain explicit uncertainty copy |

## Model and data boundary

`gpt-5.6-luna` is used only for confirmed post-session insights, roadmaps, and coach replies. There are exactly three generation routes. Presentation parsing and timing are local and have no API or model path. The model does not transcribe audio, calculate pace, count the deterministic filler evidence supplied to roadmap and chat, select a haptic, or communicate with the wearable; those behaviors are local and deterministic.

Roadmaps are returned to the app and persisted locally against their source session. Because they also use longitudinal aggregates, deleting any contributing session invalidates the saved roadmap. Chat calls are stateless; the API has no conversation database, and the app clears chat turns when the sheet closes or any saved session is deleted. Release builds correctly keep AI disabled until per-user authentication, rate limits, abuse controls, and spend ceilings exist.

`store: false` disables OpenAI Responses application-state storage. It does not by itself disable provider abuse-monitoring retention. The production OpenAI project retention mode and privacy disclosure must match the actual account controls before public release.

## Re-run

```sh
pnpm api:typecheck
pnpm api:test
pnpm api:build
pnpm audit --prod
```
