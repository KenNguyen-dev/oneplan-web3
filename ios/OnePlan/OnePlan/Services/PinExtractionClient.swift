//
//  PinExtractionClient.swift
//  OnePlan
//
//  Streams extracted pins from the server over SSE. Two-step flow:
//   1. POST /board/pins/extract via the generated OpenAPI client to get a sessionId.
//   2. Open GET /board/pins/extract/:sessionId/stream with raw URLSession.bytes
//      and decode SSE events as they arrive.
//

import Foundation
import OpenAPIRuntime

// SSE payloads aren't representable in OpenAPI 3.0, so the generated client
// has no type for an extracted pin. Define it here — the shape matches the
// server's ExtractedPinDto exactly.
struct ExtractedPinDto: Decodable, Sendable, Equatable {
    let index: Int
    let name: String
    var address: String?
    var latitude: Double?
    var longitude: Double?
    let notes: String?
    let sourceTimestampSec: Double?
    let city: String?
    let country: String?
    let category: String?
    // Itinerary day / time-of-day narrated in the source video ("Day 1", "9am").
    var dayNumber: Int?
    var timeOfDayText: String?
    // Client-only flag set when MKLocalSearch reconciles this pin against
    // Apple Maps. Excluded from the synthesized Decodable via CodingKeys.
    var isVerified: Bool = false

    private enum CodingKeys: String, CodingKey {
        case index, name, address, latitude, longitude, notes, sourceTimestampSec, city, country, category, dayNumber, timeOfDayText
    }
}

enum PinExtractionPhase: String, Sendable {
    case queued
    case cacheHit = "cache_hit"
    case resolving
    case uploading
    case processing
    case analyzing
}

// The session-service path uses this to surface the existing session id
// when a paste collides with an in-flight extraction. The PROC view
// transitions to "attach mode" using this id.
struct PinExtractionServerErrorPayload: Sendable {
    let message: String?
    let existingSessionId: String?
    // Populated when the server rejects the start with HTTP 402 and a
    // `code == "insufficient_scan_credits"` body. Callers convert this into
    // PinExtractionError.insufficientCredits to drive QuotaExceededSheet.
    let creditsError: InsufficientScanCreditsError?

    init(
        message: String?,
        existingSessionId: String?,
        creditsError: InsufficientScanCreditsError? = nil
    ) {
        self.message = message
        self.existingSessionId = existingSessionId
        self.creditsError = creditsError
    }
}

// Mirrors the server's InsufficientScanCreditsErrorDto body — the structured
// payload returned alongside HTTP 402 when a scan has no credits available.
struct InsufficientScanCreditsError: Decodable, Sendable, Equatable {
    let available: Int
    let nextProGrantAt: Date?
    let canPurchase: Bool
    let message: String

    private enum CodingKeys: String, CodingKey {
        case available, nextProGrantAt, canPurchase, message
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.available = try c.decode(Int.self, forKey: .available)
        self.canPurchase =
            try c.decodeIfPresent(Bool.self, forKey: .canPurchase) ?? true
        self.message =
            try c.decodeIfPresent(String.self, forKey: .message)
            ?? String(localized: "You're out of scan credits.")
        if let iso = try c.decodeIfPresent(String.self, forKey: .nextProGrantAt) {
            self.nextProGrantAt =
                ISO8601DateFormatter.withFractionalSeconds.date(from: iso)
                ?? ISO8601DateFormatter().date(from: iso)
        } else {
            self.nextProGrantAt = nil
        }
    }

    init(
        available: Int,
        nextProGrantAt: Date?,
        canPurchase: Bool,
        message: String
    ) {
        self.available = available
        self.nextProGrantAt = nextProGrantAt
        self.canPurchase = canPurchase
        self.message = message
    }
}

private extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

struct VideoMetaDto: Decodable, Sendable, Equatable {
    let title: String?
    let description: String?
    let uploader: String?
    let thumbnail: String?
}

