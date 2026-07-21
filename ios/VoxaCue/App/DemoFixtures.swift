import Foundation
import VoxaCore

enum DemoFixtures {
    static func sessions() -> [SessionSummary] {
        [
            SessionSummary(
                sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
                name: "Keystone Practice",
                startedAt: Date(timeIntervalSince1970: 1_783_987_200),
                durationSeconds: 155,
                targetDurationSeconds: 180,
                targetMinimumWPM: 130,
                targetMaximumWPM: 160,
                speakingSeconds: 120.9,
                averageWPM: 147,
                timeInPaceRange: 0.76,
                fillerCount: 4,
                fillersPerSpeakingMinute: 1.99,
                talkRatio: 0.78,
                paceStandardDeviationWPM: 11.8,
                pauseCount: 9,
                averagePauseSeconds: 0.92,
                longestPauseSeconds: 1.7,
                pitchRangeSemitones: 7.2,
                energyRangeDB: 13.1,
                cueCount: 3,
                transcript: "Today we are introducing Voxa Cue, a private speech coach that helps presenters adjust without breaking focus."
            ),
            SessionSummary(
                sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
                name: "Team Update",
                startedAt: Date(timeIntervalSince1970: 1_783_814_400),
                durationSeconds: 292,
                targetDurationSeconds: 300,
                targetMinimumWPM: 130,
                targetMaximumWPM: 160,
                speakingSeconds: 216.08,
                averageWPM: 158,
                timeInPaceRange: 0.68,
                fillerCount: 8,
                fillersPerSpeakingMinute: 2.22,
                talkRatio: 0.74,
                paceStandardDeviationWPM: 16.4,
                pauseCount: 13,
                averagePauseSeconds: 0.81,
                longestPauseSeconds: 2.2,
                pitchRangeSemitones: 6.5,
                energyRangeDB: 11.4,
                cueCount: 6,
                transcript: "The team made meaningful progress across the product, hardware, and market research workstreams."
            )
        ]
    }

    static func insight() -> CoachingInsight {
        CoachingInsight(
            schemaVersion: 1,
            overallSummary: "Your delivery was controlled and easy to follow. The strongest next gain is giving key ideas more room before moving on.",
            strengths: [
                EvidenceItem(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
                    title: "Controlled pace",
                    evidence: "You remained inside your target range for most of the session."
                ),
                EvidenceItem(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
                    title: "Clean opening",
                    evidence: "The first minute contained no high-confidence filler words."
                )
            ],
            priorities: [
                CoachingPriority(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000203")!,
                    title: "Pause after evidence",
                    evidence: "Your pace rose immediately after several important statistics.",
                    nextAction: "Add a deliberate one-second pause after each headline number."
                )
            ],
            drills: [
                CoachingDrill(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000204")!,
                    title: "Headline pause drill",
                    instructions: "Read five key claims aloud and hold one full breath after each claim.",
                    durationMinutes: 4
                )
            ],
            confidenceNote: "Deterministic coaching fixture for product demonstration; it is not based on captured audio."
        )
    }

    static func roadmap() -> PracticeRoadmap {
        PracticeRoadmap(
            schemaVersion: 1,
            headline: "Give the strongest ideas more room",
            summary: "Your pace is controlled. The next gain is replacing filler starts with silence and holding a beat after important claims.",
            focusFillers: [
                RoadmapFillerFocus(
                    phrase: "um",
                    count: 2,
                    guidance: "Use one quiet beat before beginning the next sentence."
                )
            ],
            steps: [
                RoadmapStep(
                    phase: .now,
                    title: "Clean the opening",
                    evidence: "Two likely filler starts appeared in the selected transcript.",
                    action: "Rehearse the first minute and pause before every new claim.",
                    measurableTarget: "Use one or fewer likely fillers."
                ),
                RoadmapStep(
                    phase: .next,
                    title: "Hold the pace",
                    evidence: "Most sampled time remained inside the selected pace range.",
                    action: "Mark three breath points and keep them in every rehearsal.",
                    measurableTarget: "Reach 80% of sampled time in range."
                ),
                RoadmapStep(
                    phase: .then,
                    title: "Shape key moments",
                    evidence: "Pitch and energy variation were measurable across the session.",
                    action: "Choose one word to emphasize in each headline sentence.",
                    measurableTarget: "Practice five headline sentences twice."
                ),
            ],
            nextSessionGoal: RoadmapGoal(
                title: "A calmer first minute",
                measurement: "Likely fillers and pace consistency",
                target: "One or fewer fillers and at least 80% in pace"
            ),
            confidenceNote: "Deterministic roadmap fixture for product demonstration; it is not based on captured audio."
        )
    }
}
