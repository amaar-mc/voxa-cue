import { describe, expect, it, vi } from "vitest";

import { createOpenAIStructuredOutputGenerator } from "../src/openai";

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
  it("sends strict JSON Schema through the Responses API", async () => {
    const expectedOutput = { schemaVersion: 1, result: "ok" };
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
    });

    expect(output).toEqual(expectedOutput);
    expect(fetchImplementation).toHaveBeenCalledOnce();
    const requestInit = fetchImplementation.mock.calls[0]?.[1];
    const body = JSON.parse(String(requestInit?.body)) as Record<string, unknown>;
    expect(body).toMatchObject({
      model: "explicit-test-model",
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
      }),
    ).rejects.toThrow();
  });
});
