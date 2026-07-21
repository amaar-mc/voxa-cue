import Foundation
import Testing
import VoxaCore
@testable import VoxaRuntime

@Test("Roadmap request sends one selected transcript and aggregate history")
func roadmapRequestUsesBoundedPrivateContext() async throws {
    let client = makeRoadmapClient(token: "roadmap-contract-token")
    let summary = roadmapSummary()

    let roadmap = try await client.createRoadmap(
        summary: summary,
        history: roadmapAnalytics(),
        fillerBreakdown: [FillerFrequency(phrase: "um", count: 2)]
    )

    #expect(roadmap.focusFillers == [
        RoadmapFillerFocus(phrase: "um", count: 2, guidance: "Replace the start with one quiet beat.")
    ])
    let capture = try #require(
        AIRoadmapURLProtocol.capture.snapshot(authorization: "Bearer roadmap-contract-token")
    )
    #expect(capture.request.url?.path == "/v1/roadmaps")
    let body = try #require(JSONSerialization.jsonObject(with: capture.body) as? [String: Any])
    #expect(body["sessionId"] == nil)
    #expect(body["name"] == nil)
    let session = try #require(body["session"] as? [String: Any])
    #expect(session["transcript"] as? String == summary.transcript)
    #expect(session["sessionId"] == nil)
    let fillers = try #require(session["fillerBreakdown"] as? [[String: Any]])
    #expect(fillers.first?["phrase"] as? String == "um")
    #expect(fillers.first?["count"] as? Int == 2)
    let history = try #require(body["history"] as? [String: Any])
    #expect(history["sessionCount"] as? Int == 3)
    #expect(history["transcript"] == nil)
    #expect(history["averagePitchRangeSemitones"] is NSNull)
    #expect(history["averageEnergyRangeDb"] is NSNull)
    #expect(history["pausesPerPresentationMinute"] is NSNull)
}

@Test("Roadmap client rejects a model filler claim that is absent from local evidence")
func roadmapClientRejectsUnknownFillerFocus() async throws {
    let client = makeRoadmapClient(token: "invalid-focus-token")

    do {
        _ = try await client.createRoadmap(
            summary: roadmapSummary(),
            history: roadmapAnalytics(),
            fillerBreakdown: [FillerFrequency(phrase: "um", count: 2)]
        )
        Issue.record("Unknown filler focus unexpectedly passed contract validation")
    } catch let error as VoxaAPIError {
        #expect(error == .contractMismatch(requestID: nil))
    }
}

@Test("Roadmap client rejects duplicate filler evidence before making a request")
func roadmapClientRejectsDuplicateFillerEvidence() async throws {
    let token = "duplicate-fillers-token"
    let client = makeRoadmapClient(token: token)

    do {
        _ = try await client.createRoadmap(
            summary: roadmapSummary(),
            history: roadmapAnalytics(),
            fillerBreakdown: [
                FillerFrequency(phrase: "Um", count: 1),
                FillerFrequency(phrase: " um ", count: 1),
            ]
        )
        Issue.record("Duplicate filler evidence unexpectedly reached the API")
    } catch let error as VoxaAPIError {
        #expect(error == .invalidPayload)
    }

    #expect(AIRoadmapURLProtocol.capture.snapshot(authorization: "Bearer \(token)") == nil)
}

@Test("Roadmap and chat clients reject filler totals that disagree with session metrics")
func aiClientsRejectMismatchedFillerTotals() async throws {
    let roadmapToken = "mismatched-roadmap-fillers-token"
    let roadmapClient = makeRoadmapClient(token: roadmapToken)
    do {
        _ = try await roadmapClient.createRoadmap(
            summary: roadmapSummary(),
            history: roadmapAnalytics(),
            fillerBreakdown: [FillerFrequency(phrase: "um", count: 1)]
        )
        Issue.record("Mismatched roadmap filler totals unexpectedly reached the API")
    } catch let error as VoxaAPIError {
        #expect(error == .invalidPayload)
    }
    #expect(AIRoadmapURLProtocol.capture.snapshot(authorization: "Bearer \(roadmapToken)") == nil)

    let chatToken = "mismatched-chat-fillers-token"
    let chatClient = makeRoadmapClient(token: chatToken)
    do {
        _ = try await chatClient.sendCoachMessage(
            summary: roadmapSummary(),
            fillerBreakdown: [FillerFrequency(phrase: "um", count: 1)],
            roadmap: roadmapFixture(),
            messages: [CoachMessage(id: UUID(), role: .user, content: "What should I practice?")]
        )
        Issue.record("Mismatched chat filler totals unexpectedly reached the API")
    } catch let error as VoxaAPIError {
        #expect(error == .invalidPayload)
    }
    #expect(AIRoadmapURLProtocol.capture.snapshot(authorization: "Bearer \(chatToken)") == nil)
}

