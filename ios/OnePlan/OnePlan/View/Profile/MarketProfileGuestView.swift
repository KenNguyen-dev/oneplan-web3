//
//  MarketProfileGuestView.swift
//  OnePlan
//
//  Created by ken on 22/3/26.
//

import SwiftUI

struct MarketProfileGuestView: View {
    let creatorId: Int

    @State private var creatorService = CreatorProfileService()

    private var profile: CreatorProfileDto? {
        creatorService.profile
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .center, spacing: 16) {
                MarketProfileHeader(
                    displayName: profile?.displayName ?? String(localized: "Creator"),
                    appliedText: profileAppliedText,
                    memberSinceText: memberSinceText,
                    isVerified: false,
                    avatarImageURL: avatarURL
                )

                if creatorService.isLoading && profile == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if creatorService.listings.isEmpty {
                    Text("No plans yet")
                        .font(Font.custom("Be Vietnam Pro", size: 16))
                        .foregroundStyle(Constants.ContentM)
                        .tracking(-0.8)
                        .padding(.top, 40)
                } else {
                    listingsSection
                }
            }
        }
        .task {
            await creatorService.fetchCreatorProfile(userId: creatorId)
        }
        .scrollIndicators(.hidden)
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

    private var avatarURL: URL? {
        guard let urlString = profile?.avatarUrl else { return nil }
        return URL(string: urlString)
    }

    private var profileAppliedText: String {
        guard !creatorService.listings.isEmpty else { return "-- Applied" }
        let total = creatorService.listings.reduce(0) { $0 + ($1.appliedCount ?? 0) }
        return MyListingsService.formatAppliedSummaryText(total)
    }

    private var memberSinceText: String {
        guard let iso = profile?.createdAt else { return String(localized: "Member") }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: iso) else { return String(localized: "Member") }
        return String(localized: "Member since \(DisplayFormatters.monthYear(date))", comment: "%@ = month and year")
    }

    private var listingsSection: some View {
        VStack(spacing: 8) {
            ForEach(creatorService.listings) { item in
                let card = MarketplaceItem(
                    creatorName: item.creatorName,
                    isCreatorVerified: item.isCreatorVerified,
                    title: item.title,
                    averageRating: item.averageRating,
                    ratingCount: item.ratingCount,
                    activitiesText: activityText(for: item),
                    durationText: durationText(for: item),
                    priceText: item.priceText,
                    tags: item.tags,
                    avatarUrl: item.creatorAvatarUrl,
                    thumbnailUrl: item.thumbnailUrl
                )

                if let listingId = item.listingId {
                    NavigationLink {
                        MarketItemDetailView(
                            listingId: listingId,
                            fallbackItem: item
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

    private func activityText(for item: RecommendedMarketplaceItem) -> String {
        let count = max(item.activityCount ?? 0, 0)
        return String(localized: "\(count) activities")
    }

    private func durationText(for item: RecommendedMarketplaceItem) -> String {
        let days = max(item.durationDays ?? 1, 1)
        return String(localized: "\(days) days")
    }
}

#Preview {
    MarketProfileGuestView(creatorId: 1)
}
