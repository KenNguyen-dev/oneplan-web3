//
//  AnalyticsClient.swift
//  OnePlan
//

import Foundation
import OpenAPIRuntime
import UIKit

/// Singleton analytics client. Owns session lifecycle and a small in-memory
/// queue of client-emitted events that flushes in batches.
///
/// Failures never propagate to callers — analytics must never break a user
/// flow. Events that fail to upload remain in the queue until the next flush.
@MainActor
final class AnalyticsClient {
    static let shared = AnalyticsClient()

    private let tracker: SessionTracker
    private var pendingEvents: [PendingEvent] = []
    private var isFlushing = false
    private let maxBatchSize = 50
    private let maxQueueSize = 500

    private struct PendingEvent {
        let name: AnalyticsEvent
        let occurredAt: Date
        /// Freeform event properties. Values MUST be JSON primitives
        /// (`String`/`Int`/`Bool`/`Double`) or nested arrays/dicts thereof —
        /// anything else makes `OpenAPIObjectContainer` throw at flush time.
        let properties: [String: any Sendable]?
    }

    /// Init is `nonisolated` so the static `shared` initializer expression can
    /// run in any context. The body only assigns a stored property — no
    /// MainActor work happens here. All instance methods remain MainActor.
    nonisolated init(tracker: SessionTracker = SessionTracker()) {
        self.tracker = tracker
    }

    var currentSessionId: String? { tracker.currentSessionId }
    var anonymousId: String? { tracker.anonymousId }

    // MARK: - Lifecycle

    func appDidBecomeActive() {
        resolveAndRegisterSession()
    }

    /// Called right after a successful login. `appDidBecomeActive` fires
    /// before the auth gate, so the very first `registerSession` of a launch
    /// often runs without a token and is rejected (401). Re-attempting here —
    /// now that an access token exists — is what actually lands the session
    /// row in the common cold-start-then-login flow.
    func userDidAuthenticate() {
        resolveAndRegisterSession()
    }

    /// Resolves the foreground session and (re)registers it whenever the
    /// server has not yet confirmed it. Emits `APP_OPEN` only for a genuinely
    /// new session, never on a registration retry.
    private func resolveAndRegisterSession() {
        let session = tracker.resolveForegroundSession()
        if session.isNew {
            track(.APP_OPEN)
        }
        if session.isNew || session.needsRegistration {
            Task { await registerSession(id: session.id, startedAt: session.startedAt) }
        }
    }

    func appDidEnterBackground() {
        tracker.markBackgrounded()
        guard let sessionId = tracker.currentSessionId else { return }
        Task { await endSession(id: sessionId) }
    }

    // MARK: - Tracking

    /// Track an event. `properties` values must be JSON primitives
    /// (`String`/`Int`/`Bool`/`Double`); non-primitive types are dropped at
    /// flush time (see `flush()`).
    func track(_ event: AnalyticsEvent, properties: [String: any Sendable]? = nil) {
        let pending = PendingEvent(
            name: event,
            occurredAt: Date(),
            properties: properties
        )
        if pendingEvents.count >= maxQueueSize {
            pendingEvents.removeFirst()
        }
        pendingEvents.append(pending)
        Task { await flush() }
    }

    // MARK: - Network

    private func registerSession(id: String, startedAt: Date) async {
        let payload = Components.Schemas.StartSessionDto(
            id: id,
            platform: .ios,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            osVersion: UIDevice.current.systemVersion,
            anonymousId: tracker.anonymousId,
            startedAt: ISO8601DateFormatter.fractional.string(from: startedAt)
        )
        do {
            let response = try await APIClient.shared.startAnalyticsSession(
                .init(body: .json(payload))
            )
            _ = try response.noContent  // throws unless the server returned 204
            tracker.markRegistered(id: id)
        } catch {
            // Registration didn't land (commonly a pre-auth 401 at cold
            // start). Deliberately do NOT mark the session registered so
            // the next foreground / login retries instead of orphaning the
            // session id. The server also lazily materializes the session
            // from the first event as a backstop.
        }
    }

    private func endSession(id: String) async {
        let payload = Components.Schemas.EndSessionDto(
            endedAt: ISO8601DateFormatter.fractional.string(from: Date())
        )
        do {
            _ = try await APIClient.shared.endAnalyticsSession(
                .init(path: .init(id: id), body: .json(payload))
            )
        } catch {
            // No-op: session-end is best-effort.
        }
    }

    private func flush() async {
        guard !isFlushing, !pendingEvents.isEmpty else { return }
        isFlushing = true
        defer { isFlushing = false }

        let batch = Array(pendingEvents.prefix(maxBatchSize))
        let dtos: [Components.Schemas.TrackEventDto] = batch.map { event in
            Components.Schemas.TrackEventDto(
                eventName: event.name,
                occurredAt: ISO8601DateFormatter.fractional.string(from: event.occurredAt),
                properties: Self.encodeProperties(event.properties, for: event.name)
            )
        }

        do {
            _ = try await APIClient.shared.trackAnalyticsEvents(
                .init(body: .json(.init(events: dtos)))
            )
            pendingEvents.removeFirst(batch.count)
        } catch {
            // Leave events in the queue; next track() will retry the flush.
        }
    }

    /// Builds the generated `properties` payload from a freeform dict.
    /// `OpenAPIObjectContainer` only accepts JSON primitives; on failure we
    /// drop the properties (not the event) and surface it in debug builds
    /// rather than silently nulling the payload.
    private static func encodeProperties(
        _ properties: [String: any Sendable]?,
        for event: AnalyticsEvent
    ) -> Components.Schemas.TrackEventDto.propertiesPayload? {
        guard let properties, !properties.isEmpty else { return nil }
        var unvalidated: [String: (any Sendable)?] = [:]
        for (key, value) in properties { unvalidated[key] = value }
        do {
            return .init(
                additionalProperties: try OpenAPIObjectContainer(
                    unvalidatedValue: unvalidated
                )
            )
        } catch {
            #if DEBUG
            print("AnalyticsClient: dropping properties for \(event) — \(error)")
            #endif
            return nil
        }
    }
}

private extension ISO8601DateFormatter {
    static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
