import { afterEach, describe, expect, it, vi } from "vitest";

import { createApp } from "../src/app";
import type { RequestLogEvent, RequestLogger } from "../src/app";
import type {
  StructuredGenerationRequest,
  StructuredOutputGenerator,
} from "../src/openai";
import {
  demoToken,
  validDeckPlanRequest,
  validDeckPlanResponse,
  validInsightRequest,
  validInsightResponse,
} from "./fixtures";

const authorizationHeaders = {
  authorization: `Bearer ${demoToken}`,
};

const buildIdentifier = "test-build-001";
const modelRequestTimeoutMilliseconds = 25_000;
const readinessCheck = async (): Promise<boolean> => true;
const requestLogger: RequestLogger = (_event) => {};

const jsonRequest = (body: unknown): RequestInit => ({
  method: "POST",
  headers: {
    ...authorizationHeaders,
    "content-type": "application/json",
  },
  body: JSON.stringify(body),
});

const createMockGenerator = (
  result: unknown,
): ReturnType<typeof vi.fn<StructuredOutputGenerator>> =>
  vi.fn<StructuredOutputGenerator>(async (_request) => result);

const createTestApp = (generateStructuredOutput: StructuredOutputGenerator) =>
  createApp({
    buildIdentifier,
    demoApiToken: demoToken,
    generateStructuredOutput,
    modelRequestTimeoutMilliseconds,
    readinessCheck,
    requestLogger,
  });

afterEach(() => {
  vi.useRealTimers();
});

