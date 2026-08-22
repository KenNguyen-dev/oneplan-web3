//
//  PinExtractionSessionService.swift
//  OnePlan
//
//  Holds the in-flight pin-extraction session as app-wide state so that
//  extraction continues running across ProcessPinView mount/unmount cycles.
//  Single-source-of-truth for:
//   - BoardScanningCard on BoardView (binds to `activeSession`),
//   - ProcessPinView (renders `phase` / `pins` / `videoDescription` / ...).
//
//  The SSE consumer lives here — not in the view — so the stream survives
//  navigation. Server-side, extraction is fully detached from the SSE
//  connection: closing the socket no longer aborts the work.
//

import Foundation
import OpenAPIRuntime

typealias PinExtractionSessionServerDto = Components.Schemas.PinExtractionSessionDto
typealias PinExtractionSessionStatus = Components.Schemas.PinExtractionSessionStatus
typealias ServerExtractedPinDto = Components.Schemas.ExtractedPinDto

extension Notification.Name {
    nonisolated(unsafe) static let pinExtractionSessionUpdated =
        Notification.Name("pinExtractionSessionUpdated")
    // Posted after a scan-credit pack purchase is validated so balance
    // badges refresh without waiting for a scan/scenePhase change.
    nonisolated(unsafe) static let scanCreditBalanceChanged =
        Notification.Name("scanCreditBalanceChanged")
}

@MainActor
@Observable
final class PinExtractionSessionService {
    static let shared = PinExtractionSessionService()

    // The server-confirmed snapshot. Refreshed by refresh(), start(),
    // attach(), and cancel(); also kept in sync as the SSE stream arrives.
    private(set) var activeSession: PinExtractionSessionServerDto?

    // Streaming state mirrors what ProcessPinView used to hold as @State.
    // Updated as the SSE stream arrives, OR set wholesale from the server
    // snapshot on attach()/refresh().
    private(set) var phase: PinExtractionPhase = .queued
    private(set) var pins: [ExtractedPinDto] = []
    private(set) var videoDescription: String?
    private(set) var thumbnailURL: URL?
    private(set) var streamFinished = false
    private(set) var failureMessage: String?
    private(set) var fromCache = false

    // Populated when `start()` is rejected with HTTP 402 by the server.
    // Views present QuotaExceededSheet by binding to this. Cleared once the
    // user dismisses the sheet (clearCreditError()).
    var lastCreditError: InsufficientScanCreditsError?

    func clearCreditError() {
        lastCreditError = nil
    }

    private var client: PinExtractionClient?
    private var streamTask: Task<Void, Never>?
    // Read by NotificationDelegate to decide whether to suppress the
    // foreground banner — we only suppress when the user is literally
    // viewing ProcessPinView for this exact session.
    private(set) var attachedSessionId: String?

    private var apiClient: Client { APIClient.shared }

    // MARK: - Public surface

    // Reload the active session from the server. Idempotent; safe to call
    // on every BoardView appearance or scene-phase change. Does not open
    // an SSE stream — BoardView only needs the snapshot.
    func refresh() async {
        do {
            let response = try await apiClient.getActivePinExtraction(.init())
            switch response {
            case .ok(let r):
                let envelope = try r.body.json
                if let payload = envelope.session {
                    applyServerSnapshot(payload)
                } else {
                    clearLocal()
                }
            case .undocumented:
                clearLocal()
            }
        } catch {
            // Best-effort refresh — don't surface failures. If the user
            // really has an active session, the next interaction will retry.
            print("PinExtractionSessionService.refresh error: \(error)")
        }
    }

    // Start a new extraction. Throws if the server has a different URL
    // running (409); the throwing path's existingSessionId can be used to
    // attach to the in-flight one instead. Throws
    // PinExtractionError.insufficientCredits with a structured payload when the
    // user has no scan credits — views observe `lastCreditError` to present
    // QuotaExceededSheet.
    @discardableResult
    func start(sourceUrl: String) async throws -> String {
        // If we already have a live session for any URL, the server will
        // either return its id (same URL) or 409 (different URL). Either
        // way we don't open a second stream blindly.
        do {
            let existing = try await postStart(sourceUrl: sourceUrl)
            await attach(sessionId: existing)
            return existing
        } catch let error as PinExtractionError {
            if case .insufficientCredits(let credits) = error {
                lastCreditError = credits
            }
            throw error
        }
    }

