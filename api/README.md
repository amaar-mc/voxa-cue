# Voxa Cue API

Server-only AI routes for the Voxa Cue iOS companion app. Live speech analysis and haptic decisions stay on the iPhone; this service receives presentation text or finalized session data only. It rejects audio fields and does not expose the OpenAI key to the app.

## Run locally

```sh
cp .env.example .env.local
pnpm install
pnpm dev
```

Set all four variables explicitly. `OPENAI_API_KEY` remains server-side, `OPENAI_MODEL` selects the Responses API model, `VOXA_BUILD_ID` identifies the deployed build in probes, and `VOXA_DEMO_API_TOKEN` must be a random value of at least 32 characters.

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
    "pitchRangeSemitones": 8.4,
    "energyRangeDb": 13.2,
    "completedOnTime": true
  },
  "checkpoints": [],
  "cueEvents": []
}
```

`fillersPerMinute` is normalized by speaking time. The nullable metric, checkpoint, and cue-sequence keys remain required and must be sent as JSON `null` when unavailable. Cue delivery status may be `pending`, `accepted`, `completed`, `failed`, `notConnected`, or `suppressed`.

The response matches `contracts/insight-v1.schema.json`. Provider failures return sanitized `502` errors and request-budget expirations return a typed `504 model_request_timed_out`; neither exposes prompts, credentials, or provider error bodies.

## Operations and privacy

The API accepts only canonical UUID `X-Request-Id` values and creates a UUID when the header is missing or malformed. Responses echo the safe identifier. Structured request logs contain only request ID, method, path without query parameters, status, and latency; authorization headers and request bodies are never logged. The insight route validates the app session identifier but strips it before creating provider input. The OpenAI adapter uses zero SDK retries, a 22-second provider timeout, and an abortable 25-second route budget within Vercel's 30-second function limit. JSON responses include no-store and standard browser hardening headers.

The adapter sets `store: false`, which disables Responses API application-state storage. It does not by itself disable OpenAI's default abuse-monitoring logs. Before public release, configure and disclose the production project's actual retention mode, including any approved Modified Abuse Monitoring or Zero Data Retention controls.

## Verify

```sh
pnpm typecheck
pnpm test
pnpm build
```

Deploy the `api` directory as the Vercel project root and configure the four environment variables in Vercel. Set `VOXA_BUILD_ID` to the deployment commit SHA or release identifier.