@Test("Roadmap client accepts normalized model filler spelling and preserves local wording")
func roadmapClientNormalizesModelFillerFocus() async throws {
    let client = makeRoadmapClient(token: "normalized-focus-token")

    let roadmap = try await client.createRoadmap(
        summary: roadmapSummary(),
        history: roadmapAnalytics(),
        fillerBreakdown: [FillerFrequency(phrase: "you know", count: 2)]
    )

    #expect(roadmap.focusFillers.first?.phrase == "you know")
    #expect(roadmap.focusFillers.first?.count == 2)
}

@Test("Coach chat is stateless and sends only user and assistant turns")
func coachChatSendsBoundedConversationContext() async throws {
    let client = makeRoadmapClient(token: "coach-chat-token")
    let messages = [
        CoachMessage(id: UUID(), role: .user, content: "How should I rehearse the opening?"),
        CoachMessage(id: UUID(), role: .assistant, content: "Start with one deliberate pause."),
        CoachMessage(id: UUID(), role: .user, content: "What should I measure next?"),
    ]

    let reply = try await client.sendCoachMessage(
        summary: roadmapSummary(),
        fillerBreakdown: [FillerFrequency(phrase: "um", count: 2)],
        roadmap: roadmapFixture(),
        messages: messages
    )

    #expect(reply.reply == "Track the first minute: aim for one or fewer likely fillers and stay inside your pace range.")
    let capture = try #require(
        AIRoadmapURLProtocol.capture.snapshot(authorization: "Bearer coach-chat-token")
    )
    #expect(capture.request.url?.path == "/v1/coach-chat")
    let body = try #require(JSONSerialization.jsonObject(with: capture.body) as? [String: Any])
    #expect(body["previousResponseId"] == nil)
    #expect(body["history"] == nil)
    let encodedMessages = try #require(body["messages"] as? [[String: Any]])
    #expect(encodedMessages.map { $0["role"] as? String } == ["user", "assistant", "user"])
}

private func makeRoadmapClient(token: String) -> VoxaAPIClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AIRoadmapURLProtocol.self]
    return VoxaAPIClient(
        baseURL: URL(string: "https://api.example.test")!,
        bearerToken: token,
        session: URLSession(configuration: configuration),
        requestTimeoutSeconds: 28
    )
}

private func roadmapSummary() -> SessionSummary {
    SessionSummary(
        sessionID: UUID(uuidString: "99547CD1-F513-4EB9-A1EE-4454C0687546")!,
        name: "Private rehearsal",
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        durationSeconds: 180,
        targetDurationSeconds: 180,
        targetMinimumWPM: 130,
        targetMaximumWPM: 160,
        speakingSeconds: 144,
        averageWPM: 148,
        timeInPaceRange: 0.78,
        fillerCount: 2,
        fillersPerSpeakingMinute: 0.83,
        talkRatio: 0.8,
        paceStandardDeviationWPM: 10,
        pauseCount: 5,
        averagePauseSeconds: 0.9,
        longestPauseSeconds: 1.6,
        pitchRangeSemitones: 7,
        energyRangeDB: 12,
        cueCount: 1,
        transcript: "Um, our product keeps feedback private. Um, the next step is deliberate practice."
    )
}

private func roadmapAnalytics() -> LongTermAnalytics {
    LongTermAnalytics(
        sessionCount: 3,
        totalPresentationSeconds: 540,
        averageWPM: 151,
        timeInPaceRange: 0.72,
        fillersPerSpeakingMinute: 1.4,
        talkRatio: 0.78,
        onTargetSessionRatio: 0.67,
        averageAbsoluteTimingDeviationSeconds: 12,
        averagePaceStandardDeviationWPM: 11,
        averagePitchRangeSemitones: nil,
        averageEnergyRangeDB: nil,
        measuredIntonationSessionCount: 0,
        pausesPerPresentationMinute: nil,
        averagePauseSeconds: nil,
        longestPauseSeconds: nil,
        measuredPauseSessionCount: 0
    )
}

