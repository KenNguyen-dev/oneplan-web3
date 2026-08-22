//
//  MarketItemDetailView.swift
//  OnePlan
//
//  Created by ken on 22/3/26.
//

import SwiftUI
import UIKit

struct MarketItemDetailView: View {
    let listingId: Int
    let fallbackItem: RecommendedMarketplaceItem?
    let tripId: Int?

    @Environment(UserProfileService.self) private var userProfileService
    @Environment(MarketplaceFeedService.self) private var feedService
    @Environment(StoreManager.self) private var storeManager
    @State private var detailService = MarketplaceListingDetailService()
    @State private var acquisitionService = MarketplaceAcquisitionService()
    @State private var navigateToCreatorId: Int?
    @State private var selectedPlanItemId: Int?
    @State private var activeCover: DetailCover?

    private enum DetailCover: Int, Identifiable {
        case success, paywall
        var id: Int { rawValue }
    }

    init(
        listingId: Int,
        fallbackItem: RecommendedMarketplaceItem? = nil,
        tripId: Int? = nil
    ) {
        self.listingId = listingId
        self.fallbackItem = fallbackItem
        self.tripId = tripId
    }

    private var listing: Components.Schemas.MarketplaceListingDto? {
        detailService.listing
    }

    private var marketItems: [Components.Schemas.MarketItemDto] {
        listing?.items ?? []
    }

    private var sortedMarketItems: [Components.Schemas.MarketItemDto] {
        marketItems.sorted { lhs, rhs in
            if lhs.dayNumber != rhs.dayNumber { return lhs.dayNumber < rhs.dayNumber }
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.id < rhs.id
        }
    }

    private var mappedPlanItems: [PlanItemDto] {
        sortedMarketItems.map { item in
            PlanItemDto(
                id: item.id,
                tripId: listingId,
                planDate: syntheticPlanDate(dayNumber: item.dayNumber),
                title: item.title,
                description: item.description,
                location: item.location,
                latitude: item.latitude,
                longitude: item.longitude,
                address: item.address,
                startTime: item.startTime,
                category: item.category.map { .init(value1: $0.value1) },
                voiceUrl: nil,
                voiceDuration: nil,
                dayNumber: nil,
                sortOrder: item.sortOrder,
                createdAt: item.createdAt,
                members: []
            )
        }
    }

    private var planItemImageUrlsById: [Int: [String]] {
        Dictionary(uniqueKeysWithValues: sortedMarketItems.map { item in
            (item.id, item.imageUrls)
        })
    }

    private var titleText: String {
        listing?.name ?? fallbackItem?.title ?? String(localized: "Marketplace plan")
    }

    private var creatorName: String {
        listing?.creatorName ?? fallbackItem?.creatorName ?? String(localized: "Local creator")
    }

    private var ratingText: String {
        let avg = listing?.averageRating.flatMap { Double($0) }
        let count = listing.map { Int($0.ratingCount) } ?? 0
        return MarketplaceRatingFormatter.formatRatingText(average: avg, count: count)
    }

    private var lastUpdatedCaption: String? {
        guard let listing, Int(listing.ratingCount) > 0 else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard
            let created = iso.date(from: listing.createdAt),
            let updated = iso.date(from: listing.updatedAt),
            updated.timeIntervalSince(created) > 60
        else { return nil }

        return String(localized: "Updated \(DisplayFormatters.date(updated)) · some ratings may predate this", comment: "%@ = last-updated date")
    }

    private var activitiesText: String {
        let count = mappedPlanItems.count
        return String(localized: "\(count) activities")
    }

    private var durationDays: Int {
        if let duration = listing?.durationDays {
            return max(duration, 1)
        }
        if let fallbackDuration = fallbackItem?.durationDays {
            return max(fallbackDuration, 1)
        }
        let maxDayNumber = sortedMarketItems.map(\.dayNumber).max() ?? 1
        return max(maxDayNumber, 1)
    }

    private var durationText: String {
        String(localized: "\(durationDays) days")
    }

    private var descriptionText: String {
        let text = listing?.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty {
            return text
        }
        return String(localized: "A curated trip plan ready to use. Browse the timeline below and enjoy the journey.")
    }

    private var thumbnailUrl: String? {
        listing?.coverImageUrl ?? fallbackItem?.thumbnailUrl
    }

    private var listingCurrency: Currency {
        Currency(from: listing?.currency.value1) ?? .VND
    }

