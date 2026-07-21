import type {
  CoachChatRequest,
  CoachChatResponse,
  InsightRequest,
  InsightResponse,
  RoadmapRequest,
  RoadmapResponse,
} from "../src/schemas";

export const demoToken = "test-demo-token-with-at-least-32-chars";

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
    paceStandardDeviationWpm: 11.2,
    pauseCount: 7,
    averagePauseSeconds: 0.9,
    longestPauseSeconds: 1.8,
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

export const validRoadmapRequest: RoadmapRequest = {
  schemaVersion: 1,
  locale: "en-US",
  session: {
    transcript:
      "Um, today I will explain Voxa Cue. The product helps presenters stay composed and finish on time.",
    target: validInsightRequest.target,
    metrics: {
      ...validInsightRequest.metrics,
      fillerCount: 3,
    },
    fillerBreakdown: [
      { phrase: "um", count: 1 },
      { phrase: "you know", count: 2 },
    ],
  },
  history: {
    sessionCount: 6,
    totalPresentationSeconds: 1_056,
    averageWpm: 151,
    timeInPaceRangeRatio: 0.71,
    fillersPerMinute: 2.1,
    talkRatio: 0.78,
    onTargetSessionRatio: 0.67,
    averageAbsoluteTimingDeviationSeconds: 14.5,
    averagePaceStandardDeviationWpm: 12.4,
    averagePitchRangeSemitones: 7.8,
    averageEnergyRangeDb: 12.1,
    measuredIntonationSessionCount: 6,
    pausesPerPresentationMinute: 2.4,
    averagePauseSeconds: 0.82,
    longestPauseSeconds: 2.1,
    measuredPauseSessionCount: 6,
  },
};

export const validRoadmapResponse: RoadmapResponse = {
  schemaVersion: 1,
  headline: "Build a calmer opening",
  summary:
    "Your timing and pace baseline are solid. The next improvement is reducing opening fillers while preserving deliberate pauses.",
  focusFillers: [
    {
      phrase: "um",
      count: 1,
      guidance: "Replace the opening filler with one silent breath before the first claim.",
    },
  ],
  steps: [
    {
      phase: "now",
      title: "Rehearse the first sentence",
      evidence: "The selected transcript begins with one detected um.",
      action: "Repeat the opening five times with a silent breath before speaking.",
      measurableTarget: "Complete five openings without a detected filler.",
    },
    {
      phase: "next",
      title: "Stabilize the first minute",
      evidence: "Historical pace consistency is 71 percent.",
      action: "Record three one-minute openings while staying inside the configured pace range.",
      measurableTarget: "Reach at least 80 percent time in pace range in two of three attempts.",
    },
    {
      phase: "then",
      title: "Run the complete presentation",
      evidence: "Four of six measured sessions finished on target.",
      action: "Perform one full rehearsal using the opening routine and planned pauses.",
      measurableTarget: "Finish by the target and use no more than one filler per speaking minute.",
    },
  ],
  nextSessionGoal: {
    title: "Deliver a calm, on-time rehearsal",
    measurement: "Opening fillers, sampled pace range, and completion time",
    target: "No opening filler, at least 80 percent in range, and finish by the configured target.",
  },
  confidenceNote:
    "This roadmap uses one selected transcript and aggregate measurements from six local sessions.",
};

export const validCoachChatRequest: CoachChatRequest = {
  schemaVersion: 1,
  locale: "en-US",
  session: validRoadmapRequest.session,
  roadmap: validRoadmapResponse,
  messages: [
    {
      role: "user",
      content: "How should I practice the opening before tomorrow's presentation?",
    },
  ],
};

export const validCoachChatResponse: CoachChatResponse = {
  schemaVersion: 1,
  reply:
    "Practice five short opening repetitions. Take one silent breath, deliver the first claim, then stop and reset before the next repetition.",
  suggestedPrompts: [
    "How do I pace the first minute?",
    "What should I measure in my next rehearsal?",
  ],
};
