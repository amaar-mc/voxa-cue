import { Hono } from "hono";
import type { Context } from "hono";
import type { ZodType } from "zod";

import { readJsonBody, secureTokenEquals } from "./http";
import type { StructuredOutputGenerator } from "./openai";
import {
  createDeckPlanInput,
  createInsightInput,
  deckPlanInstructions,
  insightInstructions,
} from "./prompts";
import {
  deckPlanJsonSchema,
  deckPlanRequestSchema,
  deckPlanResponseSchema,
  insightJsonSchema,
  insightRequestSchema,
  insightResponseSchema,
} from "./schemas";
import type {
  DeckPlanRequest,
  DeckPlanResponse,
  InsightRequest,
  InsightResponse,
} from "./schemas";

const deckPlanMaximumBytes = 512 * 1_024;
const insightMaximumBytes = 256 * 1_024;

type ErrorCode =
  | "audio_not_accepted"
  | "invalid_json"
  | "invalid_model_response"
  | "invalid_request"
  | "model_request_failed"
  | "not_found"
  | "payload_too_large"
  | "unauthorized"
  | "unsupported_media_type";

type ErrorStatus = 400 | 401 | 404 | 413 | 415 | 422 | 502;

type ValidationIssue = {
  readonly path: string;
  readonly message: string;
};

export type AppDependencies = {
  readonly demoApiToken: string;
  readonly generateStructuredOutput: StructuredOutputGenerator;
};

const jsonError = (
  context: Context,
  status: ErrorStatus,
  code: ErrorCode,
  message: string,
  issues: readonly ValidationIssue[],
) =>
  context.json(
    {
      error: {
        code,
        message,
        issues,
      },
    },
    status,
  );

const zodIssues = (schemaIssues: readonly { path: PropertyKey[]; message: string }[]) =>
  schemaIssues.slice(0, 20).map((issue) => ({
    path: issue.path.map((component) => String(component)).join("."),
    message: issue.message,
  }));

const parseBody = async <Output>(
  context: Context,
  maximumBytes: number,
  schema: ZodType<Output>,
): Promise<
  | { readonly ok: true; readonly value: Output }
  | { readonly ok: false; readonly response: Response }
> => {
  const body = await readJsonBody(context.req.raw, maximumBytes);
  if (!body.ok) {
    return {
      ok: false,
      response: jsonError(
        context,
        body.status,
        body.code,
        body.message,
        [],
      ),
    };
  }

  const parsed = schema.safeParse(body.value);
  if (!parsed.success) {
    return {
      ok: false,
      response: jsonError(
        context,
        422,
        "invalid_request",
        "Request did not match the endpoint contract.",
        zodIssues(parsed.error.issues),
      ),
    };
  }

  return { ok: true, value: parsed.data };
};

const validateDeckPlanSemantics = (
  plan: DeckPlanResponse,
  request: DeckPlanRequest,
): boolean => {
  if (plan.title !== request.title) {
    return false;
  }

  const validSlideIndexes = new Set(
    request.slides.map((slide) => slide.slideIndex),
  );
  const checkpointIds = new Set<string>();
  let previousSlideIndex = -1;
  let previousCumulativeSeconds = 0;

  for (const checkpoint of plan.checkpoints) {
    if (
      !validSlideIndexes.has(checkpoint.slideIndex) ||
      checkpointIds.has(checkpoint.id) ||
      checkpoint.id !== `slide-${checkpoint.slideIndex}` ||
      checkpoint.slideIndex <= previousSlideIndex ||
      checkpoint.targetCumulativeSeconds <= previousCumulativeSeconds
    ) {
      return false;
    }

    const normalizedAnchors = checkpoint.anchorTerms.map((anchor) =>
      anchor.toLocaleLowerCase("en-US"),
    );
    if (new Set(normalizedAnchors).size !== normalizedAnchors.length) {
      return false;
    }

    checkpointIds.add(checkpoint.id);
    previousSlideIndex = checkpoint.slideIndex;
    previousCumulativeSeconds = checkpoint.targetCumulativeSeconds;
  }

  return previousCumulativeSeconds === request.targetDurationSeconds;
};

