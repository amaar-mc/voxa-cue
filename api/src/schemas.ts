import { z } from "zod";

const trimmedString = (minimumLength: number, maximumLength: number) =>
  z.string().trim().min(minimumLength).max(maximumLength);

const boundedNumber = (minimum: number, maximum: number) =>
  z.number().finite().min(minimum).max(maximum);

const deckSlideSchema = z
  .object({
    slideIndex: z.number().int().min(0).max(99),
    title: z.string().trim().max(200),
    visibleText: z.string().trim().max(10_000),
    speakerNotes: z.string().trim().max(10_000),
  })
  .strict()
  .refine(
    (slide) =>
      slide.title.length > 0 ||
      slide.visibleText.length > 0 ||
      slide.speakerNotes.length > 0,
    { message: "Each slide must include a title, visible text, or speaker notes." },
  );

export const deckPlanRequestSchema = z
  .object({
    schemaVersion: z.literal(1),
    locale: z.literal("en-US"),
    title: trimmedString(1, 200),
    targetDurationSeconds: z.number().int().min(30).max(7_200),
    slides: z.array(deckSlideSchema).min(1).max(100),
  })
  .strict()
  .superRefine((request, context) => {
    const indexes = new Set<number>();
    let previousIndex = -1;

    request.slides.forEach((slide, index) => {
      if (indexes.has(slide.slideIndex)) {
        context.addIssue({
          code: "custom",
          message: `Duplicate slideIndex ${slide.slideIndex}.`,
          path: ["slides", index, "slideIndex"],
        });
      }
      if (slide.slideIndex <= previousIndex) {
        context.addIssue({
          code: "custom",
          message: "Slides must be ordered by increasing slideIndex.",
          path: ["slides", index, "slideIndex"],
        });
      }
      indexes.add(slide.slideIndex);
      previousIndex = slide.slideIndex;
    });
  });

export const deckCheckpointSchema = z
  .object({
    id: trimmedString(1, 80),
    slideIndex: z.number().int().min(0),
    label: trimmedString(1, 120),
    targetCumulativeSeconds: z.number().int().min(1),
    semanticSummary: trimmedString(1, 400),
    anchorTerms: z.array(trimmedString(1, 80)).min(2).max(12),
  })
  .strict();

export const deckPlanResponseSchema = z
  .object({
    schemaVersion: z.literal(1),
    title: trimmedString(1, 200),
    checkpoints: z.array(deckCheckpointSchema).min(1).max(100),
  })
  .strict();

const targetSchema = z
  .object({
    durationSeconds: z.number().int().min(30).max(7_200),
    paceMinimumWpm: z.number().int().min(60).max(250),
    paceMaximumWpm: z.number().int().min(61).max(300),
  })
  .strict()
  .refine((target) => target.paceMaximumWpm > target.paceMinimumWpm, {
    message: "paceMaximumWpm must exceed paceMinimumWpm.",
    path: ["paceMaximumWpm"],
  });

const metricsSchema = z
  .object({
    durationSeconds: boundedNumber(1, 7_200),
    speakingSeconds: boundedNumber(0, 7_200),
    averageWpm: boundedNumber(0, 400),
    timeInPaceRangeRatio: boundedNumber(0, 1),
    fillerCount: z.number().int().min(0).max(10_000),
    fillersPerMinute: boundedNumber(0, 100),
    talkRatio: boundedNumber(0, 1),
    pitchRangeSemitones: boundedNumber(0, 96).nullable(),
    energyRangeDb: boundedNumber(0, 120).nullable(),
    completedOnTime: z.boolean(),
  })
  .strict()
  .refine((metrics) => metrics.speakingSeconds <= metrics.durationSeconds, {
    message: "speakingSeconds cannot exceed durationSeconds.",
    path: ["speakingSeconds"],
  });

const checkpointResultSchema = z
  .object({
    id: trimmedString(1, 80),
    label: trimmedString(1, 120),
    targetCumulativeSeconds: z.number().int().min(1).max(7_200),
    observedCumulativeSeconds: boundedNumber(0, 7_200).nullable(),
    confidence: boundedNumber(0, 1).nullable(),
    status: z.enum(["reached", "missed", "skipped"]),
  })
  .strict();

export const cueKindSchema = z.enum([
  "tooFast",
  "tooSlow",
  "fillerBurst",
  "time75",
  "time90",
  "time100",
  "deckBehind",
]);

const cueEventSchema = z
  .object({
    sequence: z.number().int().min(0).max(65_535).nullable(),
    kind: cueKindSchema,
    elapsedSeconds: boundedNumber(0, 7_200),
    reason: trimmedString(1, 240),
    deliveryStatus: z.enum([
      "pending",
      "accepted",
      "completed",
      "failed",
      "notConnected",
      "suppressed",
    ]),
  })
  .strict();

