import { Hono } from "hono";
import type { Context } from "hono";
import type { ZodType } from "zod";

import { readJsonBody, secureTokenEquals } from "./http.js";
import {
  createStructuredGenerationTimeoutError,
  isStructuredGenerationTimeoutError,
} from "./openai.js";
import type { StructuredOutputGenerator } from "./openai.js";
import {
  coachChatInstructions,
  createCoachChatInput,
  createInsightInput,
  createRoadmapInput,
  insightInstructions,
  roadmapInstructions,
} from "./prompts.js";
import {
  coachChatJsonSchema,
  coachChatRequestSchema,
  coachChatResponseSchema,
  insightJsonSchema,
  insightRequestSchema,
  insightResponseSchema,
  roadmapJsonSchema,
  roadmapRequestSchema,
  roadmapResponseSchema,
} from "./schemas.js";
import type {
  CoachChatRequest,
  CoachChatResponse,
  InsightRequest,
  InsightResponse,
  RoadmapRequest,
  RoadmapResponse,
} from "./schemas.js";

const insightMaximumBytes = 256 * 1_024;
const roadmapMaximumBytes = 256 * 1_024;
const coachChatMaximumBytes = 256 * 1_024;

type ErrorCode =
  | "audio_not_accepted"
  | "invalid_json"
  | "invalid_model_response"
  | "invalid_request"
  | "model_request_failed"
  | "model_request_timed_out"
  | "not_found"
  | "payload_too_large"
  | "rate_limited"
  | "unauthorized"
  | "unsupported_media_type";

type ErrorStatus = 400 | 401 | 404 | 413 | 415 | 422 | 429 | 502 | 503 | 504;

type ValidationIssue = {
  readonly path: string;
  readonly message: string;
};

export type RequestLogEvent = {
  readonly requestId: string;
  readonly method: string;
  readonly path: string;
  readonly status: number;
  readonly latencyMilliseconds: number;
};

export type RequestLogger = (event: RequestLogEvent) => void;
export type ReadinessCheck = () => Promise<boolean>;

export type AppDependencies = {
  readonly buildIdentifier: string;
  readonly demoApiToken: string;
  readonly generateStructuredOutput: StructuredOutputGenerator;
  readonly modelRequestTimeoutMilliseconds: number;
  readonly readinessCheck: ReadinessCheck;
  readonly requestLogger: RequestLogger;
};

const serviceName = "voxa-cue-api";
const schemaVersion = 1;
const safeRequestIdPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;

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

const generateInsight = async (
  dependencies: AppDependencies,
  request: InsightRequest,
  signal: AbortSignal,
): Promise<InsightResponse | null> => {
  const generated = await dependencies.generateStructuredOutput({
    schemaName: "voxa_cue_insight_v1",
    instructions: insightInstructions,
    input: createInsightInput(request),
    jsonSchema: insightJsonSchema as unknown as Record<string, unknown>,
    maximumOutputTokens: 2_500,
    signal,
  });
  const parsed = insightResponseSchema.safeParse(generated);
  return parsed.success ? parsed.data : null;
};

const normalizedPhrase = (phrase: string): string =>
  phrase.toLocaleLowerCase("en-US").replaceAll(/\s+/gu, " ").trim();

const validateRoadmapSemantics = (
  roadmap: RoadmapResponse,
  request: RoadmapRequest,
): boolean => {
  const expectedPhases = ["now", "next", "then"] as const;
  if (
    !roadmap.steps.every(
      (step, index) => step.phase === expectedPhases[index],
    )
  ) {
    return false;
  }

  const suppliedFillers = new Map(
    request.session.fillerBreakdown.map((item) => [
      normalizedPhrase(item.phrase),
      item.count,
    ]),
  );
  const returnedPhrases = new Set<string>();
  return roadmap.focusFillers.every((item) => {
    const phrase = normalizedPhrase(item.phrase);
    if (returnedPhrases.has(phrase) || suppliedFillers.get(phrase) !== item.count) {
      return false;
    }
    returnedPhrases.add(phrase);
    return true;
  });
};

const generateRoadmap = async (
  dependencies: AppDependencies,
  request: RoadmapRequest,
  signal: AbortSignal,
): Promise<RoadmapResponse | null> => {
  const generated = await dependencies.generateStructuredOutput({
    schemaName: "voxa_cue_roadmap_v1",
    instructions: roadmapInstructions,
    input: createRoadmapInput(request),
    jsonSchema: roadmapJsonSchema as unknown as Record<string, unknown>,
    maximumOutputTokens: 2_200,
    signal,
  });
  const parsed = roadmapResponseSchema.safeParse(generated);
  if (!parsed.success || !validateRoadmapSemantics(parsed.data, request)) {
    return null;
  }
  return parsed.data;
};

