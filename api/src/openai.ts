import OpenAI from "openai";

export type StructuredGenerationRequest = {
  readonly schemaName: string;
  readonly instructions: string;
  readonly input: string;
  readonly jsonSchema: Record<string, unknown>;
  readonly maximumOutputTokens: number;
  readonly signal: AbortSignal;
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

export type OpenAIReadinessConfiguration = {
  readonly apiKey: string;
  readonly model: string;
  readonly timeoutMilliseconds: number;
  readonly fetchImplementation: typeof fetch;
};

export type OpenAIReadinessCheck = () => Promise<boolean>;

export type StructuredGenerationTimeoutError = Error & {
  readonly code: "structured_generation_timed_out";
};

export const createStructuredGenerationTimeoutError =
  (): StructuredGenerationTimeoutError =>
    Object.assign(new Error("Structured generation timed out."), {
      name: "StructuredGenerationTimeoutError",
      code: "structured_generation_timed_out" as const,
    });

export const isStructuredGenerationTimeoutError = (
  error: unknown,
): error is StructuredGenerationTimeoutError =>
  error instanceof Error &&
  "code" in error &&
  error.code === "structured_generation_timed_out";

const providerAbortOrTimeoutNames = new Set([
  "AbortError",
  "APIConnectionTimeoutError",
  "APIUserAbortError",
]);

const isProviderAbortOrTimeout = (error: unknown): boolean =>
  error instanceof Error &&
  providerAbortOrTimeoutNames.has(error.name);

export const createOpenAIReadinessCheck = (
  configuration: OpenAIReadinessConfiguration,
): OpenAIReadinessCheck => {
  if (
    !Number.isSafeInteger(configuration.timeoutMilliseconds) ||
    configuration.timeoutMilliseconds <= 0
  ) {
    throw new Error("timeoutMilliseconds must be a positive integer.");
  }
  const modelURL = new URL(
    `/v1/models/${encodeURIComponent(configuration.model)}`,
    "https://api.openai.com",
  );

  return async () => {
    const controller = new AbortController();
    const timeout = setTimeout(
      () => controller.abort(),
      configuration.timeoutMilliseconds,
    );
    try {
      const response = await configuration.fetchImplementation(modelURL, {
        method: "GET",
        headers: {
          Accept: "application/json",
          Authorization: `Bearer ${configuration.apiKey}`,
        },
        signal: controller.signal,
      });
      return response.ok;
    } catch {
      return false;
    } finally {
      clearTimeout(timeout);
    }
  };
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
    try {
      const response = await client.responses.create(
        {
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
        },
        { signal: request.signal },
      );

      if (response.output_text.length === 0) {
        throw new Error("OpenAI returned no structured output.");
      }

      return JSON.parse(response.output_text) as unknown;
    } catch (error) {
      if (request.signal.aborted || isProviderAbortOrTimeout(error)) {
        throw createStructuredGenerationTimeoutError();
      }
      throw error;
    }
  };
};