export const insightRequestSchema = z
  .object({
    schemaVersion: z.literal(1),
    sessionId: trimmedString(1, 80),
    locale: z.literal("en-US"),
    transcript: trimmedString(1, 100_000),
    target: targetSchema,
    metrics: metricsSchema,
    checkpoints: z.array(checkpointResultSchema).max(100),
    cueEvents: z.array(cueEventSchema).max(500),
  })
  .strict();

const evidenceItemSchema = z
  .object({
    title: trimmedString(1, 100),
    evidence: trimmedString(1, 300),
  })
  .strict();

const prioritySchema = z
  .object({
    title: trimmedString(1, 100),
    evidence: trimmedString(1, 300),
    nextAction: trimmedString(1, 300),
  })
  .strict();

const drillSchema = z
  .object({
    title: trimmedString(1, 100),
    instructions: trimmedString(1, 400),
    durationMinutes: z.number().int().min(1).max(30),
  })
  .strict();

export const insightResponseSchema = z
  .object({
    schemaVersion: z.literal(1),
    overallSummary: trimmedString(1, 600),
    strengths: z.array(evidenceItemSchema).min(1).max(3),
    priorities: z.array(prioritySchema).min(1).max(3),
    drills: z.array(drillSchema).min(1).max(3),
    confidenceNote: trimmedString(1, 300),
  })
  .strict();

export const environmentSchema = z
  .object({
    OPENAI_API_KEY: trimmedString(1, 500),
    OPENAI_MODEL: trimmedString(1, 100),
    VOXA_BUILD_ID: trimmedString(1, 100),
    VOXA_DEMO_API_TOKEN: trimmedString(32, 500),
  })
  .strict();

export type DeckPlanRequest = z.infer<typeof deckPlanRequestSchema>;
export type DeckPlanResponse = z.infer<typeof deckPlanResponseSchema>;
export type InsightRequest = z.infer<typeof insightRequestSchema>;
export type InsightResponse = z.infer<typeof insightResponseSchema>;
export type RuntimeEnvironment = z.infer<typeof environmentSchema>;

export const deckPlanJsonSchema = {
  type: "object",
  additionalProperties: false,
  required: ["schemaVersion", "title", "checkpoints"],
  properties: {
    schemaVersion: { const: 1 },
    title: { type: "string", minLength: 1, maxLength: 200 },
    checkpoints: {
      type: "array",
      minItems: 1,
      maxItems: 100,
      items: {
        type: "object",
        additionalProperties: false,
        required: [
          "id",
          "slideIndex",
          "label",
          "targetCumulativeSeconds",
          "semanticSummary",
          "anchorTerms",
        ],
        properties: {
          id: { type: "string", minLength: 1, maxLength: 80 },
          slideIndex: { type: "integer", minimum: 0 },
          label: { type: "string", minLength: 1, maxLength: 120 },
          targetCumulativeSeconds: { type: "integer", minimum: 1 },
          semanticSummary: { type: "string", minLength: 1, maxLength: 400 },
          anchorTerms: {
            type: "array",
            minItems: 2,
            maxItems: 12,
            items: { type: "string", minLength: 1, maxLength: 80 },
          },
        },
      },
    },
  },
} as const;

export const insightJsonSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "schemaVersion",
    "overallSummary",
    "strengths",
    "priorities",
    "drills",
    "confidenceNote",
  ],
  properties: {
    schemaVersion: { const: 1 },
    overallSummary: { type: "string", minLength: 1, maxLength: 600 },
    strengths: {
      type: "array",
      minItems: 1,
      maxItems: 3,
      items: { $ref: "#/$defs/evidenceItem" },
    },
    priorities: {
      type: "array",
      minItems: 1,
      maxItems: 3,
      items: { $ref: "#/$defs/priority" },
    },
    drills: {
      type: "array",
      minItems: 1,
      maxItems: 3,
      items: { $ref: "#/$defs/drill" },
    },
    confidenceNote: { type: "string", minLength: 1, maxLength: 300 },
  },
  $defs: {
    evidenceItem: {
      type: "object",
      additionalProperties: false,
      required: ["title", "evidence"],
      properties: {
        title: { type: "string", minLength: 1, maxLength: 100 },
        evidence: { type: "string", minLength: 1, maxLength: 300 },
      },
    },
    priority: {
      type: "object",
      additionalProperties: false,
      required: ["title", "evidence", "nextAction"],
      properties: {
        title: { type: "string", minLength: 1, maxLength: 100 },
        evidence: { type: "string", minLength: 1, maxLength: 300 },
        nextAction: { type: "string", minLength: 1, maxLength: 300 },
      },
    },
    drill: {
      type: "object",
      additionalProperties: false,
      required: ["title", "instructions", "durationMinutes"],
      properties: {
        title: { type: "string", minLength: 1, maxLength: 100 },
        instructions: { type: "string", minLength: 1, maxLength: 400 },
        durationMinutes: { type: "integer", minimum: 1, maximum: 30 },
      },
    },
  },
} as const;
