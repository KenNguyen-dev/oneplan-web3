//
//  LoginView.swift
//  OnePlan
//
//  Created by ken on 22/3/26.
//

import SwiftUI

struct MarketView: View {
    private let staticDestinationNames: [String]
    private let staticRecommendedItems: [RecommendedMarketplaceItem]
    private let marketplaceFeedService: MarketplaceFeedService?
    private let tripId: Int?
    @Environment(UserProfileService.self) private var userProfileService
    @State private var selectedDiscoveryTab: MarketplaceDiscoveryTab = .trending
    @State private var isShowingLocationPicker = false
    @State private var selectedDestination: SelectedMarketDestination?
    @State private var selectedMarketDurationRange: MarketplaceDurationRange = .oneToThree
    @State private var selectedMarketBudgetSort: MarketplaceBudgetSort?
    @State private var selectedMarketTag: Components.Schemas.ListingTag = .FRIENDS
    @State private var selectedFilters: Set<MarketplaceFilterChip> = []

    init(
        destinationNames: [String] = [],
        recommendedItems: [RecommendedMarketplaceItem] = [],
        tripId: Int? = nil
    ) {
        self.staticDestinationNames = destinationNames
        self.staticRecommendedItems = recommendedItems
        self.marketplaceFeedService = nil
        self.tripId = tripId
    }

    init(
        marketplaceFeedService: MarketplaceFeedService,
        tripId: Int? = nil
    ) {
        self.staticDestinationNames = []
        self.staticRecommendedItems = []
        self.marketplaceFeedService = marketplaceFeedService
        self.tripId = tripId
    }

    fileprivate static let previewDestinationNames: [String] = [
        "Ha Noi", "Bangkok", "Da Nang", "Beijing", "New York",
    ]

    fileprivate static let previewRecommendedItems: [RecommendedMarketplaceItem] = [
        RecommendedMarketplaceItem(
            creatorName: "Vivian solo",
            isCreatorVerified: true,
            title: "Da Lat Trip for Friends",
            priceText: "From 2,500,000đ/person",
            tags: [.FRIENDS],
            listingId: 101,
            durationDays: 5,
            activityCount: 21,
            appliedCount: 134,
            averageRating: 4.8,
            ratingCount: 1280
        ),
        RecommendedMarketplaceItem(
            creatorName: "Huong Local",
            isCreatorVerified: false,
            title: "Da Lat Budget Trip for Couples",
            priceText: "From 2,000,000đ/person",
            tags: [.COUPLES],
            listingId: 102,
            durationDays: 3,
            activityCount: 12,
            appliedCount: 58,
            averageRating: 4.5,
            ratingCount: 312
        ),
        RecommendedMarketplaceItem(
            creatorName: "Tri hay di",
            isCreatorVerified: false,
            title: "Đi ngay đi, rẻ lắm lun ròiiii",
            priceText: "From 2,000,000đ/person",
            tags: [.COUPLES],
            listingId: 103,
            durationDays: 2,
            activityCount: 8,
            appliedCount: 9,
            isAcquired: true,
            averageRating: 4.2,
            ratingCount: 47
        ),
        RecommendedMarketplaceItem(
            creatorName: "Backpacker Minh",
            isCreatorVerified: true,
            title: "Hà Giang Loop Adventure",
            priceText: "From 3,200,000đ/person",
            tags: [.SOLO, .FRIENDS],
            listingId: 104,
            durationDays: 7,
            activityCount: 18,
            appliedCount: 240,
            averageRating: 4.9,
            ratingCount: 10_450
        ),
        RecommendedMarketplaceItem(
            creatorName: "Linh Family Trips",
            isCreatorVerified: false,
            title: "Phú Quốc Family Getaway",
            priceText: "From 4,000,000đ/person",
            tags: [.FAMILY],
            listingId: 105,
            durationDays: 4,
            activityCount: 15,
            appliedCount: 31
        )
    ]

    var body: some View {
        marketBody
            .onAppear {
                AnalyticsClient.shared.track(.MARKET_OPENED)
            }
    }