    // Attach to an existing session. Idempotent — no-op when already
    // attached to the same id. When the id differs from the current
    // attachment, tears down the previous client+task first so we don't
    // leak the SSE socket on repeated re-mounts.
    func attach(sessionId: String) async {
        if attachedSessionId == sessionId, client != nil { return }
        teardownStream()

        // Pull the server snapshot first so the view has immediate state
        // even if the SSE socket takes a moment to open.
        do {
            let snapshot = try await apiClient.getPinExtraction(
                .init(path: .init(sessionId: sessionId))
            )
            switch snapshot {
            case .ok(let r):
                let payload = try r.body.json
                applyServerSnapshot(payload)
            case .undocumented(let code, _):
                failureMessage = "Couldn't load extraction (\(code))"
                return
            }
        } catch {
            failureMessage = "Couldn't load extraction: \(error.localizedDescription)"
            return
        }

        attachedSessionId = sessionId

        // If the session is already terminal, don't open SSE — the
        // snapshot above already has everything.
        if streamFinished { return }

        let newClient = PinExtractionClient()
        client = newClient
        streamTask = Task { [weak self] in
            await self?.consumeStream(client: newClient, sessionId: sessionId)
        }
    }

    // Cancel a running session OR dismiss a terminal one. The server
    // treats both with the same DELETE endpoint.
    func cancel(sessionId: String) async {
        do {
            _ = try await apiClient.cancelPinExtraction(
                .init(path: .init(sessionId: sessionId))
            )
        } catch {
            print("PinExtractionSessionService.cancel error: \(error)")
        }
        teardownStream()
        clearLocal()
        NotificationCenter.default.post(name: .pinExtractionSessionUpdated, object: nil)
    }

    // Convenience wrapper: dismiss the currently-active terminal session.
    func dismiss() async {
        guard let id = activeSession?.id else { return }
        await cancel(sessionId: id)
    }

    // Called by ProcessPinView after MKLocalSearch returns a result for a
    // pin. Writes the verified address/coordinate back into the service's
    // pin array so the resume flow doesn't lose enrichment. We re-find
    // by index AND name to defend against the unlikely case where the
    // session rolled over while the enrichment was in flight.
    func applyEnrichment(
        index: Int,
        name: String,
        address: String,
        latitude: Double,
        longitude: Double
    ) {
        guard let i = pins.firstIndex(where: { $0.index == index && $0.name == name })
        else { return }
        pins[i].address = address
        pins[i].latitude = latitude
        pins[i].longitude = longitude
        pins[i].isVerified = true
    }

    // MARK: - Internal

    private func postStart(sourceUrl: String) async throws -> String {
        let response = try await apiClient.startPinExtraction(
            .init(body: .json(.init(sourceUrl: sourceUrl)))
        )
        switch response {
        case .created(let r):
            let body = try r.body.json
            return body.sessionId
        case .code402(let r):
            // Typed scan-credit body — decode directly via the helper.
            let body = try r.body.json
            throw PinExtractionError.insufficientCredits(
                PinExtractionClient.creditsError(from: body)
            )
        case .undocumented(let code, let payload):
            // 409 conflict still arrives as undocumented (no @ApiResponse for
            // it). Bridge through the generic extractor so the existing
            // sessionId is preserved.
            let extracted = await PinExtractionClientErrorReader.read(payload: payload)
            if let credits = extracted.creditError {
                throw PinExtractionError.insufficientCredits(credits)
            }
            throw PinExtractionError.serverRejected(
                status: code,
                message: extracted.message,
                existingSessionId: extracted.existingSessionId
            )
        }
    }

    private func consumeStream(
        client: PinExtractionClient,
        sessionId: String
    ) async {
        do {
            for try await event in client.stream(sessionId: sessionId) {
                if Task.isCancelled { break }
                apply(event: event)
            }
        } catch is CancellationError {
            // expected on teardown
        } catch {
            failureMessage = error.localizedDescription
            streamFinished = true
        }
    }

    private func apply(event: PinExtractionEvent) {
        switch event {
        case .status(let p):
            phase = p
        case .videoMeta(let meta):
            let resolved =
                meta.description?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? meta.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let resolved, !resolved.isEmpty {
                videoDescription = resolved
            }
            if let thumb = meta.thumbnail?.trimmingCharacters(in: .whitespacesAndNewlines),
               !thumb.isEmpty,
               let url = URL(string: thumb) {
                thumbnailURL = url
            }
        case .pin(let p):
            // Replace by index when already present; else append. Critically:
            // preserve any client-side enrichment for the matching pin so an
            // SSE replay (on attach after dismiss) doesn't wipe seals/coords.
            if let i = pins.firstIndex(where: { $0.index == p.index }) {
                pins[i] = Self.merge(server: p, local: pins[i])
            } else {
                pins.append(p)
            }
        case .done(_, _, let cache):
            fromCache = cache
            streamFinished = true
            // Refresh activeSession's status so BoardScanningCard flips
            // from "Scanning" to "Done" without waiting for another GET.
            Task { await refresh() }
        case .failure(_, let message):
            failureMessage = message
            streamFinished = true
            Task { await refresh() }
        }
        NotificationCenter.default.post(name: .pinExtractionSessionUpdated, object: nil)
    }