private func roadmapFixture() -> PracticeRoadmap {
    PracticeRoadmap(
        schemaVersion: 1,
        headline: "Make the opening quieter",
        summary: "Your clearest next gain is replacing filler starts with a brief pause.",
        focusFillers: [
            RoadmapFillerFocus(phrase: "um", count: 2, guidance: "Replace the start with one quiet beat.")
        ],
        steps: [
            RoadmapStep(phase: .now, title: "Reset the opening", evidence: "Two ums appeared.", action: "Pause before sentence one.", measurableTarget: "At most one um."),
            RoadmapStep(phase: .next, title: "Hold pace", evidence: "Pace was mostly in range.", action: "Mark breath points.", measurableTarget: "80% in range."),
            RoadmapStep(phase: .then, title: "Shape emphasis", evidence: "Pitch range was measured.", action: "Stress one word per claim.", measurableTarget: "Practice three claims."),
        ],
        nextSessionGoal: RoadmapGoal(title: "Cleaner first minute", measurement: "Likely filler count", target: "One or fewer"),
        confidenceNote: "Based on the selected transcript and measured session history."
    )
}

private struct AIRoadmapCapturedRequest: Sendable {
    let request: URLRequest
    let body: Data
}

private final class AIRoadmapCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [String: AIRoadmapCapturedRequest] = [:]

    func record(_ request: URLRequest, body: Data) {
        guard let authorization = request.value(forHTTPHeaderField: "Authorization") else { return }
        lock.lock()
        requests[authorization] = AIRoadmapCapturedRequest(request: request, body: body)
        lock.unlock()
    }

    func snapshot(authorization: String) -> AIRoadmapCapturedRequest? {
        lock.lock()
        defer { lock.unlock() }
        return requests[authorization]
    }
}

private final class AIRoadmapURLProtocol: URLProtocol, @unchecked Sendable {
    static let capture = AIRoadmapCapture()

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let body = Self.readBody(from: request), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotDecodeRawData))
            return
        }
        Self.capture.record(request, body: body)
        let authorization = request.value(forHTTPHeaderField: "Authorization")
        let responseBody: Data
        if url.path == "/v1/coach-chat" {
            responseBody = Data(
                #"{"schemaVersion":1,"reply":"Track the first minute: aim for one or fewer likely fillers and stay inside your pace range.","suggestedPrompts":["Give me a two-minute drill"]}"#.utf8
            )
        } else {
            let phrase: String
            if authorization == "Bearer invalid-focus-token" {
                phrase = "basically"
            } else if authorization == "Bearer normalized-focus-token" {
                phrase = "You   Know"
            } else {
                phrase = "um"
            }
            responseBody = Data(
                """
                {"schemaVersion":1,"headline":"Make the opening quieter","summary":"Your clearest next gain is replacing filler starts with a brief pause.","focusFillers":[{"phrase":"\(phrase)","count":2,"guidance":"Replace the start with one quiet beat."}],"steps":[{"phase":"now","title":"Reset the opening","evidence":"Two ums appeared.","action":"Pause before sentence one.","measurableTarget":"At most one um."},{"phase":"next","title":"Hold pace","evidence":"Pace was mostly in range.","action":"Mark breath points.","measurableTarget":"80% in range."},{"phase":"then","title":"Shape emphasis","evidence":"Pitch range was measured.","action":"Stress one word per claim.","measurableTarget":"Practice three claims."}],"nextSessionGoal":{"title":"Cleaner first minute","measurement":"Likely filler count","target":"One or fewer"},"confidenceNote":"Based on the selected transcript and measured session history."}
                """.utf8
            )
        }
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let bytesRead = stream.read(&buffer, maxLength: buffer.count)
            if bytesRead < 0 { return nil }
            if bytesRead == 0 { return body }
            body.append(buffer, count: bytesRead)
        }
    }
}