    private var marketBody: some View {
        Group {
            if isLoadingInitialFeed {
                loadingContent
            } else if shouldShowEmptyState {
                emptyStateContent
            } else {
                marketContent
            }
        }
        .task(id: currentFilters) {
            guard let marketplaceFeedService else { return }
            await marketplaceFeedService.listMarketplaceFeed(filters: currentFilters)
        }
        .fullScreenCover(isPresented: $isShowingLocationPicker) {
            TripLocationPickerSheet(
                isPresented: $isShowingLocationPicker
            ) { city, state, country in
                selectedDestination = SelectedMarketDestination(
                    cityId: city?.id,
                    stateId: state.id,
                    countryId: country.id,
                    cityName: city?.name,
                    stateName: state.name,
                    countryName: country.name
                )
            }
        }
        .scrollIndicators(.hidden)
        .onReceive(NotificationCenter.default.publisher(for: .listingUpdated)) { notification in
            guard let marketplaceFeedService else { return }
            if let info = notification.object as? ListingUpdateInfo {
                marketplaceFeedService.applyListingUpdate(info)
            } else {
                Task { await marketplaceFeedService.listMarketplaceFeed(filters: currentFilters, force: true) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .marketplaceListingRated)) { notification in
            guard let update = notification.object as? ListingRatingUpdate,
                  let marketplaceFeedService else { return }
            marketplaceFeedService.applyRatingUpdate(update)
        }
        .safeAreaPadding(.horizontal, 16)
        .background {
            ZStack(alignment: .top) {
                Color(Constants.Background)
                    .ignoresSafeArea()

                topBlurBackground
                    .ignoresSafeArea(.all, edges: .top)
            }
        }
        .background(Constants.Background)
    }

    private var destinationNames: [String] {
        marketplaceFeedService?.destinationNames ?? staticDestinationNames
    }

    private var recommendedItems: [RecommendedMarketplaceItem] {
        marketplaceFeedService?.recommendedItems ?? staticRecommendedItems
    }

    private var matchedScope: MarketplaceFeedMatchedScope? {
        marketplaceFeedService?.matchedDestinationScope
    }

    private var currentFilters: MarketplaceFeedFilters {
        var filters = MarketplaceFeedFilters()
        filters.tab = selectedDiscoveryTab == .trending ? .TRENDING : .TOP_RATED
        if let destination = selectedDestination {
            filters.cityId = destination.cityId
            filters.stateId = destination.stateId
            filters.countryId = destination.countryId
        }
        if selectedFilters.contains(.duration) {
            let (min, max) = selectedMarketDurationRange.dayBounds
            filters.durationMinDays = min
            filters.durationMaxDays = max
        }
        if selectedFilters.contains(.companions) {
            filters.tag = selectedMarketTag
        }
        if selectedFilters.contains(.budget), let sort = selectedMarketBudgetSort {
            filters.budgetSort = sort == .ascending ? .ASC : .DESC
        }
        return filters
    }

    private var isLoadingInitialFeed: Bool {
        guard let marketplaceFeedService else { return false }
        return marketplaceFeedService.isLoadingFeed
            && marketplaceFeedService.recommendedItems.isEmpty
            && marketplaceFeedService.destinationNames.isEmpty
    }

    private var shouldShowEmptyState: Bool {
        recommendedItems.isEmpty && destinationNames.isEmpty
    }

    private var loadingContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            marketHeader
                .padding(.top, 14)

            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var emptyStateContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            marketHeader
                .padding(.top, 14)

            EmptyMarket()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var marketContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                marketHeader
                    .padding(.top, 14)

                if let originalName = fallbackOriginalName {
                    MarketplaceFallbackHeader(originalName: originalName)
                }

                if !recommendedItems.isEmpty {
                    recommendedSection
                } else if matchedScope == .NONE {
                    EmptyMarket()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                }
            }
            .padding(.bottom, 80)
        }

    }

    private var fallbackOriginalName: String? {
        guard let destination = selectedDestination else { return nil }
        switch matchedScope {
        case .STATE?, .COUNTRY?, .NONE?:
            return destination.mostSpecificName
        default:
            return nil
        }
    }

    private var fallbackBroaderName: String? {
        guard let destination = selectedDestination else { return nil }
        switch matchedScope {
        case .STATE?:
            return destination.stateName
        case .COUNTRY?:
            return destination.countryName
        default:
            return nil
        }
    }

    private var recommendedSectionTitle: String {
        if let broader = fallbackBroaderName {
            return String(localized: "Similar trips in \(broader)", comment: "%@ = broader destination name")
        }
        return String(localized: "Recommended for you")
    }

    private var marketHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            MarketplaceSearchbar(
                selectedDestinationText: selectedDestination?.mostSpecificName,
                selectedTab: selectedDiscoveryTab,
                onSearchTap: { isShowingLocationPicker = true },
                onClearTap: { selectedDestination = nil },
                onTabSelected: { selectedDiscoveryTab = $0 }
            )

            MarketplaceFilterStrip(
                selectedFilters: $selectedFilters,
                selectedDurationRange: $selectedMarketDurationRange,
                selectedBudgetSort: $selectedMarketBudgetSort,
                selectedTag: $selectedMarketTag
            )
        }
    }

    private var recommendedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(recommendedSectionTitle)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundStyle(Constants.ContentM)
                .tracking(-0.7)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                ForEach(recommendedItems) { item in
                    let card = MarketplaceItem(
                        creatorName: item.creatorName,
                        isCreatorVerified: item.isCreatorVerified,
                        unlockText: item.isAcquired ? String(localized: "Unlocked") : String(localized: "Free"),
                        isAcquired: item.isAcquired,
                        title: item.title,
                        averageRating: item.averageRating,
                        ratingCount: item.ratingCount,
                        activitiesText: activityText(for: item),
                        durationText: durationText(for: item),
                        priceText: item.priceText,
                        tags: item.tags,
                        avatarUrl: item.creatorAvatarUrl,
                        thumbnailUrl: item.thumbnailUrl,
                        isOwnListing: isOwnListing(item)
                    )

                    if let listingId = item.listingId {
                        NavigationLink {
                            MarketItemDetailView(
                                listingId: listingId,
                                fallbackItem: item,
                                tripId: tripId
                            )
                        } label: {
                            card
                        }
                        .buttonStyle(.plain)
                    } else {
                        card
                    }
                }
            }
        }
    }

    private func isOwnListing(_ item: RecommendedMarketplaceItem) -> Bool {
        guard let creatorId = item.createdById,
              let myId = userProfileService.profile?.id else { return false }
        return creatorId == myId
    }

    private func durationText(for item: RecommendedMarketplaceItem) -> String {
        let days = max(item.durationDays ?? 3, 1)
        return String(localized: "\(days) days")
    }

    private func activityText(for item: RecommendedMarketplaceItem) -> String {
        let count = max(item.activityCount ?? 0, 0)
        return String(localized: "\(count) activities")
    }

    private var topBlurBackground: some View {
        Circle()
            .fill(
                Color(UIColor(red: 0.2, green: 0.64, blue: 1, alpha: 1))
            )
            .frame(width: 435, height: 455)
            .blur(radius: 60)
            .offset(y: -310)
            .allowsHitTesting(false)
    }

}

struct SelectedMarketDestination: Equatable {
    var cityId: Int?
    var stateId: Int?
    var countryId: Int?
    var cityName: String?
    var stateName: String?
    var countryName: String?

    var mostSpecificName: String {
        cityName ?? stateName ?? countryName ?? ""
    }
}

private extension MarketplaceDurationRange {
    var dayBounds: (min: Int, max: Int) {
        switch self {
        case .oneToThree: (1, 3)
        case .fourToSeven: (4, 7)
        case .eightToFourteen: (8, 14)
        }
    }
}

#Preview {
    MarketView()
        .environment(UserProfileService())
}

#Preview("Populated") {
    MarketView(
        destinationNames: MarketView.previewDestinationNames,
        recommendedItems: MarketView.previewRecommendedItems
    )
    .environment(UserProfileService())
}
