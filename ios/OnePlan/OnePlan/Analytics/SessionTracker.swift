//
//  SessionTracker.swift
//  OnePlan
//

import Foundation

/// Owns the lifecycle of the analytics session id stored on-device.
/// Generates a fresh UUID on cold start or when the app has been backgrounded
/// for longer than `inactivityTimeout`. Persists the most recent session id
/// and `lastBackgroundedAt` to UserDefaults so force-quits roll over correctly.
///
/// Not actor-isolated: UserDefaults is thread-safe, and `AnalyticsClient`
/// (which owns the only instance in production) confines all access to the
/// main actor anyway.
final class SessionTracker: @unchecked Sendable {
    private enum Keys {
        static let sessionId = "analytics.sessionId"
        static let anonymousId = "analytics.anonymousId"
        static let lastBackgroundedAt = "analytics.lastBackgroundedAt"
        static let sessionStartedAt = "analytics.sessionStartedAt"
        // The session id whose `POST /analytics/sessions` the server has
        // confirmed (2xx). Compared against `sessionId` so a rotated session
        // is automatically considered unregistered without extra bookkeeping.
        static let registeredSessionId = "analytics.registeredSessionId"
    }

    /// Time in background after which the next foreground starts a new session.
    private let inactivityTimeout: TimeInterval = 30 * 60

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.string(forKey: Keys.anonymousId) == nil {
            defaults.set(UUID().uuidString, forKey: Keys.anonymousId)
        }
    }

    var currentSessionId: String? {
        defaults.string(forKey: Keys.sessionId)
    }

    var anonymousId: String? {
        defaults.string(forKey: Keys.anonymousId)
    }

    /// True only when the *current* session id has been confirmed registered
    /// with the server. Rotating the session id invalidates this for free
    /// because we compare the stored id, not a bare boolean.
    var isCurrentSessionRegistered: Bool {
        guard let current = currentSessionId,
              let registered = defaults.string(forKey: Keys.registeredSessionId)
        else { return false }
        return current == registered
    }

    /// Records that the server confirmed registration for `id`. Ignored if the
    /// session has since rotated, so we never mark a stale id as registered.
    func markRegistered(id: String) {
        guard id == currentSessionId else { return }
        defaults.set(id, forKey: Keys.registeredSessionId)
    }

    /// Returns `(sessionId, startedAt, isNew, needsRegistration)`.
    /// `isNew == true` means a brand-new session was created — emit `APP_OPEN`.
    /// `needsRegistration == true` means the server has not yet confirmed this
    /// session id (newly created, or a prior `registerSession` never landed) —
    /// the caller must (re)attempt registration. Decoupling the two lets a
    /// failed registration self-heal on the next foreground / login instead of
    /// orphaning the session id forever.
    func resolveForegroundSession(now: Date = Date()) -> (id: String, startedAt: Date, isNew: Bool, needsRegistration: Bool) {
        let lastBackgrounded = defaults.object(forKey: Keys.lastBackgroundedAt) as? Date
        let existingId = currentSessionId
        let existingStartedAt = defaults.object(forKey: Keys.sessionStartedAt) as? Date

        let isExpired: Bool = {
            guard let lastBackgrounded else { return existingId == nil }
            return now.timeIntervalSince(lastBackgrounded) >= inactivityTimeout
        }()

        if let id = existingId, let startedAt = existingStartedAt, !isExpired {
            // Reused session: not new, but still needs registration if the
            // server never confirmed it (e.g. the original POST hit a
            // pre-auth 401 and was silently dropped).
            return (id, startedAt, false, !isCurrentSessionRegistered)
        }

        let newId = UUID().uuidString
        defaults.set(newId, forKey: Keys.sessionId)
        defaults.set(now, forKey: Keys.sessionStartedAt)
        defaults.removeObject(forKey: Keys.lastBackgroundedAt)
        return (newId, now, true, true)
    }

    func markBackgrounded(at date: Date = Date()) {
        defaults.set(date, forKey: Keys.lastBackgroundedAt)
    }
}
