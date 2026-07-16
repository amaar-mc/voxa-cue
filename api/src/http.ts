const utf8Decoder = new TextDecoder("utf-8", { fatal: true });

const forbiddenAudioKeys = new Set([
  "audio",
  "audiodata",
  "audiobase64",
  "audiourl",
  "recording",
  "pcm",
  "wav",
  "mp3",
  "m4a",
  "waveform",
]);

export type RequestBodyError = {
  readonly ok: false;
  readonly status: 400 | 413 | 415;
  readonly code:
    | "invalid_json"
    | "payload_too_large"
    | "unsupported_media_type"
    | "audio_not_accepted";
  readonly message: string;
};

export type RequestBodyResult =
  | { readonly ok: true; readonly value: unknown }
  | RequestBodyError;

const readBoundedBody = async (
  request: Request,
  maximumBytes: number,
): Promise<RequestBodyResult | Uint8Array> => {
  const contentLength = request.headers.get("content-length");
  if (contentLength !== null) {
    const parsedContentLength = Number(contentLength);
    if (
      Number.isFinite(parsedContentLength) &&
      parsedContentLength > maximumBytes
    ) {
      return {
        ok: false,
        status: 413,
        code: "payload_too_large",
        message: `Request body must not exceed ${maximumBytes} bytes.`,
      };
    }
  }

  if (request.body === null) {
    return new Uint8Array();
  }

  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;

  while (true) {
    const result = await reader.read();
    if (result.done) {
      break;
    }

    totalBytes += result.value.byteLength;
    if (totalBytes > maximumBytes) {
      await reader.cancel();
      return {
        ok: false,
        status: 413,
        code: "payload_too_large",
        message: `Request body must not exceed ${maximumBytes} bytes.`,
      };
    }
    chunks.push(result.value);
  }

  const body = new Uint8Array(totalBytes);
  let offset = 0;
  chunks.forEach((chunk) => {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  });
  return body;
};

const containsForbiddenAudioField = (value: unknown): boolean => {
  if (Array.isArray(value)) {
    return value.some((item) => containsForbiddenAudioField(item));
  }
  if (value === null || typeof value !== "object") {
    return false;
  }

  return Object.entries(value).some(([key, child]) => {
    const normalizedKey = key.toLocaleLowerCase("en-US").replaceAll(/[^a-z0-9]/g, "");
    return (
      forbiddenAudioKeys.has(normalizedKey) ||
      containsForbiddenAudioField(child)
    );
  });
};

export const readJsonBody = async (
  request: Request,
  maximumBytes: number,
): Promise<RequestBodyResult> => {
  const contentType = request.headers.get("content-type");
  if (
    contentType === null ||
    !/^application\/json(?:\s*;|$)/u.test(
      contentType.toLocaleLowerCase("en-US"),
    )
  ) {
    return {
      ok: false,
      status: 415,
      code: "unsupported_media_type",
      message: "Content-Type must be application/json.",
    };
  }

  const bodyResult = await readBoundedBody(request, maximumBytes);
  if (!(bodyResult instanceof Uint8Array)) {
    return bodyResult;
  }

  try {
    const decodedBody = utf8Decoder.decode(bodyResult);
    const parsedBody: unknown = JSON.parse(decodedBody);
    if (containsForbiddenAudioField(parsedBody)) {
      return {
        ok: false,
        status: 400,
        code: "audio_not_accepted",
        message: "Raw audio and audio file references are not accepted.",
      };
    }
    return { ok: true, value: parsedBody };
  } catch {
    return {
      ok: false,
      status: 400,
      code: "invalid_json",
      message: "Request body must contain valid UTF-8 JSON.",
    };
  }
};

export const secureTokenEquals = (
  receivedToken: string,
  expectedToken: string,
): boolean => {
  const receivedBytes = new TextEncoder().encode(receivedToken);
  const expectedBytes = new TextEncoder().encode(expectedToken);
  const comparisonLength = Math.max(receivedBytes.length, expectedBytes.length);
  let mismatch = receivedBytes.length ^ expectedBytes.length;

  for (let index = 0; index < comparisonLength; index += 1) {
    mismatch |= (receivedBytes[index] ?? 0) ^ (expectedBytes[index] ?? 0);
  }

  return mismatch === 0;
};