const generateCoachChat = async (
  dependencies: AppDependencies,
  request: CoachChatRequest,
  signal: AbortSignal,
): Promise<CoachChatResponse | null> => {
  const generated = await dependencies.generateStructuredOutput({
    schemaName: "voxa_cue_coach_chat_v1",
    instructions: coachChatInstructions,
    input: createCoachChatInput(request),
    jsonSchema: coachChatJsonSchema as unknown as Record<string, unknown>,
    maximumOutputTokens: 700,
    signal,
  });
  const parsed = coachChatResponseSchema.safeParse(generated);
  return parsed.success ? parsed.data : null;
};

const runWithModelRequestDeadline = async <Output>(
  requestSignal: AbortSignal,
  timeoutMilliseconds: number,
  operation: (signal: AbortSignal) => Promise<Output>,
): Promise<Output> => {
  const controller = new AbortController();
  let rejectCancellation: ((reason: Error) => void) | undefined;
  const cancellation = new Promise<never>((_resolve, reject) => {
    rejectCancellation = reject;
  });
  const abort = () => {
    if (!controller.signal.aborted) {
      const error = createStructuredGenerationTimeoutError();
      controller.abort(error);
      rejectCancellation?.(error);
    }
  };

  if (requestSignal.aborted) {
    abort();
  } else {
    requestSignal.addEventListener("abort", abort, { once: true });
  }
  const timeout = setTimeout(abort, timeoutMilliseconds);

  try {
    return await Promise.race([operation(controller.signal), cancellation]);
  } catch (error) {
    if (controller.signal.aborted) {
      throw createStructuredGenerationTimeoutError();
    }
    throw error;
  } finally {
    clearTimeout(timeout);
    requestSignal.removeEventListener("abort", abort);
  }
};

const providerStatus = (error: unknown): number | null => {
  if (error === null || typeof error !== "object" || !("status" in error)) {
    return null;
  }
  const status = error.status;
  return typeof status === "number" && Number.isInteger(status) ? status : null;
};

const providerRetryAfterSeconds = (error: unknown): number | null => {
  if (error === null || typeof error !== "object" || !("headers" in error)) {
    return null;
  }
  const headers = error.headers;
  if (!(headers instanceof Headers)) {
    return null;
  }
  const retryAfter = headers.get("retry-after");
  if (retryAfter === null || !/^\d+$/u.test(retryAfter)) {
    return null;
  }
  return Math.min(300, Math.max(1, Number(retryAfter)));
};

const modelFailureResponse = (error: unknown, context: Context): Response => {
  if (isStructuredGenerationTimeoutError(error)) {
    return jsonError(
      context,
      504,
      "model_request_timed_out",
      "The coaching service did not respond within the request budget.",
      [],
    );
  }

  const status = providerStatus(error);
  if (status === 429) {
    const retryAfterSeconds = providerRetryAfterSeconds(error);
    if (retryAfterSeconds !== null) {
      context.header("Retry-After", String(retryAfterSeconds));
    }
    return jsonError(
      context,
      429,
      "rate_limited",
      "The coaching service is busy. Try again shortly.",
      [],
    );
  }

  if (status === 401 || status === 403 || (status !== null && status >= 500)) {
    return jsonError(
      context,
      503,
      "model_request_failed",
      "The coaching service is temporarily unavailable.",
      [],
    );
  }

  return jsonError(
    context,
    502,
    "model_request_failed",
    "The coaching service is temporarily unavailable.",
    [],
  );
};

const probeBody = (status: "ok" | "ready" | "not_ready", build: string) => ({
  status,
  service: serviceName,
  schemaVersion,
  build,
});

const publicLivenessBody = () => ({
  status: "ok" as const,
  service: serviceName,
  schemaVersion,
});

const requestIdFor = (context: Context): string => {
  const receivedRequestId = context.req.header("x-request-id") ?? "";
  return safeRequestIdPattern.test(receivedRequestId)
    ? receivedRequestId
    : crypto.randomUUID();
};

const writeRequestLog = (
  logger: RequestLogger,
  event: RequestLogEvent,
): void => {
  try {
    logger(event);
  } catch {
    // Request telemetry must never alter an API response.
  }
};

