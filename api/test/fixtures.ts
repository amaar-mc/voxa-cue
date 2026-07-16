import type {
  DeckPlanRequest,
  DeckPlanResponse,
  InsightRequest,
  InsightResponse,
} from "../src/schemas";

export const demoToken = "test-demo-token-with-at-least-32-chars";

export const validDeckPlanRequest: DeckPlanRequest = {
  schemaVersion: 1,
  locale: "en-US",
  title: "Voxa Cue Product Pitch",
  targetDurationSeconds: 180,
  slides: [
    {
      slideIndex: 0,
      title: "The problem",
      visibleText: "Presenters lose pace and timing under pressure.",
      speakerNotes: "Explain why feedback currently arrives too late.",
    },
    {
      slideIndex: 1,
      title: "Voxa Cue",
      visibleText: "Private real-time haptic coaching.",
      speakerNotes: "Show the wearable and explain the coaching loop.",
    },
  ],
};

export const validDeckPlanResponse: DeckPlanResponse = {
  schemaVersion: 1,
  title: "Voxa Cue Product Pitch",
  checkpoints: [
    {
      id: "slide-0",
      slideIndex: 0,
      label: "Problem",
      targetCumulativeSeconds: 75,
      semanticSummary: "Presenters struggle with pace and time under pressure.",
      anchorTerms: ["feedback arrives late", "presentation pressure"],
    },
    {
      id: "slide-1",
      slideIndex: 1,
      label: "Solution",
      targetCumulativeSeconds: 180,
      semanticSummary: "Voxa Cue supplies private haptic coaching in real time.",
      anchorTerms: ["haptic coaching", "wearable feedback"],
    },
  ],
};

export const validInsightRequest: InsightRequest = {
  schemaVersion: 1,
  sessionId: "session-001",
  locale: "en-US",
  transcript:
    "Today I will explain how Voxa Cue gives presenters private feedback while they speak.",
  target: {
    durationSeconds: 180,
    paceMinimumWpm: 130,
    paceMaximumWpm: 160,
  },
  metrics: {
    durationSeconds: 176.4,
    speakingSeconds: 138.2,
    averageWpm: 148,
    timeInPaceRangeRatio: 0.78,
    fillerCount: 4,
    fillersPerMinute: 1.74,
    talkRatio: 0.783,
    pitchRangeSemitones: 8.4,
    energyRangeDb: 13.2,
    completedOnTime: true,
  },
  checkpoints: [
    {
      id: "slide-0",
      label: "Problem",
      targetCumulativeSeconds: 75,
      observedCumulativeSeconds: 72.1,
      confidence: 0.91,
      status: "reached",
    },
  ],
  cueEvents: [
    {
      sequence: 4,
      kind: "tooFast",
      elapsedSeconds: 44.2,
      reason: "Pace remained above 160 WPM for four seconds.",
      deliveryStatus: "completed",
    },
  ],
};

export const validInsightResponse: InsightResponse = {
  schemaVersion: 1,
  overallSummary:
    "You finished on time and kept most of the presentation within your target pace.",
  strengths: [
    {
      title: "Strong timing",
      evidence: "The 176-second presentation finished inside the 180-second target.",
    },
  ],
  priorities: [
    {
      title: "Stabilize fast sections",
      evidence: "A too-fast cue fired 44 seconds into the presentation.",
      nextAction: "Pause briefly after each key claim in the opening minute.",
    },
  ],
  drills: [
    {
      title: "Opening pace ladder",
      instructions: "Rehearse the opening three times while holding 130 to 160 WPM.",
      durationMinutes: 5,
    },
  ],
  confidenceNote:
    "Feedback is based on the supplied transcript and session metrics only.",
};