enum PinExtractionEvent: Sendable {
    case status(phase: PinExtractionPhase)
    case videoMeta(VideoMetaDto)
    case pin(ExtractedPinDto)
    case done(sessionId: String, pinCount: Int, fromCache: Bool)
    case failure(code: String, message: String)
}

@MainActor
final class PinExtractionClient {
    private var task: URLSessionDataTask?

    // Dedicated URLSession for the SSE stream. URLSession.shared enforces a
    // ~60s inactivity ceiling that fires during the quiet stretch between
    // `phase: analyzing` and Gemini's first pin (yt-dlp + Files API upload +
    // PROCESSING → ACTIVE polling can easily exceed 60s). We give the session
    // a generous 5-minute window per request and 10 minutes for the whole
    // resource so the long initial silence doesn't kill the connection.
    private static let streamSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300   // per-byte inactivity
        config.timeoutIntervalForResource = 600  // whole-stream cap
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    func cancel() {
        task?.cancel()
        task = nil
    }

    // Kicks off extraction for a pasted Instagram/TikTok URL and yields events
    // (status updates, pins, terminal done/failure) as they arrive. Cancelling
    // the surrounding Task cancels the underlying URLSession streaming task,
    // which on the server side closes the SSE socket (but no longer kills
    // the extraction — that's owned by the session row now).
    func stream(sourceUrl: String) -> AsyncThrowingStream<PinExtractionEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Step 1: POST to start a session.
                    let startResponse = try await APIClient.shared.startPinExtraction(
                        .init(body: .json(.init(sourceUrl: sourceUrl)))
                    )
                    let sessionId: String
                    switch startResponse {
                    case .created(let r):
                        let session = try r.body.json
                        sessionId = session.sessionId
                    case .code402(let r):
                        // The 402 response is typed thanks to the
                        // @ApiResponse decorator on the server. Decode the
                        // structured scan-credit body directly instead of via
                        // the generic extractor.
                        let body = try r.body.json
                        throw PinExtractionError.insufficientCredits(
                            Self.creditsError(from: body)
                        )
                    case .undocumented(let statusCode, let payload):
                        let extracted = await Self.extractServerError(from: payload)
                        if let credits = extracted.creditsError {
                            throw PinExtractionError.insufficientCredits(credits)
                        }
                        throw PinExtractionError.serverRejected(
                            status: statusCode,
                            message: extracted.message,
                            existingSessionId: extracted.existingSessionId
                        )
                    }

