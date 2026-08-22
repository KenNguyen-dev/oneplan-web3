//
//  MyListingsService.swift
//  OnePlan
//

import Foundation
import SwiftUI

struct ListingUpdateInfo {
    let listingId: Int
    let name: String
    let rawPrice: String
    let currency: Currency
    let tags: [Components.Schemas.ListingTag]
    let durationDays: Int
    let coverImageUrl: String?
}

struct OwnedListingItem: Identifiable {
    let id = UUID()
    let listingId: Int
    let appliedText: String
    let appliedCount: Int
    var title: String
    var averageRating: Double?
    var ratingCount: Int
    var priceText: String
    var tags: [Components.Schemas.ListingTag]
    var thumbnailUrl: String?
    var durationDays: Int
    var activityCount: Int
    var status: Components.Schemas.MarketplaceListingStatus
}

@MainActor
@Observable
final class MyListingsService {
    var isLoading = false
    var hasLoaded = false
    var listings: [OwnedListingItem] = []
    var error: String?

    private var client: Client { APIClient.shared }

    func loadMyListings(force: Bool = false) async {
        if isLoading { return }
        if hasLoaded && !force { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await client.listMyListings()
            let dtos = try response.ok.body.json

            listings = dtos.map(mapListing)
            hasLoaded = true
            error = nil
        } catch {
            print("MyListingsService.loadMyListings error: \(error)")
            self.error = String(localized: "Failed to load your listings")

            if !hasLoaded {
                listings = []
            }
        }
    }

    func applyUpdate(_ info: ListingUpdateInfo) {
        guard let index = listings.firstIndex(where: { $0.listingId == info.listingId }) else { return }
        listings[index].title = info.name
        listings[index].priceText = formatPriceText(info.rawPrice, currency: info.currency)
        listings[index].tags = info.tags
        listings[index].durationDays = info.durationDays
        if let coverImageUrl = info.coverImageUrl {
            listings[index].thumbnailUrl = coverImageUrl
        }
    }

    private func mapListing(_ dto: MarketplaceListingDto) -> OwnedListingItem {
        let currency = Currency(from: dto.currency.value1) ?? .VND
        return OwnedListingItem(
            listingId: dto.id,
            appliedText: Self.formatAppliedCountText(Int(dto.appliedCount)),
            appliedCount: Int(dto.appliedCount),
            title: dto.name,
            averageRating: dto.averageRating.flatMap { Double($0) },
            ratingCount: Int(dto.ratingCount),
            priceText: formatPriceText(dto.price, currency: currency),
            tags: dto.tags,
            thumbnailUrl: dto.coverImageUrl,
            durationDays: dto.durationDays,
            activityCount: dto.items.count,
            status: dto.status.value1
        )
    }

    private func formatPriceText(_ rawPrice: String, currency: Currency) -> String {
        let amount = NSDecimalNumber(string: rawPrice)
        guard amount != .notANumber else {
            return String(localized: "From \(rawPrice)\(currency.symbol)/person", comment: "%1$@ = price, %2$@ = currency symbol")
        }

        let whole = CurrencyFormatter.formatWhole(amount.doubleValue)
        return String(localized: "From \(whole)\(currency.symbol)/person", comment: "%1$@ = price, %2$@ = currency symbol")
    }

    static func formatAppliedCountText(_ count: Int) -> String {
        "\(max(count, 0))"
    }

    static func formatAppliedSummaryText(_ count: Int) -> String {
        String(localized: "\(formatAppliedCountText(count)) Applied", comment: "%@ = count")
    }
}