    // Updates the in-memory state to match the server snapshot. Used by
    // refresh() and attach() — both rely on the typed GET for the initial
    // hydration so the view has data even before SSE opens.
    private func applyServerSnapshot(_ dto: PinExtractionSessionServerDto) {
        activeSession = dto
        attachedSessionId = dto.id

        if let phaseString = dto.phase,
           let parsed = PinExtractionPhase(rawValue: phaseString) {
            phase = parsed
        }

        videoDescription =
            dto.videoMeta?.description?.trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
            ?? dto.videoMeta?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        thumbnailURL = dto.videoMeta?.thumbnail
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            .flatMap(URL.init(string:))

        // Merge rather than replace so a server snapshot (e.g. refresh()
        // after `done`) doesn't wipe client-side MKLocalSearch enrichment
        // — the server has no idea about isVerified/address/lat/lng we
        // resolved locally.
        let serverPins = dto.pins.map { Self.localPin(from: $0) }
        pins = serverPins.map { serverPin in
            if let localPin = pins.first(where: {
                $0.index == serverPin.index && $0.name == serverPin.name
            }) {
                return Self.merge(server: serverPin, local: localPin)
            }
            return serverPin
        }
        fromCache = dto.fromCache

        // swift-openapi-generator wraps allOf-referenced enums in a
        // single-value struct, so the actual enum case lives at `.value1`
        // (same pattern as TripDto.status.value1 elsewhere in the app).
        switch dto.status.value1 {
        case .DONE, .FAILED, .CANCELLED:
            streamFinished = true
        case .QUEUED, .RUNNING:
            streamFinished = false
        }

        if dto.status.value1 == .FAILED {
            failureMessage = dto.errorMessage ?? "Extraction failed."
        } else {
            failureMessage = nil
        }
    }

    private func clearLocal() {
        activeSession = nil
        attachedSessionId = nil
        phase = .queued
        pins = []
        videoDescription = nil
        thumbnailURL = nil
        streamFinished = false
        failureMessage = nil
        fromCache = false
    }

    private func teardownStream() {
        streamTask?.cancel()
        streamTask = nil
        client?.cancel()
        client = nil
    }

    // When a fresher server-shape pin arrives (SSE replay or REST refresh)
    // and we already have a verified local copy, preserve the local
    // enrichment fields. The server is authoritative for everything else
    // (name, notes, city, country, category, sourceTimestampSec).
    private static func merge(
        server: ExtractedPinDto,
        local: ExtractedPinDto
    ) -> ExtractedPinDto {
        guard local.isVerified else { return server }
        var merged = server
        merged.address = local.address
        merged.latitude = local.latitude
        merged.longitude = local.longitude
        merged.isVerified = true
        return merged
    }

    private static func localPin(from server: ServerExtractedPinDto) -> ExtractedPinDto {
        ExtractedPinDto(
            index: server.index,
            name: server.name,
            address: server.address,
            latitude: server.latitude,
            longitude: server.longitude,
            notes: server.notes,
            sourceTimestampSec: server.sourceTimestampSec,
            city: server.city,
            country: server.country,
            category: server.category,
            dayNumber: server.dayNumber,
            timeOfDayText: server.timeOfDayText
        )
    }
}

// Bridge for reading 409 conflict bodies through PinExtractionClient's
// existing extractor. We can't call the private static directly, so this
// thin wrapper re-implements the same body-parse contract.
private enum PinExtractionClientErrorReader {
    struct Extracted {
        let message: String?
        let existingSessionId: String?
        let creditError: InsufficientScanCreditsError?
    }

    static func read(payload: OpenAPIRuntime.UndocumentedPayload) async -> Extracted {
        let empty = Extracted(message: nil, existingSessionId: nil, creditError: nil)
        guard let body = payload.body else { return empty }
        guard let data = try? await Data(collecting: body, upTo: 64 * 1024) else {
            return empty
        }
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return empty
        }
        var message: String?
        if let m = obj["message"] as? String {
            message = m
        } else if let arr = obj["message"] as? [String], let first = arr.first {
            message = first
        }
        let sessionId = obj["sessionId"] as? String

        var creditError: InsufficientScanCreditsError?
        if (obj["code"] as? String) == "insufficient_scan_credits" {
            if let bodyData = try? JSONSerialization.data(withJSONObject: obj),
               let decoded = try? JSONDecoder().decode(
                   InsufficientScanCreditsError.self, from: bodyData
               ) {
                creditError = decoded
            }
        }

        return Extracted(
            message: message,
            existingSessionId: sessionId,
            creditError: creditError
        )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