export const createApp = (dependencies: AppDependencies): Hono => {
  if (dependencies.buildIdentifier.trim().length === 0) {
    throw new Error("buildIdentifier must not be empty.");
  }
  if (
    !Number.isSafeInteger(dependencies.modelRequestTimeoutMilliseconds) ||
    dependencies.modelRequestTimeoutMilliseconds <= 0
  ) {
    throw new Error(
      "modelRequestTimeoutMilliseconds must be a positive integer.",
    );
  }

  const app = new Hono();
  const expectedAuthorization = `Bearer ${dependencies.demoApiToken}`;

  app.use("*", async (context, next) => {
    const startedAt = performance.now();
    const requestId = requestIdFor(context);
    context.header("X-Request-Id", requestId);
    context.header("Cache-Control", "no-store");
    context.header("X-Content-Type-Options", "nosniff");
    context.header("Referrer-Policy", "no-referrer");
    context.header(
      "Permissions-Policy",
      "camera=(), microphone=(), geolocation=()",
    );
    context.header("Cross-Origin-Resource-Policy", "same-origin");
    context.header(
      "Content-Security-Policy",
      "default-src 'none'; frame-ancestors 'none'",
    );
    context.header("X-Frame-Options", "DENY");

    const authorization = context.req.header("authorization") ?? "";
    const isPublicLivenessProbe =
      context.req.method === "GET" && context.req.path === "/livez";
    if (
      !isPublicLivenessProbe &&
      !secureTokenEquals(authorization, expectedAuthorization)
    ) {
      context.header("WWW-Authenticate", 'Bearer realm="Voxa Cue API"');
      const response = jsonError(
        context,
        401,
        "unauthorized",
        "A valid Voxa Cue demo bearer token is required.",
        [],
      );
      writeRequestLog(dependencies.requestLogger, {
        requestId,
        method: context.req.method,
        path: context.req.path,
        status: response.status,
        latencyMilliseconds: performance.now() - startedAt,
      });
      return response;
    }

    await next();
    writeRequestLog(dependencies.requestLogger, {
      requestId,
      method: context.req.method,
      path: context.req.path,
      status: context.res.status,
      latencyMilliseconds: performance.now() - startedAt,
    });
  });

  app.get("/livez", (context) =>
    context.json(publicLivenessBody()),
  );

  app.get("/health", (context) =>
    context.json(probeBody("ok", dependencies.buildIdentifier)),
  );

  app.get("/readyz", async (context) => {
    let isReady = false;
    try {
      isReady = await dependencies.readinessCheck();
    } catch {
      isReady = false;
    }
    return context.json(
      probeBody(
        isReady ? "ready" : "not_ready",
        dependencies.buildIdentifier,
      ),
      isReady ? 200 : 503,
    );
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
      const insight = await runWithModelRequestDeadline(
        context.req.raw.signal,
        dependencies.modelRequestTimeoutMilliseconds,
        async (signal) =>
          generateInsight(dependencies, parsedRequest.value, signal),
      );
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
    } catch (error) {
      return modelFailureResponse(error, context);
    }
  });

  app.post("/v1/roadmaps", async (context) => {
    const parsedRequest = await parseBody(
      context,
      roadmapMaximumBytes,
      roadmapRequestSchema,
    );
    if (!parsedRequest.ok) {
      return parsedRequest.response;
    }

    try {
      const roadmap = await runWithModelRequestDeadline(
        context.req.raw.signal,
        dependencies.modelRequestTimeoutMilliseconds,
        async (signal) =>
          generateRoadmap(dependencies, parsedRequest.value, signal),
      );
      if (roadmap === null) {
        return jsonError(
          context,
          502,
          "invalid_model_response",
          "The coaching service returned an invalid roadmap.",
          [],
        );
      }
      return context.json(roadmap, 200);
    } catch (error) {
      return modelFailureResponse(error, context);
    }
  });

  app.post("/v1/coach-chat", async (context) => {
    const parsedRequest = await parseBody(
      context,
      coachChatMaximumBytes,
      coachChatRequestSchema,
    );
    if (!parsedRequest.ok) {
      return parsedRequest.response;
    }

    try {
      const reply = await runWithModelRequestDeadline(
        context.req.raw.signal,
        dependencies.modelRequestTimeoutMilliseconds,
        async (signal) =>
          generateCoachChat(dependencies, parsedRequest.value, signal),
      );
      if (reply === null) {
        return jsonError(
          context,
          502,
          "invalid_model_response",
          "The coaching service returned an invalid chat reply.",
          [],
        );
      }
      return context.json(reply, 200);
    } catch (error) {
      return modelFailureResponse(error, context);
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
