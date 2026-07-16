import Foundation
import Testing
import VoxaCore
@testable import VoxaRuntime

@Test("Insight requests preserve explicit JSON null contract fields")
func insightRequestPreservesExplicitNullFields() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [InsightRequestURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let client = VoxaAPIClient(
        baseURL: try #require(URL(string: "https://api.example.test")),
        bearerToken: "test-bearer-token",
        session: session,
        requestTimeoutSeconds: 28
    )
    let sessionID = try #require(UUID(uuidString: "60B7DB55-58A2-4B69-80B7-AEBC95E708DC"))
    let summary = SessionSummary(
        sessionID: sessionID,
        name: "Contract rehearsal",
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        durationSeconds: 176.4,
        targetDurationSeconds: 180,
        targetMinimumWPM: 130,
        targetMaximumWPM: 160,
        speakingSeconds: 138.2,
        averageWPM: 148,
        timeInPaceRange: 0.78,
        fillerCount: 4,
        fillersPerSpeakingMinute: 1.74,
        talkRatio: 0.783,
        pitchRangeSemitones: nil,
        energyRangeDB: nil,
        cueCount: 0,
        transcript: "Today I will explain how Voxa Cue gives presenters private feedback while they speak."
    )
    let checkpoints = [
        SessionCheckpointResult(
            id: "slide-0",
            label: "Problem",
            targetCumulativeSeconds: 75,
            observedCumulativeSeconds: nil,
            confidence: nil,
            status: .missed
        )
    ]
    let cueEvents = [
        SessionCueEvent(
            sequence: nil,
            kind: .tooFast,
            elapsedSeconds: 44.2,
            reason: "Cue was queued when the session ended.",
            deliveryStatus: .pending
        )
    ]

    _ = try await client.createInsight(
        summary: summary,
        checkpoints: checkpoints,
        cueEvents: cueEvents
    )

    let capturedRequest = try #require(
        InsightRequestURLProtocol.capture.snapshot(authorization: "Bearer test-bearer-token")
    )
    #expect(capturedRequest.request.url?.path == "/v1/insights")
    #expect(capturedRequest.request.value(forHTTPHeaderField: "Authorization") == "Bearer test-bearer-token")
    #expect(capturedRequest.request.value(forHTTPHeaderField: "X-Request-Id")?.isEmpty == false)
    #expect(capturedRequest.request.timeoutInterval == 28)
    let json = try #require(JSONSerialization.jsonObject(with: capturedRequest.body) as? [String: Any])
    let metrics = try #require(json["metrics"] as? [String: Any])
    #expect(metrics["pitchRangeSemitones"] is NSNull)
    #expect(metrics["energyRangeDb"] is NSNull)
    let encodedCheckpoints = try #require(json["checkpoints"] as? [[String: Any]])
    let checkpoint = try #require(encodedCheckpoints.first)
    #expect(checkpoint["observedCumulativeSeconds"] is NSNull)
    #expect(checkpoint["confidence"] is NSNull)
    let encodedCueEvents = try #require(json["cueEvents"] as? [[String: Any]])
    let cueEvent = try #require(encodedCueEvents.first)
    #expect(cueEvent["sequence"] is NSNull)
    #expect(cueEvent["deliveryStatus"] as? String == "pending")
}

@Test("Insight requests bound transient short-session rate metrics")
func insightRequestBoundsShortSessionRates() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [InsightRequestURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let client = VoxaAPIClient(
        baseURL: try #require(URL(string: "https://api.example.test")),
        bearerToken: "short-session-test-token",
        session: session,
        requestTimeoutSeconds: 28
    )
    let summary = SessionSummary(
        sessionID: try #require(UUID(uuidString: "806420AA-9058-4B70-8757-14BB754C861A")),
        name: "One-second microphone check",
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        durationSeconds: 1,
        targetDurationSeconds: 30,
        targetMinimumWPM: 130,
        targetMaximumWPM: 160,
        speakingSeconds: 1,
        averageWPM: 1_200,
        timeInPaceRange: 0,
        fillerCount: 10,
        fillersPerSpeakingMinute: 600,
        talkRatio: 1,
        pitchRangeSemitones: nil,
        energyRangeDB: nil,
        cueCount: 0,
        transcript: "Um um um um um um um um um um."
    )

    _ = try await client.createInsight(summary: summary, checkpoints: [], cueEvents: [])

    let capturedRequest = try #require(
        InsightRequestURLProtocol.capture.snapshot(authorization: "Bearer short-session-test-token")
    )
    let json = try #require(JSONSerialization.jsonObject(with: capturedRequest.body) as? [String: Any])
    let metrics = try #require(json["metrics"] as? [String: Any])
    #expect(metrics["averageWpm"] as? Double == 400)
    #expect(metrics["fillersPerMinute"] as? Double == 100)
    #expect(metrics["completedOnTime"] as? Bool == false)
}

