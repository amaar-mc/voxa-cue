# Voxa Cue API

Server-only AI routes for the Voxa Cue iOS companion app. Live speech analysis and haptic decisions stay on the iPhone; this service receives presentation text or finalized session data only. It rejects audio fields and does not expose the OpenAI key to the app.

## Run locally

```sh
cp .env.example .env.local
pnpm install
pnpm dev
```

Set all three variables explicitly. `OPENAI_API_KEY` remains server-side, `OPENAI_MODEL` selects the Responses API model, and `VOXA_DEMO_API_TOKEN` must be a random value of at least 32 characters.

All endpoints require `Authorization: Bearer <VOXA_DEMO_API_TOKEN>`. JSON POST requests also require `Content-Type: application/json`.

## Endpoints

`GET /health` returns API readiness without calling OpenAI.

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

The response matches `contracts/insight-v1.schema.json`. Provider failures return sanitized `502` errors; they never expose prompts, credentials, or provider error bodies.

## Verify

```sh
pnpm typecheck
pnpm test
pnpm build
```

Deploy the `api` directory as the Vercel project root and configure the three environment variables in Vercel.
