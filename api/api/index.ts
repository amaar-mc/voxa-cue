import { handle } from "hono/vercel";

import { createApp } from "../src/app";
import { createOpenAIStructuredOutputGenerator } from "../src/openai";
import { environmentSchema } from "../src/schemas";

const environment = environmentSchema.parse({
  OPENAI_API_KEY: process.env["OPENAI_API_KEY"],
  OPENAI_MODEL: process.env["OPENAI_MODEL"],
  VOXA_DEMO_API_TOKEN: process.env["VOXA_DEMO_API_TOKEN"],
});

const generateStructuredOutput = createOpenAIStructuredOutputGenerator({
  apiKey: environment.OPENAI_API_KEY,
  model: environment.OPENAI_MODEL,
  timeoutMilliseconds: 20_000,
  maximumRetries: 1,
  fetchImplementation: globalThis.fetch,
});

const app = createApp({
  demoApiToken: environment.VOXA_DEMO_API_TOKEN,
  generateStructuredOutput,
});

export const config = {
  maxDuration: 30,
};

export default handle(app);