@Test("Insight timing distinguishes grace-range completion from finishing by the deadline")
func insightRequestReportsLateGraceRangeAsNotCompletedOnTime() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [InsightRequestURLProtocol.self]
    let client = VoxaAPIClient(
        baseURL: try #require(URL(string: "https://api.example.test")),
        bearerToken: "late-grace-range-token",
        session: URLSession(configuration: configuration),
        requestTimeoutSeconds: 28
    )
    let summary = SessionSummary(
        sessionID: try #require(UUID(uuidString: "ECED7C87-0BEC-49D3-827F-31BCF5A7697A")),
        name: "Slightly late pitch",
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        durationSeconds: 315,
        targetDurationSeconds: 300,
        targetMinimumWPM: 130,
        targetMaximumWPM: 160,
        speakingSeconds: 250,
        averageWPM: 145,
        timeInPaceRange: 0.8,
        fillerCount: 3,
        fillersPerSpeakingMinute: 0.72,
        talkRatio: 0.79,
        pitchRangeSemitones: 7,
        energyRangeDB: 11,
        cueCount: 1,
        transcript: "The presentation landed inside Voxa Cue's display grace range but after the configured deadline."
    )

    _ = try await client.createInsight(summary: summary, checkpoints: [], cueEvents: [])

    let capturedRequest = try #require(
        InsightRequestURLProtocol.capture.snapshot(authorization: "Bearer late-grace-range-token")
    )
    let json = try #require(JSONSerialization.jsonObject(with: capturedRequest.body) as? [String: Any])
    let metrics = try #require(json["metrics"] as? [String: Any])
    #expect(summary.timingOutcome == .onTarget)
    #expect(metrics["completedOnTime"] as? Bool == false)
}

@Test("API readiness exposes the deployed build")
func apiReadinessExposesBuild() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [APIBehaviorURLProtocol.self]
    let client = VoxaAPIClient(
        baseURL: try #require(URL(string: "https://api.example.test")),
        bearerToken: "ready-token",
        session: URLSession(configuration: configuration),
        requestTimeoutSeconds: 28
    )

    let health = try await client.readiness()

    #expect(health.status == "ready")
    #expect(health.service == "voxa-cue-api")
    #expect(health.schemaVersion == 1)
    #expect(health.build == "test-build")
}

@Test("API client maps timeout and authorization failures into actionable errors")
func apiClientMapsOperationalFailures() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [APIBehaviorURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let timeoutClient = VoxaAPIClient(
        baseURL: try #require(URL(string: "https://api.example.test")),
        bearerToken: "timeout-token",
        session: session,
        requestTimeoutSeconds: 28
    )
    let unauthorizedClient = VoxaAPIClient(
        baseURL: try #require(URL(string: "https://api.example.test")),
        bearerToken: "unauthorized-token",
        session: session,
        requestTimeoutSeconds: 28
    )

    do {
        _ = try await timeoutClient.readiness()
        Issue.record("A timed-out request unexpectedly succeeded")
    } catch let error as VoxaAPIError {
        #expect(error == .timedOut(requestID: nil))
    }

    do {
        _ = try await unauthorizedClient.readiness()
        Issue.record("An unauthorized request unexpectedly succeeded")
    } catch let error as VoxaAPIError {
        #expect(error == .unauthorized(requestID: "11111111-1111-4111-8111-111111111111"))
    }
}

private struct CapturedRequest: Sendable {
    let request: URLRequest
    let body: Data
}

private final class CapturedURLRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var capturedRequests: [String: CapturedRequest] = [:]

    func record(_ request: URLRequest, body: Data) {
        guard let authorization = request.value(forHTTPHeaderField: "Authorization") else { return }
        lock.lock()
        capturedRequests[authorization] = CapturedRequest(request: request, body: body)
        lock.unlock()
    }

    func snapshot(authorization: String) -> CapturedRequest? {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequests[authorization]
    }
}

private final class InsightRequestURLProtocol: URLProtocol, @unchecked Sendable {
    static let capture = CapturedURLRequest()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestBody = Self.readBody(from: request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotDecodeRawData))
            return
        }
        Self.capture.record(request, body: requestBody)
        let responseBody = Data(
            #"{"schemaVersion":1,"overallSummary":"You finished on time.","strengths":[{"title":"Strong timing","evidence":"The presentation finished inside its target."}],"priorities":[{"title":"Stabilize pace","evidence":"A fast section occurred.","nextAction":"Pause after each key claim."}],"drills":[{"title":"Pace ladder","instructions":"Rehearse the opening at target pace.","durationMinutes":5}],"confidenceNote":"Feedback uses transcript and metrics only."}"#.utf8
        )
        guard let url = request.url,
              let response = HTTPURLResponse(
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
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }
        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let bytesRead = stream.read(&buffer, maxLength: buffer.count)
            if bytesRead < 0 {
                return nil
            }
            if bytesRead == 0 {
                return body
            }
            body.append(buffer, count: bytesRead)
        }
    }
}

private final class APIBehaviorURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let token = request.value(forHTTPHeaderField: "Authorization")
        if token == "Bearer timeout-token" {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }

        let statusCode = token == "Bearer unauthorized-token" ? 401 : 200
        let body = statusCode == 200
            ? Data(#"{"status":"ready","service":"voxa-cue-api","schemaVersion":1,"build":"test-build"}"#.utf8)
            : Data(#"{"error":{"code":"unauthorized","message":"A valid token is required.","issues":[]}}"#.utf8)
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "application/json",
                    "X-Request-Id": "11111111-1111-4111-8111-111111111111"
                ]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
