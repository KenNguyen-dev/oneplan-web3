//
//  CurrencyCatalogServiceTests.swift
//  OnePlanTests
//

import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
import Testing
@testable import OnePlan

@MainActor
@Suite("CurrencyCatalogService")
struct CurrencyCatalogServiceTests {
    private func makeService(
        initialCurrencies: [Currency] = [
            Currency(code: "ABC", name: "Alpha Beta Coin", symbol: "A$", decimalPlaces: 3)
        ]
    ) -> CurrencyCatalogService {
        let client = Client(
            serverURL: URL(string: "http://127.0.0.1:1")!,
            transport: URLSessionTransport()
        )
        return CurrencyCatalogService(client: client, initialCurrencies: initialCurrencies)
    }

    @Test("catalog lookup returns loaded server metadata")
    func lookupReturnsLoadedMetadata() {
        let service = makeService()

        let currency = service.currency(forCode: "ABC")

        #expect(currency.code == "ABC")
        #expect(currency.displayName == "Alpha Beta Coin")
        #expect(currency.symbol == "A$")
        #expect(currency.decimalPlaces == 3)
    }

    @Test("unknown lookup falls back safely")
    func unknownLookupFallsBackSafely() {
        let service = makeService()

        let currency = service.currency(forCode: "ZZZ")

        #expect(currency.code == "ZZZ")
        #expect(currency.displayName == "ZZZ")
        #expect(currency.symbol == "ZZZ")
        #expect(currency.decimalPlaces == 2)
    }

    @Test("generated API conversion fails gracefully for unsupported codes")
    func apiConversionFailsGracefully() {
        #expect(Currency.USD.toAPICurrency == .USD)
        #expect(Currency(code: "ZZZ", name: "Unknown", symbol: "ZZZ", decimalPlaces: 2).toAPICurrency == nil)
    }

    @Test("currency equality is based on code")
    func equalityUsesCode() {
        let fallback = Currency.USD
        let serverLoaded = Currency(
            code: "USD",
            name: "US Dollar from Server",
            symbol: "US$",
            decimalPlaces: 2
        )

        #expect(fallback == serverLoaded)
    }
}
