import { z } from "zod";

const trimmedString = (minimumLength: number, maximumLength: number) =>
  z.string().trim().min(minimumLength).max(maximumLength);

const boundedNumber = (minimum: number, maximum: number) =>
  z.number().finite().min(minimum).max(maximum);

const normalizedEnglishPhrase = (phrase: string): string =>
  phrase.toLocaleLowerCase("en-US").replaceAll(/\s+/gu, " ").trim();

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
    paceStandardDeviationWpm: boundedNumber(0, 200).nullable().optional(),
    pauseCount: z.number().int().min(0).max(10_000).nullable().optional(),
    averagePauseSeconds: boundedNumber(0, 600).nullable().optional(),
    longestPauseSeconds: boundedNumber(0, 7_200).nullable().optional(),
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
  "time50",
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

const fillerBreakdownItemSchema = z
  .object({
    phrase: trimmedString(1, 80),
    count: z.number().int().min(1).max(10_000),
  })
  .strict();

const fillerBreakdownSchema = z
  .array(fillerBreakdownItemSchema)
  .max(20)
  .superRefine((items, context) => {
    const phrases = new Set<string>();
    items.forEach((item, index) => {
      const normalizedPhrase = normalizedEnglishPhrase(item.phrase);
      if (phrases.has(normalizedPhrase)) {
        context.addIssue({
          code: "custom",
          message: "Filler phrases must be unique after normalization.",
          path: [index, "phrase"],
        });
      }
      phrases.add(normalizedPhrase);
    });
  });

export const roadmapSessionSchema = z
  .object({
    transcript: trimmedString(1, 100_000),
    target: targetSchema,
    metrics: metricsSchema,
    fillerBreakdown: fillerBreakdownSchema,
  })
  .strict()
  .superRefine((session, context) => {
    const breakdownTotal = session.fillerBreakdown.reduce(
      (total, item) => total + item.count,
      0,
    );
    if (breakdownTotal !== session.metrics.fillerCount) {
      context.addIssue({
        code: "custom",
        message:
          "Filler breakdown counts must equal the deterministic session fillerCount.",
        path: ["fillerBreakdown"],
      });
    }
  });

export const roadmapHistorySchema = z
  .object({
    sessionCount: z.number().int().min(1).max(1_000),
    totalPresentationSeconds: boundedNumber(1, 7_200_000),
    averageWpm: boundedNumber(0, 400),
    timeInPaceRangeRatio: boundedNumber(0, 1),
    fillersPerMinute: boundedNumber(0, 100),
    talkRatio: boundedNumber(0, 1),
    onTargetSessionRatio: boundedNumber(0, 1),
    averageAbsoluteTimingDeviationSeconds: boundedNumber(0, 7_200),
    averagePaceStandardDeviationWpm: boundedNumber(0, 200).nullable(),
    averagePitchRangeSemitones: boundedNumber(0, 96).nullable(),
    averageEnergyRangeDb: boundedNumber(0, 120).nullable(),
    measuredIntonationSessionCount: z.number().int().min(0).max(1_000),
    pausesPerPresentationMinute: boundedNumber(0, 600).nullable(),
    averagePauseSeconds: boundedNumber(0, 600).nullable(),
    longestPauseSeconds: boundedNumber(0, 7_200).nullable(),
    measuredPauseSessionCount: z.number().int().min(0).max(1_000),
  })
  .strict()
  .superRefine((history, context) => {
    if (history.measuredIntonationSessionCount > history.sessionCount) {
      context.addIssue({
        code: "custom",
        message: "measuredIntonationSessionCount cannot exceed sessionCount.",
        path: ["measuredIntonationSessionCount"],
      });
    }
    if (history.measuredPauseSessionCount > history.sessionCount) {
      context.addIssue({
        code: "custom",
        message: "measuredPauseSessionCount cannot exceed sessionCount.",
        path: ["measuredPauseSessionCount"],
      });
    }
  });

export const roadmapRequestSchema = z
  .object({
    schemaVersion: z.literal(1),
    locale: z.literal("en-US"),
    session: roadmapSessionSchema,
    history: roadmapHistorySchema,
  })
  .strict();

const focusFillerSchema = z
  .object({
    phrase: trimmedString(1, 80),
    count: z.number().int().min(1).max(10_000),
    guidance: trimmedString(1, 300),
  })
  .strict();

const roadmapStepSchema = z
  .object({
    phase: z.enum(["now", "next", "then"]),
    title: trimmedString(1, 100),
    evidence: trimmedString(1, 300),
    action: trimmedString(1, 400),
    measurableTarget: trimmedString(1, 240),
  })
  .strict();

const nextSessionGoalSchema = z
  .object({
    title: trimmedString(1, 100),
    measurement: trimmedString(1, 120),
    target: trimmedString(1, 180),
  })
  .strict();

export const roadmapResponseSchema = z
  .object({
    schemaVersion: z.literal(1),
    headline: trimmedString(1, 100),
    summary: trimmedString(1, 500),
    focusFillers: z.array(focusFillerSchema).max(3),
    steps: z.array(roadmapStepSchema).length(3),
    nextSessionGoal: nextSessionGoalSchema,
    confidenceNote: trimmedString(1, 300),
  })
  .strict()
  .superRefine((roadmap, context) => {
    const expectedPhases = ["now", "next", "then"] as const;
    roadmap.steps.forEach((step, index) => {
      if (step.phase !== expectedPhases[index]) {
        context.addIssue({
          code: "custom",
          message: `Roadmap step ${index + 1} must use phase ${expectedPhases[index]}.`,
          path: ["steps", index, "phase"],
        });
      }
    });
  });

