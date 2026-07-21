import { describe, expect, it } from "vitest";

import { readJsonBody } from "../src/http";

const maximumBytes = 256 * 1_024;

const jsonRequest = (body: string): Request =>
  new Request("https://api.example.test/v1/insights", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body,
  });

describe("request body privacy guard", () => {
  it.each([
    "data:audio/wav;base64,UklGRgAAAAA=",
    "https://files.example.test/private-recording.m4a?download=1",
    "UklGRgAAAAAAAAAAAAAAAAAAAAAA",
    "SUQzBAAAAAAAAAAAAAAAAAAAAAAA",
    "T2dnUwAAAAAAAAAAAAAAAAAAAAAA",
    "ZkxhQwAAAAAAAAAAAAAAAAAAAAAA",
  ])("rejects audio content hidden inside an allowed text field", async (transcript) => {
    const result = await readJsonBody(
      jsonRequest(JSON.stringify({ transcript })),
      maximumBytes,
    );

    expect(result).toMatchObject({
      ok: false,
      status: 400,
      code: "audio_not_accepted",
    });
  });

  it("rejects a large encoded binary block", async () => {
    const encodedBinary = "QUJD".repeat(300);
    const result = await readJsonBody(
      jsonRequest(JSON.stringify({ transcript: encodedBinary })),
      maximumBytes,
    );

    expect(result).toMatchObject({
      ok: false,
      status: 400,
      code: "audio_not_accepted",
    });
  });

  it("does not reject ordinary speech about audio formats", async () => {
    const result = await readJsonBody(
      jsonRequest(JSON.stringify({
        transcript: "I exported an MP3 once, but this sentence is only transcript text.",
      })),
      maximumBytes,
    );

    expect(result).toEqual({
      ok: true,
      value: {
        transcript: "I exported an MP3 once, but this sentence is only transcript text.",
      },
    });
  });

  it("scans deeply nested JSON without recursion failure", async () => {
    const depth = 5_000;
    const body = `${'{"safe":'.repeat(depth)}"speech"${"}".repeat(depth)}`;
    const result = await readJsonBody(jsonRequest(body), maximumBytes);

    expect(result.ok).toBe(true);
  });
});
