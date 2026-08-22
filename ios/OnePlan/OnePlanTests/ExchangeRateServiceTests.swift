//
//  ExchangeRateServiceTests.swift
//  OnePlanTests
//
//  Unit tests for ExchangeRateService that do NOT hit the network.
//  We construct a `Client` pointing at an unreachable URL and only
//  exercise code paths that short-circuit before a network call:
//   - same-currency rate()
//   - cachedRate() peek
//   - fresh cache hit on rate()
//  Test seeding uses the `_seedCacheForTesting` internal helper.
//

import Foundation
import Testing
import OpenAPIRuntime
import OpenAPIURLSession
@testable import OnePlan

@MainActor
@Suite("ExchangeRateService")
struct ExchangeRateServiceTests {

    /// Build a service wired to a non-network `Client`. The transport here
    /// would fail on a real request, but these tests never trigger one.
    private func makeService() -> ExchangeRateService {
        let client = Client(
            serverURL: URL(string: "http://127.0.0.1:1")!,
            transport: URLSessionTransport()
        )
        return ExchangeRateService(client: client)
    }

    // MARK: - Same-currency short-circuit

    @Test("rate(from: .VND, to: .VND) returns 1.0 without a fetch")
    func sameCurrencyShortCircuits() async throws {
        let service = makeService()
        let rate = try await service.rate(from: .VND, to: .VND)
        #expect(rate == 1.0)
        // No inflight fetch should have been created.
        #expect(service._inflightCountForTesting == 0)
    }

    @Test("convert with same currency returns amount unchanged")
    func convertSameCurrency() async throws {
        let service = makeService()
        let out = try await service.convert(123_456, from: .USD, to: .USD)
        #expect(out == 123_456)
    }

    // MARK: - cachedRate peek

    @Test("cachedRate returns nil when no entry exists")
    func cachedRateMissing() {
        let service = makeService()
        #expect(service.cachedRate(from: .USD, to: .VND) == nil)
    }

    @Test("cachedRate returns 1.0 for same currency without seeding")
    func cachedRateSameCurrency() {
        let service = makeService()
        #expect(service.cachedRate(from: .THB, to: .THB) == 1.0)
    }

    @Test("cachedRate returns seeded value when fresh")
    func cachedRateReturnsSeeded() {
        let service = makeService()
        service._seedCacheForTesting(from: .USD, to: .VND, rate: 24_500)
        #expect(service.cachedRate(from: .USD, to: .VND) == 24_500)
    }

    @Test("cachedRate returns nil when entry is past the staleness window")
    func cachedRateStaleReturnsNil() {
        let service = makeService()
        // staleTolerance is 10 minutes; seed 11 minutes in the past.
        let stalePast = Date().addingTimeInterval(-60 * 11)
        service._seedCacheForTesting(
            from: .USD,
            to: .VND,
            rate: 24_500,
            fetchedAt: stalePast
        )
        #expect(service.cachedRate(from: .USD, to: .VND) == nil)
    }

    // MARK: - Cache hit on rate()

    @Test("After seeding, rate(...) returns the cached value (no fetch)")
    func rateHitsCacheAfterSeed() async throws {
        let service = makeService()
        service._seedCacheForTesting(from: .USD, to: .VND, rate: 24_500)
        let rate = try await service.rate(from: .USD, to: .VND)
        #expect(rate == 24_500)
        // Cache hit means no inflight task was created.
        #expect(service._inflightCountForTesting == 0)
    }

    @Test("Expired cache entry is NOT served — rate(...) would refetch")
    func expiredCacheDoesNotShortCircuit() async {
        let service = makeService()
        let stalePast = Date().addingTimeInterval(-60 * 11) // 11 min ago
        service._seedCacheForTesting(
            from: .USD,
            to: .VND,
            rate: 24_500,
            fetchedAt: stalePast
        )
        // Triggering rate() on a stale entry must hit the network path,
        // which fails against our bogus 127.0.0.1:1 transport. We verify
        // the call throws rather than returning the stale cached value.
        await #expect(throws: (any Error).self) {
            _ = try await service.rate(from: .USD, to: .VND)
        }
    }

    // MARK: - Inflight deduplication

    @Test("Concurrent rate(...) calls that hit cache do NOT create inflight tasks")
    func concurrentCacheHitsDoNotCreateInflight() async throws {
        let service = makeService()
        service._seedCacheForTesting(from: .USD, to: .VND, rate: 24_500)

        async let a = service.rate(from: .USD, to: .VND)
        async let b = service.rate(from: .USD, to: .VND)

        let (ra, rb) = try await (a, b)
        #expect(ra == 24_500)
        #expect(rb == 24_500)
        #expect(service._inflightCountForTesting == 0)
    }

    /// Note on deduplication for actual network fetches:
    /// When two concurrent calls for an uncached pair arrive, the first
    /// populates `inflight[key]` with its Task, and the second awaits that
    /// same Task (lines in `rate(from:to:)`). Directly asserting that in a
    /// unit test requires mocking the generated OpenAPI `Client` — which
    /// is a final concrete type, not a protocol, so it cannot be subclassed
    /// or swapped without heavier test infrastructure. The cache-hit test
    /// above verifies the inflight map stays empty for cache hits; the
    /// deduplication logic is exercised end-to-end in integration tests.
}
