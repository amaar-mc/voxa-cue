import { handle } from "hono/vercel";

import { createApp } from "../src/app";
import {
  createOpenAIReadinessCheck,
  createOpenAIStructuredOutputGenerator,
} from "../src/openai";
import { environmentSchema } from "../src/schemas";

const environment = environmentSchema.parse({
  OPENAI_API_KEY: process.env["OPENAI_API_KEY"],
  OPENAI_MODEL: process.env["OPENAI_MODEL"],
  VOXA_BUILD_ID: process.env["VOXA_BUILD_ID"],
  VOXA_DEMO_API_TOKEN: process.env["VOXA_DEMO_API_TOKEN"],
});

const generateStructuredOutput = createOpenAIStructuredOutputGenerator({
  apiKey: environment.OPENAI_API_KEY,
  model: environment.OPENAI_MODEL,
  timeoutMilliseconds: 22_000,
  maximumRetries: 0,
  fetchImplementation: globalThis.fetch,
});

const readinessCheck = createOpenAIReadinessCheck({
  apiKey: environment.OPENAI_API_KEY,
  model: environment.OPENAI_MODEL,
  timeoutMilliseconds: 3_000,
  fetchImplementation: globalThis.fetch,
});

const app = createApp({
  buildIdentifier: environment.VOXA_BUILD_ID,
  demoApiToken: environment.VOXA_DEMO_API_TOKEN,
  generateStructuredOutput,
  modelRequestTimeoutMilliseconds: 25_000,
  readinessCheck,
  requestLogger: (event) => {
    console.info(JSON.stringify(event));
  },
});

export const config = {
  maxDuration: 30,
};

export default handle(app);