    private var budgetPerPersonText: String {
        if let rawPrice = listing?.price {
            return formatBudgetPerPerson(rawPrice)
        }
        if let fallbackPrice = fallbackItem?.priceText {
            return fallbackPrice
                .replacingOccurrences(of: "From ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(localized: "0\(listingCurrency.symbol)/person", comment: "%@ = currency symbol")
    }

    private var isLoadingInitial: Bool {
        detailService.isLoading && listing == nil && fallbackItem == nil
    }

    private var isOwnListing: Bool {
        guard let createdById = listing?.createdById,
              let myId = userProfileService.profile?.id else { return false }
        return createdById == myId
    }

    /// While the authoritative listing is still loading there are zero plan
    /// items, so `.full` leaks nothing and we avoid a teaser→full flash for a
    /// non-Pro creator opening their own listing from the feed.
    private var canSeeFullItinerary: Bool {
        listing == nil || storeManager.isPro || isOwnListing
    }

    var body: some View {
        Group {
            if isLoadingInitial {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                detailContent
            }
        }
        .task(id: listingId) {
            AnalyticsClient.shared.track(.PLAN_VIEWED)
            await detailService.fetchListing(id: listingId)
            await acquisitionService.checkAppliedStatus(listingId: listingId)
        }
        .scrollIndicators(.hidden)
        .safeAreaPadding(.horizontal, 16)
        .overlay(alignment: .bottom) {
            bottomOverlayCard
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .background {
            ZStack(alignment: .top) {
                Color(Constants.Background)
                    .ignoresSafeArea()

                topBlurBackground
                    .ignoresSafeArea(.all, edges: .top)
            }
        }
        .background(Constants.Background)
        .navigationDestination(item: $navigateToCreatorId) { creatorId in
            if creatorId == userProfileService.profile?.id {
                MarketProfileOwnerView()
            } else {
                MarketProfileGuestView(creatorId: creatorId)
            }
        }
        .navigationDestination(
            isPresented: Binding(
                get: { selectedPlanItemId != nil },
                set: { if !$0 { selectedPlanItemId = nil } }
            )
        ) {
            if let selectedPlanItem {
                MarketPlanDetailView(
                    planItem: selectedPlanItem,
                    imageUrls: planItemImageUrlsById[selectedPlanItem.id] ?? [],
                    dayLabel: dayLabel(for: selectedPlanItem)
                )
            }
        }
        .onChange(of: acquisitionService.applySuccess) { _, success in
            if success {
                feedService.markAsAcquired(listingId: listingId)
                activeCover = .success
            }
        }
        .fullScreenCover(item: $activeCover) { cover in
            switch cover {
            case .success:
                PurchasedTripSuccessView(
                    listingName: titleText,
                    placesText: activitiesText,
                    durationText: durationText,
                    thumbnailUrl: thumbnailUrl,
                    tripId: tripId,
                    listingId: listingId
                )
            case .paywall:
                WelcomeToMarketView(onClose: { activeCover = nil })
            }
        }
        .toolbar {
            if listing?.status.value1 == .APPROVED {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(
                        item: DeepLinkBuilder.listingURL(id: listingId),
                        subject: Text(titleText),
                        message: Text("Hey, I found this trip plan on OnePlan — check it out.")
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    // ShareLink exposes no tap/completion callback; track the
                    // share intent (sheet opened) via a simultaneous tap gesture.
                    .simultaneousGesture(TapGesture().onEnded {
                        AnalyticsClient.shared.track(
                            .MARKET_SHARED,
                            properties: ["listingId": listingId]
                        )
                    })
                }
            }
        }
    }

    private var detailContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 19) {
                MarketplaceThumbnailImageHolder(
                    thumbnailImageName: "defaultTripPlaceholder",
                    thumbnailUrl: thumbnailUrl
                )

                VStack(spacing: 8) {
                    Text(titleText)
                        .font(Font.custom("Be Vietnam Pro", size: 20))
                        .foregroundStyle(Constants.ContentB)
                        .tracking(-1)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    metadataRow
                    if let caption = lastUpdatedCaption {
                        Text(caption)
                            .font(Font.custom("Be Vietnam Pro", size: 12))
                            .foregroundStyle(Constants.ContentM)
                            .tracking(-0.5)
                    }
                    creatorRow
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            Text(descriptionText)
                .font(Font.custom("Be Vietnam Pro", size: 13.40506))
                .multilineTextAlignment(.center)
                .foregroundColor(Constants.Neutral900)
                .frame(width: 345, alignment: .top)
                .opacity(0.7)
                .padding(.top, 20)

            if let error = detailService.error, listing == nil {
                Text(error)
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundStyle(Constants.ContentM)
                    .padding(.top, 8)
            }

            MarketPlanSection(
                planItems: mappedPlanItems,
                mode: canSeeFullItinerary ? .full : .previewWithDays,
                durationDays: durationDays,
                showEmptyImagePlaceholder: false,
                planItemImageUrlsById: planItemImageUrlsById,
                onPlanTapped: { item in
                    selectedPlanItemId = item.id
                },
                onLockedTapped: { activeCover = .paywall }
            )
            .padding(.top, 20)

            Color.clear
                .frame(height: 104)
        }
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

    private var metadataRow: some View {
        HStack(spacing: 4) {
            HStack(spacing: 2) {
                Image(systemName: "star.fill")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color(red: 1, green: 0.84, blue: 0.2))

                Text(ratingText)
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundStyle(Constants.ContentM)
                    .tracking(-0.6)
            }

            dot

            Text(activitiesText)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundStyle(Constants.ContentM)
                .tracking(-0.6)

            dot

            Text(durationText)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundStyle(Constants.ContentM)
                .tracking(-0.6)
        }
    }

    private var creatorRow: some View {
        Button {
            if let createdById = listing?.createdById {
                navigateToCreatorId = createdById
            }
        } label: {
            HStack(spacing: 5) {
                creatorAvatarView

                Text(creatorName)
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundStyle(Constants.ContentB)
                    .tracking(-0.7)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var creatorAvatarView: some View {
        if let urlString = listing?.creatorAvatarUrl, let url = URL(string: urlString) {
            CachedRemoteImage(
                url: url,
                targetSize: CGSize(width: 24, height: 24)
            ) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Image("avatarPlaceholder")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .frame(width: 24, height: 24)
            .clipShape(Circle())
        } else {
            Image("avatarPlaceholder")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 24, height: 24)
                .clipShape(Circle())
        }
    }

    private var dot: some View {
        Circle()
            .fill(Constants.ContentM)
            .frame(width: 3.8, height: 3.8)
    }

    private var bottomOverlayCard: some View {
        HStack(alignment: .top, spacing: 10) {
            MarketplaceThumbnailImageHolder(
                thumbnailImageName: "defaultTripPlaceholder",
                thumbnailUrl: thumbnailUrl
            )
            .scaleEffect(CGFloat(42.0 / 72.0))
            .frame(width: 42, height: 42)

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(titleText)
                        .font(Font.custom("Be Vietnam Pro", size: 16))
                        .foregroundStyle(Constants.ContentB)
                        .tracking(-0.64)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text("Budget: ~\(budgetPerPersonText)")
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .foregroundStyle(Constants.ContentM)
                        .tracking(-0.6)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !isOwnListing {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        guard storeManager.isPro else {
                            activeCover = .paywall
                            return
                        }
                        if acquisitionService.hasApplied {
                            feedService.markAsAcquired(listingId: listingId)
                            activeCover = .success
                        } else {
                            Task {
                                await acquisitionService.applyForListing(listingId: listingId)
                            }
                        }
                    } label: {
                        Text(acquisitionService.isApplying ? String(localized: "Applying...") : String(localized: "Apply"))
                            .font(Font.custom("Be Vietnam Pro", size: 14))
                            .foregroundStyle(Constants.White)
                            .tracking(-0.7)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 0.28, green: 0.73, blue: 1), Color(red: 0.2, green: 0.64, blue: 1)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(acquisitionService.isApplying)
                    .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 1)
                }
            }
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, minHeight: 42)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .background(Constants.White)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 17.9, x: 0, y: 0)
    }

