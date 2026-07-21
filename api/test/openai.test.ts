import { describe, expect, it, vi } from "vitest";

import {
  createOpenAIReadinessCheck,
  createOpenAIStructuredOutputGenerator,
} from "../src/openai";

const structuredResponse = (output: unknown): Response =>
  new Response(
    JSON.stringify({
      id: "resp_test",
      object: "response",
      created_at: 1_800_000_000,
      status: "completed",
      error: null,
      incomplete_details: null,
      instructions: null,
      max_output_tokens: 500,
      model: "test-model",
      output: [
        {
          id: "msg_test",
          type: "message",
          status: "completed",
          role: "assistant",
          content: [
            {
              type: "output_text",
              annotations: [],
              logprobs: [],
              text: JSON.stringify(output),
            },
          ],
        },
      ],
      parallel_tool_calls: true,
      previous_response_id: null,
      reasoning: { effort: null, summary: null },
      store: false,
      temperature: 1,
      text: { format: { type: "json_schema" } },
      tool_choice: "auto",
      tools: [],
      top_p: 1,
      truncation: "disabled",
      usage: {
        input_tokens: 10,
        input_tokens_details: { cached_tokens: 0 },
        output_tokens: 10,
        output_tokens_details: { reasoning_tokens: 0 },
        total_tokens: 20,
      },
    }),
    {
      status: 200,
      headers: {
        "content-type": "application/json",
        "x-request-id": "req_test",
      },
    },
  );

