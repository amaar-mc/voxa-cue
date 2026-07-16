import { describe, expect, it, vi } from "vitest";

import { createApp } from "../src/app";
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

describe("Voxa Cue API", () => {
  it("requires the demo bearer token on every endpoint", async () => {
    const generate = createMockGenerator(validDeckPlanResponse);
    const app = createApp({
      demoApiToken: demoToken,
      generateStructuredOutput: generate,
    });

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
    const app = createApp({
      demoApiToken: demoToken,
      generateStructuredOutput: generate,
    });

    const response = await app.request("/health", {
      headers: authorizationHeaders,
    });

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      status: "ok",
      service: "voxa-cue-api",
      schemaVersion: 1,
    });
    expect(response.headers.get("cache-control")).toBe("no-store");
    expect(response.headers.get("x-request-id")).toBeTruthy();
    expect(generate).not.toHaveBeenCalled();
  });

  it("creates a validated deck plan with strict structured output", async () => {
    const generate = createMockGenerator(validDeckPlanResponse);
    const app = createApp({
      demoApiToken: demoToken,
      generateStructuredOutput: generate,
    });

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
    const app = createApp({
      demoApiToken: demoToken,
      generateStructuredOutput: generate,
    });
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
    const app = createApp({
      demoApiToken: demoToken,
      generateStructuredOutput: generate,
    });

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
    const app = createApp({
      demoApiToken: demoToken,
      generateStructuredOutput: generate,
    });

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
      const app = createApp({
        demoApiToken: demoToken,
        generateStructuredOutput: generate,
      });
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
    const app = createApp({
      demoApiToken: demoToken,
      generateStructuredOutput: generate,
    });

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
  });

  it("accepts explicit null metrics and pending cue delivery", async () => {
    const generate = createMockGenerator(validInsightResponse);
    const app = createApp({
      demoApiToken: demoToken,
      generateStructuredOutput: generate,
    });
    const request = {
      ...validInsightRequest,
      metrics: {
        ...validInsightRequest.metrics,
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
    const app = createApp({
      demoApiToken: demoToken,
      generateStructuredOutput: generate,
    });
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
    const app = createApp({
      demoApiToken: demoToken,
      generateStructuredOutput: generate,
    });

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
    const app = createApp({
      demoApiToken: demoToken,
      generateStructuredOutput: generate,
    });

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