    private func syntheticPlanDate(dayNumber: Int) -> String {
        let safeOffset = max(dayNumber, 1) - 1
        let calendar = Calendar(identifier: .gregorian)
        let baseDate = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1))
            ?? Date(timeIntervalSince1970: 946684800)
        let date = calendar.date(byAdding: .day, value: safeOffset, to: baseDate) ?? baseDate
        return Self.planDateFormatter.string(from: date)
    }

    private var selectedPlanItem: PlanItemDto? {
        guard let selectedPlanItemId else { return nil }
        return mappedPlanItems.first { $0.id == selectedPlanItemId }
    }

    private func dayLabel(for planItem: PlanItemDto) -> String? {
        guard let planDate = planItem.planDate,
              let date = Self.planDateFormatter.date(from: planDate)
        else { return nil }

        let calendar = Calendar(identifier: .gregorian)
        let baseDate = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1))
            ?? Date(timeIntervalSince1970: 946684800)
        let dayOffset = calendar.dateComponents([.day], from: baseDate, to: date).day ?? 0
        return String(localized: "Day \(max(dayOffset + 1, 1))")
    }

    private func formatBudgetPerPerson(_ rawPrice: String) -> String {
        let symbol = listingCurrency.symbol
        let amount = NSDecimalNumber(string: rawPrice)
        guard amount != .notANumber else {
            return "\(rawPrice)\(symbol)/person"
        }

        let whole = CurrencyFormatter.formatWhole(amount.doubleValue)
        return "\(whole)\(symbol)/person"
    }

    private static let planDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

#Preview {
    MarketItemDetailView(
        listingId: 1,
        fallbackItem: RecommendedMarketplaceItem(
            creatorName: "Vivian solo",
            isCreatorVerified: false,
            title: "Da Lat Trip for Friends",
            priceText: "From 2,500,000đ/person",
            tags: [.FRIENDS],
            listingId: 1
        )
    )
}
