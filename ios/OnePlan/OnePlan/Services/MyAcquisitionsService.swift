//
//  MyAcquisitionsService.swift
//  OnePlan
//

import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

typealias MarketplaceAcquisitionSummaryDto = Components.Schemas.MarketplaceAcquisitionSummaryDto

struct AcquiredPlanItem: Identifiable {
    let id = UUID()
    let acquisitionId: Int
    let listingId: Int?
    let name: String
    let priceText: String
    let tags: [Components.Schemas.ListingTag]
    let coverImageUrl: String?
    let creatorName: String
    let creatorAvatarUrl: String?
    let durationDays: Int
    let activityCount: Int
    let acquiredAt: String
    let listingStillAvailable: Bool
}

@MainActor
@Observable
final class MyAcquisitionsService {
    var isLoading = false
    var hasLoaded = false
    var acquisitions: [AcquiredPlanItem] = []
    var error: String?

    private var client: Client { APIClient.shared }

    func loadAcquisitions(force: Bool = false) async {
        if isLoading { return }
        if hasLoaded && !force { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await client.listMyAcquisitions()
            let dtos = try response.ok.body.json
            acquisitions = dtos.map(Self.mapAcquisition)
            hasLoaded = true
            error = nil
        } catch {
            print("MyAcquisitionsService.loadAcquisitions error: \(error)")
            self.error = String(localized: "Failed to load acquired plans")
            if !hasLoaded {
                acquisitions = []
            }
        }
    }

    private static func mapAcquisition(
        _ dto: MarketplaceAcquisitionSummaryDto
    ) -> AcquiredPlanItem {
        let currency = Currency(from: dto.currency.value1) ?? .VND
        return AcquiredPlanItem(
            acquisitionId: Int(dto.acquisitionId),
            listingId: dto.listingId.map { Int($0) } ?? nil,
            name: dto.name,
            priceText: Self.formatPriceText(dto.price, currency: currency),
            tags: dto.tags,
            coverImageUrl: dto.coverImageUrl,
            creatorName: dto.creatorName,
            creatorAvatarUrl: dto.creatorAvatarUrl,
            durationDays: Int(dto.durationDays),
            activityCount: Int(dto.activityCount),
            acquiredAt: dto.acquiredAt,
            listingStillAvailable: dto.listingStillAvailable
        )
    }

    private static func formatPriceText(_ rawPrice: String, currency: Currency) -> String {
        let amount = NSDecimalNumber(string: rawPrice)
        guard amount != .notANumber else {
            return "From \(rawPrice)\(currency.symbol)/person"
        }
        let whole = CurrencyFormatter.formatWhole(amount.doubleValue)
        return "From \(whole)\(currency.symbol)/person"
    }
}