describe("OpenAI structured output adapter", () => {
  it("checks configured model access without sending presentation content", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async (_input, _init) =>
      new Response(JSON.stringify({ id: "explicit-test-model" }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );
    const readinessCheck = createOpenAIReadinessCheck({
      apiKey: "server-side-test-key",
      model: "explicit-test-model",
      timeoutMilliseconds: 2_000,
      fetchImplementation,
    });

    const isReady = await readinessCheck();

    expect(isReady).toBe(true);
    expect(fetchImplementation).toHaveBeenCalledOnce();
    const [request, requestInit] = fetchImplementation.mock.calls[0] ?? [];
    expect(String(request)).toBe(
      "https://api.openai.com/v1/models/explicit-test-model",
    );
    expect(requestInit).toMatchObject({
      method: "GET",
      headers: {
        Accept: "application/json",
        Authorization: "Bearer server-side-test-key",
      },
    });
    expect(requestInit?.body).toBeUndefined();
  });

  it("fails readiness closed when configured model access is rejected", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async (_input, _init) =>
      new Response("unauthorized", { status: 401 }),
    );
    const readinessCheck = createOpenAIReadinessCheck({
      apiKey: "revoked-test-key",
      model: "explicit-test-model",
      timeoutMilliseconds: 2_000,
      fetchImplementation,
    });

    await expect(readinessCheck()).resolves.toBe(false);
  });

  it("sends strict JSON Schema through the Responses API", async () => {
    const expectedOutput = { schemaVersion: 1, result: "ok" };
    const controller = new AbortController();
    const fetchImplementation = vi.fn<typeof fetch>(async (_input, _init) =>
      structuredResponse(expectedOutput),
    );
    const generate = createOpenAIStructuredOutputGenerator({
      apiKey: "server-side-test-key",
      model: "explicit-test-model",
      timeoutMilliseconds: 2_000,
      maximumRetries: 0,
      fetchImplementation,
    });
    const schema = {
      type: "object",
      additionalProperties: false,
      required: ["schemaVersion", "result"],
      properties: {
        schemaVersion: { const: 1 },
        result: { type: "string" },
      },
    };

    const output = await generate({
      schemaName: "test_schema",
      instructions: "Return the contract.",
      input: "Input evidence",
      jsonSchema: schema,
      maximumOutputTokens: 500,
      signal: controller.signal,
    });

    expect(output).toEqual(expectedOutput);
    expect(fetchImplementation).toHaveBeenCalledOnce();
    const requestInit = fetchImplementation.mock.calls[0]?.[1];
    expect(requestInit?.signal).toBeInstanceOf(AbortSignal);
    expect(requestInit?.signal?.aborted).toBe(false);
    const body = JSON.parse(String(requestInit?.body)) as Record<string, unknown>;
    expect(body).toMatchObject({
      model: "explicit-test-model",
      reasoning: { effort: "none" },
      store: false,
      text: {
        format: {
          type: "json_schema",
          name: "test_schema",
          strict: true,
          schema,
        },
      },
    });
    expect(String(requestInit?.body)).not.toContain("server-side-test-key");
  });

  it("fails closed when the provider returns malformed structured text", async () => {
    const response = structuredResponse({ schemaVersion: 1 });
    const providerBody = (await response.json()) as {
      output: Array<{ content: Array<{ text: string }> }>;
    };
    const firstMessage = providerBody.output[0];
    const firstContent = firstMessage?.content[0];
    if (firstContent === undefined) {
      throw new Error("Test fixture is missing output content.");
    }
    firstContent.text = "not-json";
    const fetchImplementation = vi.fn<typeof fetch>(async (_input, _init) =>
      new Response(JSON.stringify(providerBody), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );
    const generate = createOpenAIStructuredOutputGenerator({
      apiKey: "server-side-test-key",
      model: "explicit-test-model",
      timeoutMilliseconds: 2_000,
      maximumRetries: 0,
      fetchImplementation,
    });

    await expect(
      generate({
        schemaName: "test_schema",
        instructions: "Return the contract.",
        input: "Input evidence",
        jsonSchema: { type: "object" },
        maximumOutputTokens: 500,
        signal: new AbortController().signal,
      }),
    ).rejects.toThrow();
  });

  it("normalizes an aborted provider request to a typed timeout error", async () => {
    const controller = new AbortController();
    const providerRequest: { signal: AbortSignal | null } = { signal: null };
    const fetchImplementation = vi.fn<typeof fetch>(
      async (_input, init) =>
        new Promise<Response>((_resolve, reject) => {
          providerRequest.signal = init?.signal ?? null;
          providerRequest.signal?.addEventListener(
            "abort",
            () => {
              reject(new DOMException("Aborted", "AbortError"));
            },
            { once: true },
          );
        }),
    );
    const generate = createOpenAIStructuredOutputGenerator({
      apiKey: "server-side-test-key",
      model: "explicit-test-model",
      timeoutMilliseconds: 2_000,
      maximumRetries: 0,
      fetchImplementation,
    });
    const generation = generate({
      schemaName: "test_schema",
      instructions: "Return the contract.",
      input: "Input evidence",
      jsonSchema: { type: "object" },
      maximumOutputTokens: 500,
      signal: controller.signal,
    });
    const expectedRejection = expect(generation).rejects.toMatchObject({
      code: "structured_generation_timed_out",
    });
    await vi.waitFor(() => {
      expect(providerRequest.signal).not.toBeNull();
    });

    controller.abort();

    await expectedRejection;
    expect(providerRequest.signal?.aborted).toBe(true);
  });

  it("does not retry provider failures when retries are disabled", async () => {
    const fetchImplementation = vi.fn<typeof fetch>(async (_input, _init) =>
      new Response(JSON.stringify({ error: { message: "unavailable" } }), {
        status: 503,
        headers: { "content-type": "application/json" },
      }),
    );
    const generate = createOpenAIStructuredOutputGenerator({
      apiKey: "server-side-test-key",
      model: "explicit-test-model",
      timeoutMilliseconds: 2_000,
      maximumRetries: 0,
      fetchImplementation,
    });

    await expect(
      generate({
        schemaName: "test_schema",
        instructions: "Return the contract.",
        input: "Input evidence",
        jsonSchema: { type: "object" },
        maximumOutputTokens: 500,
        signal: new AbortController().signal,
      }),
    ).rejects.toThrow();
    expect(fetchImplementation).toHaveBeenCalledOnce();
  });
});