                    // Step 2: Open the SSE GET. The generated client cannot
                    // express text/event-stream responses, so we drop down to
                    // URLSession.bytes for the streaming half.
                    try await self.consumeSSE(
                        sessionId: sessionId,
                        continuation: continuation
                    )
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.cancel() }
            }
        }
    }

    // Attach to a previously-started session — skips the POST and goes
    // straight to the SSE stream. Used by PinExtractionSessionService.attach
    // (resume after dismiss, deep-link from push, BoardScanningCard tap).
    func stream(sessionId: String) -> AsyncThrowingStream<PinExtractionEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.consumeSSE(
                        sessionId: sessionId,
                        continuation: continuation
                    )
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.cancel() }
            }
        }
    }

    // Reads the response body of an undocumented payload and pulls out the
    // user-facing message AND (for 409 conflicts) the existing session id.
    // NestJS rejects with one of:
    //   { statusCode, message, error }            // ValidationPipe / generic
    //   { code, message }                         // typed VideoResolverError
    //   { code, message, sessionId }              // 409 extraction_in_progress
    private static func extractServerError(
        from payload: OpenAPIRuntime.UndocumentedPayload
    ) async -> PinExtractionServerErrorPayload {
        guard let body = payload.body else {
            return .init(message: nil, existingSessionId: nil)
        }
        guard let data = try? await Data(collecting: body, upTo: 64 * 1024) else {
            return .init(message: nil, existingSessionId: nil)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return .init(message: nil, existingSessionId: nil)
        }
        guard let obj = json as? [String: Any] else {
            return .init(message: nil, existingSessionId: nil)
        }

        var message: String?
        if let msg = obj["message"] as? String {
            message = msg
        } else if let arr = obj["message"] as? [String], let first = arr.first {
            message = first
        }

        // Nest's BadRequestException + ConflictException both nest the body
        // under top-level "message" when constructed with an object — but in
        // practice we throw `new ConflictException({ code, message, sessionId })`
        // which serializes the whole object as the top-level body. Either
        // way, "sessionId" should be readable at the top level.
        let existingSessionId = obj["sessionId"] as? String

        // Detect the structured 402 scan-credit body. The server's
        // InsufficientScanCreditsException serializes as
        // `{ code: "insufficient_scan_credits", message, available,
        // nextProGrantAt, canPurchase }`. Re-encode the object through Codable
        // so we benefit from the typed decoder (date parsing, optionals).
        var creditsError: InsufficientScanCreditsError?
        if (obj["code"] as? String) == "insufficient_scan_credits" {
            if let bodyData = try? JSONSerialization.data(withJSONObject: obj),
               let decoded = try? JSONDecoder().decode(
                   InsufficientScanCreditsError.self, from: bodyData
               ) {
                creditsError = decoded
            }
        }

        return .init(
            message: message,
            existingSessionId: existingSessionId,
            creditsError: creditsError
        )
    }

    // Maps the OpenAPI-generated 402 body into our local
    // InsufficientScanCreditsError shape.
    static func creditsError(
        from dto: Components.Schemas.InsufficientScanCreditsErrorDto
    ) -> InsufficientScanCreditsError {
        let nextProGrantAt = dto.nextProGrantAt.flatMap { iso in
            ISO8601DateFormatter.withFractionalSeconds.date(from: iso)
                ?? ISO8601DateFormatter().date(from: iso)
        }
        return InsufficientScanCreditsError(
            available: dto.available,
            nextProGrantAt: nextProGrantAt,
            canPurchase: dto.canPurchase,
            message: dto.message
        )
    }

    private func consumeSSE(
        sessionId: String,
        continuation: AsyncThrowingStream<PinExtractionEvent, Error>.Continuation
    ) async throws {
        let env = APIEnvironment.current
        let url = env.serverURL
            .appendingPathComponent("board/pins/extract")
            .appendingPathComponent(sessionId)
            .appendingPathComponent("stream")
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        if let token = AuthTokenStore.shared.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (bytes, response) = try await Self.streamSession.bytes(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode >= 400 {
                continuation.finish(
                    throwing: PinExtractionError.http(status: http.statusCode)
                )
                return
            }
        }

        var currentEvent: String?
        var currentData = ""
        var shouldBreak = false

        // Flush whatever the parser has accumulated. Returns true if a
        // terminal event (done/failure) was emitted and the caller should
        // stop reading.
        func flush() -> Bool {
            defer {
                currentEvent = nil
                currentData = ""
            }
            guard !currentData.isEmpty else { return false }
            guard
                let parsed = Self.parse(
                    eventType: currentEvent,
                    dataJSON: currentData
                )
            else {
                return false
            }
            continuation.yield(parsed)
            if case .done = parsed { return true }
            if case .failure = parsed { return true }
            return false
        }

        for try await line in bytes.lines {
            if line.isEmpty {
                // Spec-compliant end of a record. Flush whatever we have.
                if flush() { shouldBreak = true; break }
                continue
            }

            if line.hasPrefix("event:") {
                // A new event begins. If we already buffered a previous event's
                // data, flush it first — URLSession.AsyncBytes.lines silently
                // collapses the empty separator lines between SSE events, so
                // arrival of a new `event:` is the only reliable boundary.
                if !currentData.isEmpty {
                    if flush() { shouldBreak = true; break }
                }
                currentEvent = line.dropFirst("event:".count).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                currentData = currentData.isEmpty ? payload : currentData + "\n" + payload
            }
            // id: and retry: lines are ignored on purpose.
        }

        if !shouldBreak {
            _ = flush()
        }
        continuation.finish()
    }

    // NestJS @Sse() serializes a MessageEvent two ways depending on version:
    //  - sometimes as `event: <type>\ndata: <jsonOfData>`,
    //  - sometimes as just `data: {"type":"...","data":{...}}` (whole payload).
    // Handle both: prefer the explicit eventType, otherwise try to read a
    // `type` field out of the JSON payload.
    private static func parse(
        eventType: String?,
        dataJSON: String
    ) -> PinExtractionEvent? {
        guard let data = dataJSON.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()

        // Determine the effective event type and the JSON Data containing the
        // inner payload (matching `event.data` on the server).
        let effectiveType: String
        let payloadData: Data
        if let eventType {
            effectiveType = eventType
            payloadData = data
        } else if let envelope = try? decoder.decode(Envelope.self, from: data) {
            effectiveType = envelope.type
            payloadData =
                (try? JSONSerialization.data(withJSONObject: envelope.data))
                ?? Data()
        } else {
            return nil
        }

        switch effectiveType {
        case "status":
            if let payload = try? decoder.decode(StatusPayload.self, from: payloadData),
               let phase = PinExtractionPhase(rawValue: payload.phase) {
                return .status(phase: phase)
            }
            return nil
        case "video_meta":
            if let meta = try? decoder.decode(VideoMetaDto.self, from: payloadData) {
                return .videoMeta(meta)
            }
            return nil
        case "pin":
            if let pin = try? decoder.decode(ExtractedPinDto.self, from: payloadData) {
                return .pin(pin)
            }
            return nil
        case "done":
            if let payload = try? decoder.decode(DonePayload.self, from: payloadData) {
                return .done(
                    sessionId: payload.sessionId,
                    pinCount: payload.pinCount,
                    fromCache: payload.fromCache
                )
            }
            return nil
        case "error":
            if let payload = try? decoder.decode(ErrorPayload.self, from: payloadData) {
                return .failure(code: payload.code, message: payload.message)
            }
            return nil
        default:
            return nil
        }
    }

    private struct Envelope: Decodable {
        let type: String
        // Untyped — we re-encode it before decoding into the concrete payload.
        let data: [String: Any]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.type = try container.decode(String.self, forKey: .type)
            let json = try container.decode(AnyJSON.self, forKey: .data)
            self.data = (json.value as? [String: Any]) ?? [:]
        }

        private enum CodingKeys: String, CodingKey { case type, data }
    }

    private struct AnyJSON: Decodable {
        let value: Any
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let v = try? c.decode(Bool.self) { value = v; return }
            if let v = try? c.decode(Int.self) { value = v; return }
            if let v = try? c.decode(Double.self) { value = v; return }
            if let v = try? c.decode(String.self) { value = v; return }
            if let v = try? c.decode([AnyJSON].self) {
                value = v.map { $0.value }; return
            }
            if let v = try? c.decode([String: AnyJSON].self) {
                value = v.mapValues { $0.value }; return
            }
            value = NSNull()
        }
    }

    private struct StatusPayload: Decodable {
        let phase: String
    }
    private struct DonePayload: Decodable {
        let sessionId: String
        let pinCount: Int
        let fromCache: Bool
    }
    private struct ErrorPayload: Decodable {
        let code: String
        let message: String
    }
}

enum PinExtractionError: LocalizedError {
    case http(status: Int)
    case serverRejected(status: Int, message: String?, existingSessionId: String?)
    case insufficientCredits(InsufficientScanCreditsError)

    var errorDescription: String? {
        switch self {
        case .http(let status):
            return "Server returned HTTP \(status)"
        case .serverRejected(_, let message, _):
            if let message, !message.isEmpty { return message }
            return "We couldn't process that link. Try a public Instagram Reel or TikTok URL."
        case .insufficientCredits(let credits):
            return credits.message
        }
    }

    // Convenience for "is this a conflict that carries a session we can
    // attach to instead of erroring out?"
    var existingSessionId: String? {
        if case .serverRejected(_, _, let id) = self { return id }
        return nil
    }

    var creditsError: InsufficientScanCreditsError? {
        if case .insufficientCredits(let c) = self { return c }
        return nil
    }
}
