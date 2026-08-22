//
//  CreatorProfileService.swift
//  OnePlan
//

import Foundation
import SwiftUI

typealias CreatorProfileDto = Components.Schemas.CreatorProfileDto

@MainActor
@Observable
final class CreatorProfileService {
    var isLoading = false
    var profile: CreatorProfileDto?
    var error: String?

    private var client: Client { APIClient.shared }

    func fetchCreatorProfile(userId: Int) async {
        if isLoading { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await client.getCreatorProfile(
                .init(path: .init(userId: userId))
            )
            profile = try response.ok.body.json
            error = nil
        } catch {
            print("CreatorProfileService.fetchCreatorProfile error: \(error)")
            self.error = String(localized: "Failed to load creator profile")
        }
    }

    var listings: [RecommendedMarketplaceItem] {
        guard let profile else { return [] }
        return profile.listings.map(mapListing)
    }

    private func mapListing(_ dto: MarketplaceListingDto) -> RecommendedMarketplaceItem {
        let currency = Currency(from: dto.currency.value1) ?? .VND
        return RecommendedMarketplaceItem(
            creatorName: dto.creatorName,
            creatorAvatarUrl: dto.creatorAvatarUrl,
            isCreatorVerified: false,
            title: dto.name,
            priceText: formatPriceText(dto.price, currency: currency),
            tags: dto.tags,
            listingId: dto.id,
            thumbnailUrl: dto.coverImageUrl,
            durationDays: dto.durationDays,
            activityCount: dto.items.count,
            appliedCount: Int(dto.appliedCount),
            averageRating: dto.averageRating.flatMap { Double($0) },
            ratingCount: Int(dto.ratingCount)
        )
    }

    private func formatPriceText(_ rawPrice: String, currency: Currency) -> String {
        let amount = NSDecimalNumber(string: rawPrice)
        guard amount != .notANumber else {
            return "From \(rawPrice)\(currency.symbol)/person"
        }
        let whole = CurrencyFormatter.formatWhole(amount.doubleValue)
        return "From \(whole)\(currency.symbol)/person"
    }
}
