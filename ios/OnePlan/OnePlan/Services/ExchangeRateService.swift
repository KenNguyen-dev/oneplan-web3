//
//  ExchangeRateService.swift
//  OnePlan
//
//  Fetches currency exchange rates from the server's
//  `GET /exchange-rates?from=X&to=Y` endpoint. Maintains an in-memory
//  cache with a staleness window and deduplicates concurrent fetches.
//

import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

enum CurrencyConversionError: LocalizedError {
    case unsupportedCurrencyCode(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedCurrencyCode(let code):
            return "Unsupported currency code: \(code)"
        }
    }
}

@MainActor
@Observable
final class ExchangeRateService {
    static let shared = ExchangeRateService()

    // MARK: - Cache types

    private struct CacheKey: Hashable {
        let from: Currency
        let to: Currency
    }

    private struct CacheEntry {
        let rate: Double
        let fetchedAt: Date
        let isStale: Bool
    }

    // MARK: - State

    private var cache: [CacheKey: CacheEntry] = [:]
    private var inflight: [CacheKey: Task<Double, Error>] = [:]
    private let staleTolerance: TimeInterval = 60 * 10  // 10 minutes

    /// Test-injected client. In production this stays nil and the service
    /// reads `APIClient.shared` on every call so it picks up fresh auth tokens
    /// after a refresh (the shared client itself re-instantiates when the
    /// token changes).
    private let injectedClient: Client?

    private var client: Client { injectedClient ?? APIClient.shared }

    // MARK: - Init

    /// Production initializer — resolves `APIClient.shared` at call time.
    private init() {
        self.injectedClient = nil
    }

    /// Test-facing initializer. Allows injecting a mock OpenAPI `Client`.
    /// Prefer `ExchangeRateService.shared` outside of tests.
    internal init(client: Client) {
        self.injectedClient = client
    }

    // MARK: - Public API

    /// Get current rate from → to. `from == to` short-circuits to 1.0.
    /// Uses the in-memory cache when an entry exists and is fresher than
    /// `staleTolerance`. Deduplicates concurrent fetches via `inflight`.
    /// Throws on network/decode failure (caller decides how to render "—").
    func rate(from: Currency, to: Currency) async throws -> Double {
        if from == to { return 1.0 }

        let key = CacheKey(from: from, to: to)

        // Fresh cache hit — serve immediately.
        if let entry = cache[key],
           Date().timeIntervalSince(entry.fetchedAt) < staleTolerance {
            return entry.rate
        }

        // Deduplicate concurrent fetches for the same pair.
        if let existing = inflight[key] {
            return try await existing.value
        }

        // Strong capture is safe: the task is held in `inflight[key]` (owned
        // by self), so self cannot deallocate while the task is live.
        let task = Task<Double, Error> {
            return try await self.fetchAndCache(from: from, to: to, key: key)
        }
        inflight[key] = task

        do {
            let value = try await task.value
            inflight[key] = nil
            return value
        } catch {
            inflight[key] = nil
            throw error
        }
    }

    /// Convenience: amount * rate.
    func convert(_ amount: Double, from: Currency, to: Currency) async throws -> Double {
        if from == to { return amount }
        let r = try await rate(from: from, to: to)
        return amount * r
    }

    /// Synchronous cache peek. Returns nil if missing or stale.
    /// Used by UI to render a best-effort preview without triggering a fetch.
    func cachedRate(from: Currency, to: Currency) -> Double? {
        if from == to { return 1.0 }
        let key = CacheKey(from: from, to: to)
        guard let entry = cache[key] else { return nil }
        if Date().timeIntervalSince(entry.fetchedAt) >= staleTolerance {
            return nil
        }
        return entry.rate
    }

    // MARK: - Test hooks

    /// Test-only: seed the in-memory cache with a known rate.
    /// Mirrors what `fetchAndCache` does after a successful network call.
    internal func _seedCacheForTesting(
        from: Currency,
        to: Currency,
        rate: Double,
        fetchedAt: Date = Date(),
        isStale: Bool = false
    ) {
        let key = CacheKey(from: from, to: to)
        cache[key] = CacheEntry(rate: rate, fetchedAt: fetchedAt, isStale: isStale)
    }

    /// Test-only: number of pending inflight fetches.
    internal var _inflightCountForTesting: Int { inflight.count }

    // MARK: - Internals

    private func fetchAndCache(from: Currency, to: Currency, key: CacheKey) async throws -> Double {
        do {
            guard let fromCurrency = from.toAPICurrency,
                  let toCurrency = to.toAPICurrency else {
                throw CurrencyConversionError.unsupportedCurrencyCode(
                    "\(from.rawValue)→\(to.rawValue)"
                )
            }

            let response = try await client.getExchangeRate(
                .init(query: .init(
                    from: fromCurrency,
                    to: toCurrency
                ))
            )

            let dto = try response.ok.body.json
            let entry = CacheEntry(
                rate: dto.rate,
                fetchedAt: Date(),
                isStale: dto.isStale
            )
            cache[key] = entry
            #if DEBUG
            print("[ExchangeRateService] fetched \(from.rawValue)→\(to.rawValue) rate=\(dto.rate) stale=\(dto.isStale)")
            #endif
            return dto.rate
        } catch {
            #if DEBUG
            print("[ExchangeRateService] fetch \(from.rawValue)→\(to.rawValue) FAILED: \(error)")
            #endif
            throw error
        }
    }
}