describe("Voxa Cue API", () => {
  it("exposes a minimal liveness probe with hardened response headers", async () => {
    const generate = createMockGenerator(validDeckPlanResponse);
    const app = createTestApp(generate);

    const response = await app.request("/livez", {
      headers: { "x-request-id": "unsafe-correlation-value" },
    });

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      status: "ok",
      service: "voxa-cue-api",
      schemaVersion: 1,
      build: buildIdentifier,
    });
    expect(response.headers.get("x-request-id")).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/u,
    );
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(response.headers.get("x-content-type-options")).toBe("nosniff");
    expect(response.headers.get("referrer-policy")).toBe("no-referrer");
    expect(response.headers.get("permissions-policy")).toBe(
      "camera=(), microphone=(), geolocation=()",
    );
    expect(response.headers.get("cross-origin-resource-policy")).toBe(
      "same-origin",
    );
    expect(generate).not.toHaveBeenCalled();
  });

  it("requires the demo bearer token on protected endpoints", async () => {
    const generate = createMockGenerator(validDeckPlanResponse);
    const app = createTestApp(generate);

    const healthResponse = await app.request("/health");
    const postResponse = await app.request("/v1/deck-plans", {
      method: "POST",
    });

    expect(healthResponse.status).toBe(401);
    expect(healthResponse.headers.get("www-authenticate")).toContain("Bearer");
    expect(postResponse.status).toBe(401);
    expect(generate).not.toHaveBeenCalled();
  });

  it("reports health without contacting OpenAI", async () => {
    const generate = createMockGenerator(validDeckPlanResponse);
    const app = createTestApp(generate);

    const response = await app.request("/health", {
      headers: authorizationHeaders,
    });

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      status: "ok",
      service: "voxa-cue-api",
      schemaVersion: 1,
      build: buildIdentifier,
    });
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(response.headers.get("x-request-id")).toBeTruthy();
    expect(generate).not.toHaveBeenCalled();
  });

  it("reports authenticated readiness without invoking model generation", async () => {
    const generate = createMockGenerator(validDeckPlanResponse);
    const unavailableApp = createApp({
      buildIdentifier,
      demoApiToken: demoToken,
      generateStructuredOutput: generate,
      modelRequestTimeoutMilliseconds,
      readinessCheck: async () => false,
      requestLogger,
    });
    const availableApp = createTestApp(generate);

    const unauthorizedResponse = await availableApp.request("/readyz");
    const unavailableResponse = await unavailableApp.request("/readyz", {
      headers: authorizationHeaders,
    });
    const availableResponse = await availableApp.request("/readyz", {
      headers: authorizationHeaders,
    });

    expect(unauthorizedResponse.status).toBe(401);
    expect(unavailableResponse.status).toBe(503);
    expect(await unavailableResponse.json()).toEqual({
      status: "not_ready",
      service: "voxa-cue-api",
      schemaVersion: 1,
      build: buildIdentifier,
    });
    expect(availableResponse.status).toBe(200);
    expect(await availableResponse.json()).toEqual({
      status: "ready",
      service: "voxa-cue-api",
      schemaVersion: 1,
      build: buildIdentifier,
    });
    expect(generate).not.toHaveBeenCalled();
  });

  it("correlates requests while logging only privacy-safe metadata", async () => {
    const safeRequestId = "123e4567-e89b-42d3-a456-426614174000";
    const privateTranscript = "private transcript marker";
    const requestLogs: RequestLogEvent[] = [];
    const generate = createMockGenerator(validInsightResponse);
    const app = createApp({
      buildIdentifier,
      demoApiToken: demoToken,
      generateStructuredOutput: generate,
      modelRequestTimeoutMilliseconds,
      readinessCheck,
      requestLogger: (event) => {
        requestLogs.push(event);
      },
    });

    const response = await app.request("/v1/insights?debug=private-query", {
      ...jsonRequest({
        ...validInsightRequest,
        transcript: privateTranscript,
      }),
      headers: {
        ...authorizationHeaders,
        "content-type": "application/json",
        "x-request-id": safeRequestId,
      },
    });

    expect(response.status).toBe(200);
    expect(response.headers.get("x-request-id")).toBe(safeRequestId);
    expect(requestLogs).toHaveLength(1);
    expect(requestLogs[0]).toEqual({
      requestId: safeRequestId,
      method: "POST",
      path: "/v1/insights",
      status: 200,
      latencyMilliseconds: expect.any(Number),
    });
    const serializedLog = JSON.stringify(requestLogs[0]);
    expect(serializedLog).not.toContain(demoToken);
    expect(serializedLog).not.toContain(privateTranscript);
    expect(serializedLog).not.toContain("private-query");
  });

  it("aborts model work at the request budget and returns a typed timeout", async () => {
    vi.useFakeTimers();
    const generate = vi.fn<StructuredOutputGenerator>(
      async (_request) => new Promise<unknown>(() => {}),
    );
    const app = createApp({
      buildIdentifier,
      demoApiToken: demoToken,
      generateStructuredOutput: generate,
      modelRequestTimeoutMilliseconds: 10,
      readinessCheck,
      requestLogger,
    });

    const responsePromise = app.request(
      "/v1/insights",
      jsonRequest(validInsightRequest),
    );
    await vi.waitFor(() => {
      expect(generate).toHaveBeenCalledOnce();
    });
    await vi.advanceTimersByTimeAsync(10);
    const response = await responsePromise;

    expect(response.status).toBe(504);
    expect(await response.json()).toMatchObject({
      error: { code: "model_request_timed_out" },
    });
    expect(generate).toHaveBeenCalledOnce();
    expect(generate.mock.calls[0]?.[0]?.signal.aborted).toBe(true);
  });

  it("creates a validated deck plan with strict structured output", async () => {
    const generate = createMockGenerator(validDeckPlanResponse);
    const app = createTestApp(generate);

    const response = await app.request(
      "/v1/deck-plans",
      jsonRequest(validDeckPlanRequest),
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual(validDeckPlanResponse);
    expect(generate).toHaveBeenCalledOnce();
    const generationRequest = generate.mock.calls[0]?.[0] as
      | StructuredGenerationRequest
      | undefined;
    expect(generationRequest?.schemaName).toBe("voxa_cue_deck_plan_v1");
    expect(generationRequest?.jsonSchema).toMatchObject({
      type: "object",
      additionalProperties: false,
    });
    expect(generationRequest?.input).not.toContain(demoToken);
  });

  it("rejects request fields that can carry raw audio before generation", async () => {
    const generate = createMockGenerator(validDeckPlanResponse);
    const app = createTestApp(generate);
    const requestWithAudio = {
      ...validDeckPlanRequest,
      metadata: {
        audioBase64: "UklGRg==",
      },
    };

    const response = await app.request(
      "/v1/deck-plans",
      jsonRequest(requestWithAudio),
    );

    expect(response.status).toBe(400);
    expect(await response.json()).toMatchObject({
      error: { code: "audio_not_accepted" },
    });
    expect(generate).not.toHaveBeenCalled();
  });

  it("enforces JSON content type and request schema", async () => {
    const generate = createMockGenerator(validDeckPlanResponse);
    const app = createTestApp(generate);

    const unsupportedResponse = await app.request("/v1/deck-plans", {
      method: "POST",
      headers: authorizationHeaders,
      body: JSON.stringify(validDeckPlanRequest),
    });
    const invalidResponse = await app.request(
      "/v1/deck-plans",
      jsonRequest({ ...validDeckPlanRequest, locale: "fr-FR" }),
    );

    expect(unsupportedResponse.status).toBe(415);
    expect(invalidResponse.status).toBe(422);
    expect(await invalidResponse.json()).toMatchObject({
      error: {
        code: "invalid_request",
        issues: [{ path: "locale" }],
      },
    });
    expect(generate).not.toHaveBeenCalled();
  });

  it("rejects oversized payloads before generation", async () => {
    const generate = createMockGenerator(validDeckPlanResponse);
    const app = createTestApp(generate);

    const response = await app.request("/v1/deck-plans", {
      method: "POST",
      headers: {
        ...authorizationHeaders,
        "content-type": "application/json",
        "content-length": String(512 * 1_024 + 1),
      },
      body: "{}",
    });

    expect(response.status).toBe(413);
    expect(await response.json()).toMatchObject({
      error: { code: "payload_too_large" },
    });
    expect(generate).not.toHaveBeenCalled();
  });

  it("rejects structurally or semantically invalid generated deck plans", async () => {
    const invalidShape = createMockGenerator({
      ...validDeckPlanResponse,
      unexpected: true,
    });
    const invalidTiming = createMockGenerator({
      ...validDeckPlanResponse,
      checkpoints: validDeckPlanResponse.checkpoints.map((checkpoint, index) =>
        index === 1
          ? { ...checkpoint, targetCumulativeSeconds: 170 }
          : checkpoint,
      ),
    });
    const invalidReference = createMockGenerator({
      ...validDeckPlanResponse,
      checkpoints: validDeckPlanResponse.checkpoints.map((checkpoint, index) =>
        index === 0 ? { ...checkpoint, id: "invented-checkpoint" } : checkpoint,
      ),
    });

    for (const generate of [invalidShape, invalidTiming, invalidReference]) {
      const app = createTestApp(generate);
      const response = await app.request(
        "/v1/deck-plans",
        jsonRequest(validDeckPlanRequest),
      );
      expect(response.status).toBe(502);
      expect(await response.json()).toMatchObject({
        error: { code: "invalid_model_response" },
      });
    }
  });

  it("creates schema-valid insights", async () => {
    const generate = createMockGenerator(validInsightResponse);
    const app = createTestApp(generate);

    const response = await app.request(
      "/v1/insights",
      jsonRequest(validInsightRequest),
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual(validInsightResponse);
    expect(generate).toHaveBeenCalledOnce();
    expect(generate.mock.calls[0]?.[0]?.schemaName).toBe(
      "voxa_cue_insight_v1",
    );
    expect(generate.mock.calls[0]?.[0]?.input).not.toContain(
      validInsightRequest.sessionId,
    );
  });

  it("accepts explicit null metrics and pending cue delivery", async () => {
    const generate = createMockGenerator(validInsightResponse);
    const app = createTestApp(generate);
    const request = {
      ...validInsightRequest,
      metrics: {
        ...validInsightRequest.metrics,
        paceStandardDeviationWpm: null,
        pauseCount: null,
        averagePauseSeconds: null,
        longestPauseSeconds: null,
        pitchRangeSemitones: null,
        energyRangeDb: null,
      },
      checkpoints: validInsightRequest.checkpoints.map((checkpoint) => ({
        ...checkpoint,
        observedCumulativeSeconds: null,
        confidence: null,
      })),
      cueEvents: validInsightRequest.cueEvents.map((event) => ({
        ...event,
        sequence: null,
        deliveryStatus: "pending",
      })),
    };

    const response = await app.request(
      "/v1/insights",
      jsonRequest(request),
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual(validInsightResponse);
    expect(generate).toHaveBeenCalledOnce();
  });

  it("requires nullable insight fields to be present", async () => {
    const generate = createMockGenerator(validInsightResponse);
    const app = createTestApp(generate);
    const { pitchRangeSemitones: _pitchRangeSemitones, ...metrics } =
      validInsightRequest.metrics;
    const request = {
      ...validInsightRequest,
      metrics,
    };

    const response = await app.request(
      "/v1/insights",
      jsonRequest(request),
    );

    expect(response.status).toBe(422);
    expect(await response.json()).toMatchObject({
      error: {
        code: "invalid_request",
        issues: [{ path: "metrics.pitchRangeSemitones" }],
      },
    });
    expect(generate).not.toHaveBeenCalled();
  });

  it("sanitizes model failures without leaking secrets or provider errors", async () => {
    const providerSecret = "provider-secret-details";
    const generate = vi.fn<StructuredOutputGenerator>(async (_request) => {
      throw new Error(`${providerSecret} ${demoToken}`);
    });
    const app = createTestApp(generate);

    const response = await app.request(
      "/v1/insights",
      jsonRequest(validInsightRequest),
    );
    const responseText = await response.text();

    expect(response.status).toBe(502);
    expect(responseText).toContain("model_request_failed");
    expect(responseText).not.toContain(providerSecret);
    expect(responseText).not.toContain(demoToken);
  });

  it("returns a sanitized error when insight output violates the contract", async () => {
    const generate = createMockGenerator({
      ...validInsightResponse,
      drills: [],
    });
    const app = createTestApp(generate);

    const response = await app.request(
      "/v1/insights",
      jsonRequest(validInsightRequest),
    );

    expect(response.status).toBe(502);
    expect(await response.json()).toMatchObject({
      error: { code: "invalid_model_response" },
    });
  });
});
