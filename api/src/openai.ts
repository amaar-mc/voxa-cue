import OpenAI from "openai";

export type StructuredGenerationRequest = {
  readonly schemaName: string;
  readonly instructions: string;
  readonly input: string;
  readonly jsonSchema: Record<string, unknown>;
  readonly maximumOutputTokens: number;
};

export type StructuredOutputGenerator = (
  request: StructuredGenerationRequest,
) => Promise<unknown>;

export type OpenAIConfiguration = {
  readonly apiKey: string;
  readonly model: string;
  readonly timeoutMilliseconds: number;
  readonly maximumRetries: number;
  readonly fetchImplementation: typeof fetch;
};

export const createOpenAIStructuredOutputGenerator = (
  configuration: OpenAIConfiguration,
): StructuredOutputGenerator => {
  const client = new OpenAI({
    apiKey: configuration.apiKey,
    timeout: configuration.timeoutMilliseconds,
    maxRetries: configuration.maximumRetries,
    fetch: configuration.fetchImplementation,
  });

  return async (request) => {
    const response = await client.responses.create({
      model: configuration.model,
      instructions: request.instructions,
      input: request.input,
      max_output_tokens: request.maximumOutputTokens,
      store: false,
      text: {
        format: {
          type: "json_schema",
          name: request.schemaName,
          strict: true,
          schema: request.jsonSchema,
        },
      },
    });

    if (response.output_text.length === 0) {
      throw new Error("OpenAI returned no structured output.");
    }

    return JSON.parse(response.output_text) as unknown;
  };
};