const generateDeckPlan = async (
  dependencies: AppDependencies,
  request: DeckPlanRequest,
): Promise<DeckPlanResponse | null> => {
  const generated = await dependencies.generateStructuredOutput({
    schemaName: "voxa_cue_deck_plan_v1",
    instructions: deckPlanInstructions,
    input: createDeckPlanInput(request),
    jsonSchema: deckPlanJsonSchema as unknown as Record<string, unknown>,
    maximumOutputTokens: 6_000,
  });
  const parsed = deckPlanResponseSchema.safeParse(generated);
  if (!parsed.success || !validateDeckPlanSemantics(parsed.data, request)) {
    return null;
  }
  return parsed.data;
};

const generateInsight = async (
  dependencies: AppDependencies,
  request: InsightRequest,
): Promise<InsightResponse | null> => {
  const generated = await dependencies.generateStructuredOutput({
    schemaName: "voxa_cue_insight_v1",
    instructions: insightInstructions,
    input: createInsightInput(request),
    jsonSchema: insightJsonSchema as unknown as Record<string, unknown>,
    maximumOutputTokens: 2_500,
  });
  const parsed = insightResponseSchema.safeParse(generated);
  return parsed.success ? parsed.data : null;
};

export const createApp = (dependencies: AppDependencies): Hono => {
  const app = new Hono();
  const expectedAuthorization = `Bearer ${dependencies.demoApiToken}`;

  app.use("*", async (context, next) => {
    const requestId = crypto.randomUUID();
    context.header("X-Request-Id", requestId);
    context.header("Cache-Control", "no-store");
    context.header("X-Content-Type-Options", "nosniff");

    const authorization = context.req.header("authorization") ?? "";
    if (!secureTokenEquals(authorization, expectedAuthorization)) {
      context.header("WWW-Authenticate", 'Bearer realm="Voxa Cue API"');
      return jsonError(
        context,
        401,
        "unauthorized",
        "A valid Voxa Cue demo bearer token is required.",
        [],
      );
    }

    await next();
  });

  app.get("/health", (context) =>
    context.json({
      status: "ok",
      service: "voxa-cue-api",
      schemaVersion: 1,
    }),
  );

  app.post("/v1/deck-plans", async (context) => {
    const parsedRequest = await parseBody(
      context,
      deckPlanMaximumBytes,
      deckPlanRequestSchema,
    );
    if (!parsedRequest.ok) {
      return parsedRequest.response;
    }

    try {
      const plan = await generateDeckPlan(dependencies, parsedRequest.value);
      if (plan === null) {
        return jsonError(
          context,
          502,
          "invalid_model_response",
          "The coaching service returned an invalid deck plan.",
          [],
        );
      }
      return context.json(plan, 200);
    } catch {
      return jsonError(
        context,
        502,
        "model_request_failed",
        "The coaching service is temporarily unavailable.",
        [],
      );
    }
  });

  app.post("/v1/insights", async (context) => {
    const parsedRequest = await parseBody(
      context,
      insightMaximumBytes,
      insightRequestSchema,
    );
    if (!parsedRequest.ok) {
      return parsedRequest.response;
    }

    try {
      const insight = await generateInsight(dependencies, parsedRequest.value);
      if (insight === null) {
        return jsonError(
          context,
          502,
          "invalid_model_response",
          "The coaching service returned invalid insights.",
          [],
        );
      }
      return context.json(insight, 200);
    } catch {
      return jsonError(
        context,
        502,
        "model_request_failed",
        "The coaching service is temporarily unavailable.",
        [],
      );
    }
  });

  app.notFound((context) =>
    jsonError(context, 404, "not_found", "Endpoint not found.", []),
  );

  app.onError((_error, context) =>
    context.json(
      {
        error: {
          code: "internal_error",
          message: "The API could not complete the request.",
          issues: [],
        },
      },
      500,
    ),
  );

  return app;
};
