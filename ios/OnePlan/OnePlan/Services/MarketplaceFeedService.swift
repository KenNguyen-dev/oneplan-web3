//
//  MarketplaceFeedService.swift
//  OnePlan
//

import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

typealias MarketplaceFeedDto = Components.Schemas.MarketplaceFeedDto
typealias MarketplaceFeedItemDto = Components.Schemas.MarketplaceFeedItemDto
typealias MarketplaceFeedMatchedScope = Components.Schemas.MarketplaceFeedDto.matchedDestinationScopePayload

struct MarketplaceFeedFilters: Equatable {
    var tab: Operations.listMarketplaceFeed.Input.Query.tabPayload = .TRENDING
    var cityId: Int?
    var stateId: Int?
    var countryId: Int?
    var durationMinDays: Int?
    var durationMaxDays: Int?
    var tag: Components.Schemas.ListingTag?
    var budgetSort: Operations.listMarketplaceFeed.Input.Query.budgetSortPayload?
}

@MainActor
@Observable
final class MarketplaceFeedService {
    var isLoadingFeed = false
    var destinationNames: [String] = []
    var recommendedItems: [RecommendedMarketplaceItem] = []
    // Admin-curated featured listings (Home "Popular plans"); empty when no
    // listing is featured — Home falls back to recommendedItems.
    var featuredItems: [RecommendedMarketplaceItem] = []
    var matchedDestinationScope: MarketplaceFeedMatchedScope?
    var error: String?

    private var client: Client { APIClient.shared }
    private var lastFetchedFilters: MarketplaceFeedFilters?

    func listMarketplaceFeed(
        filters: MarketplaceFeedFilters = .init(),
        force: Bool = false,
        take: Int = 20
    ) async {
        if isLoadingFeed { return }
        if !force, lastFetchedFilters == filters { return }

        isLoadingFeed = true
        defer { isLoadingFeed = false }

        do {
            let query = Operations.listMarketplaceFeed.Input.Query(
                take: take,
                tab: filters.tab,
                cityId: filters.cityId,
                stateId: filters.stateId,
                countryId: filters.countryId,
                durationMinDays: filters.durationMinDays,
                durationMaxDays: filters.durationMaxDays,
                tag: filters.tag.flatMap {
                    Operations.listMarketplaceFeed.Input.Query.tagPayload(rawValue: $0.rawValue)
                },
                budgetSort: filters.budgetSort
            )
            let response = try await client.listMarketplaceFeed(.init(query: query))
            let feed = try response.ok.body.json

            destinationNames = feed.destinationNames
            recommendedItems = feed.items.map(mapFeedItem)
            featuredItems = feed.featured.map(mapFeedItem)
            matchedDestinationScope = feed.matchedDestinationScope
            lastFetchedFilters = filters
            error = nil
        } catch {
            if isExpectedCancellation(error) { return }

            print("MarketplaceFeedService.listMarketplaceFeed error: \(error)")
            self.error = String(localized: "Failed to load marketplace feed")

            if lastFetchedFilters == nil {
                destinationNames = []
                recommendedItems = []
                featuredItems = []
                matchedDestinationScope = nil
            }
        }
    }

    func applyListingUpdate(_ info: ListingUpdateInfo) {
        applyToItemLists(listingId: info.listingId) { item in
            item.title = info.name
            item.priceText = formatPriceText(info.rawPrice, currency: info.currency)
            item.tags = info.tags
            item.durationDays = info.durationDays
            if let coverImageUrl = info.coverImageUrl {
                item.thumbnailUrl = coverImageUrl
            }
        }
    }

    func markAsAcquired(listingId: Int) {
        applyToItemLists(listingId: listingId) { $0.isAcquired = true }
    }

    func applyRatingUpdate(_ update: ListingRatingUpdate) {
        applyToItemLists(listingId: update.listingId) { item in
            item.averageRating = update.average
            item.ratingCount = update.count
        }
    }

    // Applies an in-place patch to a listing wherever it appears (the
    // recommended feed and the featured list can hold the same listing).
    private func applyToItemLists(
        listingId: Int,
        _ patch: (inout RecommendedMarketplaceItem) -> Void
    ) {
        if let index = recommendedItems.firstIndex(where: { $0.listingId == listingId }) {
            patch(&recommendedItems[index])
        }
        if let index = featuredItems.firstIndex(where: { $0.listingId == listingId }) {
            patch(&featuredItems[index])
        }
    }

    private func mapFeedItem(_ item: MarketplaceFeedItemDto) -> RecommendedMarketplaceItem {
        let currency = Currency(from: item.currency.value1) ?? .VND
        let averageRating = item.averageRating.flatMap { Double($0) }
        let ratingCount = Int(item.ratingCount)
        return RecommendedMarketplaceItem(
            creatorName: item.creatorName,
            creatorAvatarUrl: item.creatorAvatarUrl,
            isCreatorVerified: false,
            title: item.name,
            priceText: formatPriceText(item.price, currency: currency),
            tags: item.tags,
            listingId: item.id,
            createdById: Int(item.createdById),
            thumbnailUrl: item.coverImageUrl,
            durationDays: item.durationDays,
            activityCount: Int(item.activityCount),
            appliedCount: Int(item.appliedCount),
            isAcquired: item.acquired,
            averageRating: averageRating,
            ratingCount: ratingCount,
            cityName: item.cityName,
            countryName: item.countryName
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

    private func isExpectedCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return true
        }

        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error,
           isExpectedCancellation(underlyingError)
        {
            return true
        }

        return String(describing: error).contains("CancellationError")
    }
}
