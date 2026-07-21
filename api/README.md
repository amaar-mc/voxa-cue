# Voxa Cue API

Server-only AI routes for the Voxa Cue iOS companion app. Live speech analysis and haptic decisions stay on the iPhone. Post-session routes accept tightly bounded text only after an in-app confirmation, reject audio fields, and never expose the OpenAI key to the app.

## Run locally

```sh
cp .env.example .env.local
pnpm install
pnpm dev
```

Set all four variables explicitly. `OPENAI_API_KEY` remains server-side, `OPENAI_MODEL` selects the Responses API model, `VOXA_BUILD_ID` identifies the deployed build in probes, and `VOXA_DEMO_API_TOKEN` must be a random value of at least 32 characters. The checked-in MVP configuration uses `gpt-5.6-luna` for fast, cost-sensitive structured deck plans and post-session coaching.

The shared bearer token is closed-prototype authentication, not a production user-authentication system or durable public secret. Every endpoint except `GET /livez` requires `Authorization: Bearer <VOXA_DEMO_API_TOKEN>`. JSON POST requests also require `Content-Type: application/json`.

## Endpoints

`GET /livez` is an unauthenticated, minimal liveness probe. `GET /health` is its authenticated compatibility alias. Neither contacts OpenAI. `GET /readyz` is authenticated and verifies that the configured OpenAI key can access the configured model through a three-second metadata-only request; it sends no presentation content and performs no generation. Probe bodies contain only status, service, schema version, and build identifier.

`POST /v1/deck-plans` accepts up to 512 KiB:

```json
{
  "schemaVersion": 1,
  "locale": "en-US",
  "title": "Product Pitch",
  "targetDurationSeconds": 180,
  "slides": [
    {
      "slideIndex": 0,
      "title": "The problem",
      "visibleText": "Presenters rush under pressure.",
      "speakerNotes": "Explain why current feedback arrives too late."
    }
  ]
}
```

The response matches `contracts/deck-plan-v1.schema.json`. Checkpoints reference valid input slides, increase monotonically, use unique IDs and anchors, and end at the requested duration.

`POST /v1/insights` accepts up to 256 KiB:

```json
{
  "schemaVersion": 1,
  "sessionId": "session-001",
  "locale": "en-US",
  "transcript": "Finalized presentation transcript.",
  "target": {
    "durationSeconds": 180,
    "paceMinimumWpm": 130,
    "paceMaximumWpm": 160
  },
  "metrics": {
    "durationSeconds": 176.4,
    "speakingSeconds": 138.2,
    "averageWpm": 148,
    "timeInPaceRangeRatio": 0.78,
    "fillerCount": 4,
    "fillersPerMinute": 1.74,
    "talkRatio": 0.783,
    "paceStandardDeviationWpm": 11.2,
    "pauseCount": 7,
    "averagePauseSeconds": 0.9,
    "longestPauseSeconds": 1.8,
    "pitchRangeSemitones": 8.4,
    "energyRangeDb": 13.2,
    "completedOnTime": true
  },
  "checkpoints": [],
  "cueEvents": []
}
```

`fillersPerMinute` is normalized by speaking time. Pace variability and pause fields are optional for compatibility with sessions recorded before those analyzers existed; current clients send explicit JSON `null` when unavailable. The pitch, energy, checkpoint, and cue-sequence nullable keys remain required. Cue delivery status may be `pending`, `accepted`, `completed`, `failed`, `notConnected`, or `suppressed`.

The response matches `contracts/insight-v1.schema.json`. Provider failures return sanitized `502` errors and request-budget expirations return a typed `504 model_request_timed_out`; neither exposes prompts, credentials, or provider error bodies.

`POST /v1/roadmaps` accepts up to 256 KiB. Its strict request contains one selected finalized transcript, that session's target and deterministic metrics, a deterministic filler breakdown, and transcript-free historical aggregates. It accepts no session identifier, name, prior transcript, or audio field. The response matches `contracts/roadmap-v1.schema.json`: a concise summary, zero to three filler focuses whose phrase and count must match the supplied breakdown, three ordered `now`/`next`/`then` steps, and a measurable next-session goal.

`POST /v1/coach-chat` accepts up to 256 KiB. It receives the same selected session context, its validated roadmap, and one to ten typed `user` or `assistant` turns of at most 1,000 characters each; the final turn must be from the user. It is stateless and returns a bounded reply plus up to three suggested prompts matching `contracts/coach-chat-v1.schema.json`. It receives no prior transcript text or raw audio.

## Operations and privacy

The API accepts only canonical UUID `X-Request-Id` values and creates a UUID when the header is missing or malformed. Responses echo the safe identifier. Structured request logs contain only request ID, method, path without query parameters, status, and latency; authorization headers and request bodies are never logged. The legacy insight route strips its app session identifier before provider input, while roadmap and chat contracts accept no identifier. The OpenAI adapter uses zero SDK retries, a 22-second provider timeout, and an abortable 25-second route budget within Vercel's 30-second function limit. JSON responses include no-store and standard browser hardening headers.

The server calls the OpenAI Responses API with `gpt-5.6-luna`, strict JSON Schema output, and `store: false`. This disables Responses application-state storage but does not by itself disable OpenAI's default abuse-monitoring logs. Before public release, configure and disclose the production project's actual retention mode, including any approved Modified Abuse Monitoring or Zero Data Retention controls.

The shared bearer token is sufficient only for the closed prototype. The Release app keeps AI disabled until per-user authentication, rate limits, abuse controls, and spend ceilings are implemented.

## Verify

```sh
pnpm typecheck
pnpm test
pnpm build
```

Deploy the `api` directory as the Vercel project root and configure the four environment variables in Vercel. Set `VOXA_BUILD_ID` to the deployment commit SHA or release identifier.