const coachChatMessageSchema = z
  .object({
    role: z.enum(["user", "assistant"]),
    content: trimmedString(1, 1_000),
  })
  .strict();

export const coachChatRequestSchema = z
  .object({
    schemaVersion: z.literal(1),
    locale: z.literal("en-US"),
    session: roadmapSessionSchema,
    roadmap: roadmapResponseSchema,
    messages: z.array(coachChatMessageSchema).min(1).max(10),
  })
  .strict()
  .superRefine((request, context) => {
    if (request.messages.at(-1)?.role !== "user") {
      context.addIssue({
        code: "custom",
        message: "The final chat message must have role user.",
        path: ["messages", request.messages.length - 1, "role"],
      });
    }
    const messageCharacters = request.messages.reduce(
      (total, message) => total + message.content.length,
      0,
    );
    if (messageCharacters > 10_000) {
      context.addIssue({
        code: "custom",
        message: "Chat history must not exceed 10000 characters.",
        path: ["messages"],
      });
    }
    const suppliedFillers = new Map(
      request.session.fillerBreakdown.map((item) => [
        normalizedEnglishPhrase(item.phrase),
        item.count,
      ]),
    );
    const roadmapFillers = new Set<string>();
    request.roadmap.focusFillers.forEach((item, index) => {
      const phrase = normalizedEnglishPhrase(item.phrase);
      if (
        roadmapFillers.has(phrase) ||
        suppliedFillers.get(phrase) !== item.count
      ) {
        context.addIssue({
          code: "custom",
          message:
            "Roadmap filler evidence must exactly match the selected session filler breakdown.",
          path: ["roadmap", "focusFillers", index],
        });
      }
      roadmapFillers.add(phrase);
    });
  });

export const coachChatResponseSchema = z
  .object({
    schemaVersion: z.literal(1),
    reply: trimmedString(1, 1_200),
    suggestedPrompts: z.array(trimmedString(1, 120)).max(3),
  })
  .strict();

export const environmentSchema = z
  .object({
    OPENAI_API_KEY: trimmedString(1, 500),
    OPENAI_MODEL: z.literal("gpt-5.6-luna"),
    VOXA_BUILD_ID: trimmedString(1, 100),
    VOXA_DEMO_API_TOKEN: trimmedString(32, 500),
  })
  .strict();

export type InsightRequest = z.infer<typeof insightRequestSchema>;
export type InsightResponse = z.infer<typeof insightResponseSchema>;
export type RoadmapSession = z.infer<typeof roadmapSessionSchema>;
export type RoadmapHistory = z.infer<typeof roadmapHistorySchema>;
export type RoadmapRequest = z.infer<typeof roadmapRequestSchema>;
export type RoadmapResponse = z.infer<typeof roadmapResponseSchema>;
export type CoachChatRequest = z.infer<typeof coachChatRequestSchema>;
export type CoachChatResponse = z.infer<typeof coachChatResponseSchema>;
export type RuntimeEnvironment = z.infer<typeof environmentSchema>;

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
    schemaVersion: { type: "number", const: 1 },
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

export const roadmapJsonSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "schemaVersion",
    "headline",
    "summary",
    "focusFillers",
    "steps",
    "nextSessionGoal",
    "confidenceNote",
  ],
  properties: {
    schemaVersion: { type: "number", const: 1 },
    headline: { type: "string", minLength: 1, maxLength: 100 },
    summary: { type: "string", minLength: 1, maxLength: 500 },
    focusFillers: {
      type: "array",
      minItems: 0,
      maxItems: 3,
      items: { $ref: "#/$defs/focusFiller" },
    },
    steps: {
      type: "array",
      minItems: 3,
      maxItems: 3,
      items: { $ref: "#/$defs/roadmapStep" },
    },
    nextSessionGoal: { $ref: "#/$defs/nextSessionGoal" },
    confidenceNote: { type: "string", minLength: 1, maxLength: 300 },
  },
  $defs: {
    focusFiller: {
      type: "object",
      additionalProperties: false,
      required: ["phrase", "count", "guidance"],
      properties: {
        phrase: { type: "string", minLength: 1, maxLength: 80 },
        count: { type: "integer", minimum: 1, maximum: 10_000 },
        guidance: { type: "string", minLength: 1, maxLength: 300 },
      },
    },
    roadmapStep: {
      type: "object",
      additionalProperties: false,
      required: [
        "phase",
        "title",
        "evidence",
        "action",
        "measurableTarget",
      ],
      properties: {
        phase: { type: "string", enum: ["now", "next", "then"] },
        title: { type: "string", minLength: 1, maxLength: 100 },
        evidence: { type: "string", minLength: 1, maxLength: 300 },
        action: { type: "string", minLength: 1, maxLength: 400 },
        measurableTarget: {
          type: "string",
          minLength: 1,
          maxLength: 240,
        },
      },
    },
    nextSessionGoal: {
      type: "object",
      additionalProperties: false,
      required: ["title", "measurement", "target"],
      properties: {
        title: { type: "string", minLength: 1, maxLength: 100 },
        measurement: { type: "string", minLength: 1, maxLength: 120 },
        target: { type: "string", minLength: 1, maxLength: 180 },
      },
    },
  },
} as const;

export const coachChatJsonSchema = {
  type: "object",
  additionalProperties: false,
  required: ["schemaVersion", "reply", "suggestedPrompts"],
  properties: {
    schemaVersion: { type: "number", const: 1 },
    reply: { type: "string", minLength: 1, maxLength: 1_200 },
    suggestedPrompts: {
      type: "array",
      minItems: 0,
      maxItems: 3,
      items: { type: "string", minLength: 1, maxLength: 120 },
    },
  },
} as const;
