//
//  NetworkMonitor.swift
//  OnePlan
//
//  Connectivity source of truth for offline mode. Consumes NWPathMonitor's
//  native AsyncSequence (iOS 17+) on the MainActor — no pathUpdateHandler, no
//  GCD queue, no manual actor hop.
//

import Foundation
import Network
import OpenAPIRuntime

extension Notification.Name {
    /// Posted on a false→true connectivity transition. Used only by non-view
    /// consumers that can't observe `NetworkMonitor.isOnline` via SwiftUI
    /// (e.g. `RealtimeService`). Views should observe `isOnline` with
    /// `.onChange` / `.task(id:)` instead.
    static let networkBecameReachable = Notification.Name("networkBecameReachable")
}

@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isOnline = true

    private var monitorTask: Task<Void, Never>?

    private init() {}

    /// Starts observing connectivity. Idempotent; safe to call once at launch.
    func start() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            // NWPathMonitor is itself an AsyncSequence of NWPath (both Sendable,
            // iOS 17+). The iterator is intentionally non-Sendable, so it lives
            // entirely inside this single for-await in this single Task.
            for await path in NWPathMonitor() {
                self?.update(isOnline: path.status == .satisfied)
            }
        }
    }

    private func update(isOnline newValue: Bool) {
        let wasOffline = !isOnline
        isOnline = newValue
        if wasOffline, newValue {
            NotificationCenter.default.post(name: .networkBecameReachable, object: nil)
        }
    }
}

/// Classifies an error as "device is offline" so read paths can fall back to
/// cached data instead of surfacing an error.
///
/// The typed unwrap MUST come first: `OpenAPIRuntime.ClientError` is a plain
/// Swift struct (not `CustomNSError`), so bridging it via `as NSError` yields a
/// synthetic error whose `NSUnderlyingErrorKey` is nil — the wrapped `URLError`
/// would never be reached by the NSError walk alone.
///
/// `.timedOut` is deliberately NOT treated as offline: timeouts frequently
/// happen while fully online (slow/overloaded server), and we don't want a real
/// backend outage to silently show stale data behind an "Offline" banner.
func isOfflineError(_ error: Error) -> Bool {
    if let clientError = error as? ClientError {
        return isOfflineError(clientError.underlyingError)
    }

    if let urlError = error as? URLError {
        switch urlError.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .cannotConnectToHost,
             .dataNotAllowed,
             .cannotFindHost:
            return true
        default:
            return false
        }
    }

    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain {
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorCannotConnectToHost,
             NSURLErrorDataNotAllowed,
             NSURLErrorCannotFindHost:
            return true
        default:
            break
        }
    }

    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
        return isOfflineError(underlying)
    }

    return false
}
