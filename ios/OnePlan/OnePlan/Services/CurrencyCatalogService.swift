//
//  CurrencyCatalogService.swift
//  OnePlan
//

import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

@MainActor
@Observable
final class CurrencyCatalogService {
    static let shared = CurrencyCatalogService()

    private(set) var currencies: [Currency] = Currency.fallbackCurrencies.sorted {
        $0.displayName < $1.displayName
    }
    private(set) var hasLoaded = false
    private(set) var isLoading = false
    private(set) var error: String?

    private let injectedClient: Client?
    private var client: Client { injectedClient ?? APIClient.shared }

    private var currenciesByCode: [String: Currency] = Dictionary(
        uniqueKeysWithValues: Currency.fallbackCurrencies.map { ($0.code, $0) }
    )

    private init() {
        self.injectedClient = nil
    }

    internal init(client: Client, initialCurrencies: [Currency] = Currency.fallbackCurrencies) {
        self.injectedClient = client
        apply(initialCurrencies)
    }

    func loadCurrencies(force: Bool = false) async {
        if isLoading { return }
        if hasLoaded && !force { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await client.listCurrencies()
            let dtos = try response.ok.body.json
            apply(dtos.map(Currency.init(dto:)))
            hasLoaded = true
            error = nil
        } catch {
            print("CurrencyCatalogService.loadCurrencies error: \(error)")
            self.error = String(localized: "Failed to load currencies")
        }
    }

    func currency(from apiCurrency: Components.Schemas.Currency) -> Currency {
        currency(forCode: apiCurrency.rawValue)
    }

    func currency(forCode code: String) -> Currency {
        currenciesByCode[code] ?? Currency.fallback(forCode: code)
    }

    private func apply(_ loadedCurrencies: [Currency]) {
        let deduped = loadedCurrencies.reduce(into: [String: Currency]()) { result, currency in
            result[currency.code] = currency
        }
        currenciesByCode = deduped
        currencies = deduped.values.sorted { $0.displayName < $1.displayName }
    }
}

extension Currency {
    init(dto: Components.Schemas.CurrencyDto) {
        self.init(
            code: dto.code.value1.rawValue,
            name: dto.name,
            symbol: dto.symbol,
            decimalPlaces: Int(dto.decimalPlaces)
        )
    }
}
