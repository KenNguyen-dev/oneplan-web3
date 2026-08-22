//
//  MarketProfileOwnerView.swift
//  OnePlan
//
//  Created by ken on 22/3/26.
//

import SwiftUI

struct MarketProfileOwnerView: View {
    @Environment(UserProfileService.self) private var userProfileService
    @State private var myListingsService = MyListingsService()
    @State private var editingListingId: Int?

    private let staticListings: [OwnedListingItem]?

    init() {
        self.staticListings = nil
    }

    init(listings: [OwnedListingItem]) {
        self.staticListings = listings
    }

    fileprivate static let previewListings: [OwnedListingItem] = [
        OwnedListingItem(
            listingId: 1,
            appliedText: "1,253",
            appliedCount: 1253,
            title: "Da Lat Trip for Friends",
            averageRating: nil,
            ratingCount: 0,
            priceText: "From 2,500,000đ/person",
            tags: [.FRIENDS],
            thumbnailUrl: nil,
            durationDays: 3,
            activityCount: 21,
            status: .APPROVED
        ),
        OwnedListingItem(
            listingId: 2,
            appliedText: "855",
            appliedCount: 855,
            title: "Da Lat Budget Trip for Couples",
            averageRating: nil,
            ratingCount: 0,
            priceText: "From 2,000,000đ/person",
            tags: [.COUPLES],
            thumbnailUrl: nil,
            durationDays: 3,
            activityCount: 12,
            status: .PENDING_REVIEW
        ),
        OwnedListingItem(
            listingId: 3,
            appliedText: "37",
            appliedCount: 37,
            title: "Đi ngay đi, rẻ lắm lun ròiiii",
            averageRating: nil,
            ratingCount: 0,
            priceText: "From 2,000,000đ/person",
            tags: [.COUPLES],
            thumbnailUrl: nil,
            durationDays: 3,
            activityCount: 8,
            status: .REJECTED
        ),
    ]

    private var listings: [OwnedListingItem] {
        staticListings ?? myListingsService.listings
    }

    private var isLoadingInitial: Bool {
        guard staticListings == nil else { return false }
        return myListingsService.isLoading && myListingsService.listings.isEmpty
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .center, spacing: 24) {
                MarketProfileHeader(
                    displayName: userProfileService.profile?.displayName
                        ?? "One Plan User",
                    appliedText: profileAppliedText,
                    memberSinceText: memberSinceText,
                    isVerified: false,
                    avatarImageURL: profileAvatarURL
                )

                if isLoadingInitial {
                    ProgressView()
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .center
                        )
                        .padding(.top, 40)
                } else if listings.isEmpty {
                    emptyState
                } else {
                    uploadedPlansSection
                }
            }
        }
        .task {
            guard staticListings == nil else { return }
            await myListingsService.loadMyListings()
        }
        .scrollIndicators(.hidden)
        .safeAreaPadding(.horizontal, 16)
        .onReceive(NotificationCenter.default.publisher(for: .listingUpdated)) { notification in
            guard staticListings == nil else { return }
            if let info = notification.object as? ListingUpdateInfo {
                myListingsService.applyUpdate(info)
            } else {
                Task { await myListingsService.loadMyListings(force: true) }
            }
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
        .navigationDestination(item: $editingListingId) { listingId in
            UploadTripView(listingId: listingId)
        }
    }

    private var profileAvatarURL: URL? {
        guard let urlString = userProfileService.profile?.avatarUrl else {
            return nil
        }
        return URL(string: urlString)
    }

    private var profileAppliedText: String {
        guard !listings.isEmpty else { return "-- Applied" }
        let total = listings.reduce(0) { $0 + $1.appliedCount }
        return MyListingsService.formatAppliedSummaryText(total)
    }

    private var memberSinceText: String {
        guard let iso = userProfileService.profile?.createdAt else {
            return String(localized: "Member")
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: iso) else { return String(localized: "Member") }
        return String(localized: "Member since \(DisplayFormatters.monthYear(date))", comment: "%@ = month and year")
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

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No uploaded plans yet")
                .font(Font.custom("Be Vietnam Pro", size: 16))
                .foregroundStyle(Constants.ContentM)
                .tracking(-0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func activityText(for item: OwnedListingItem) -> String {
        let count = max(item.activityCount, 0)
        return String(localized: "\(count) activities")
    }

    private func durationText(for item: OwnedListingItem) -> String {
        let days = max(item.durationDays, 1)
        return String(localized: "\(days) days")
    }

    private var uploadedPlansSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Uploaded plans")
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundStyle(Constants.ContentM)
                .tracking(-0.7)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                ForEach(listings) { item in
                    MarketplaceItem(
                        mode: .edit,
                        appliedText: item.appliedText,
                        title: item.title,
                        averageRating: item.averageRating,
                        ratingCount: item.ratingCount,
                        activitiesText: activityText(for: item),
                        durationText: durationText(for: item),
                        priceText: item.priceText,
                        tags: item.tags,
                        thumbnailUrl: item.thumbnailUrl,
                        listingStatus: item.status,
                        onEditTap: {
                            editingListingId = item.listingId
                        }
                    )
                }
            }
        }
    }
}

#Preview {
    MarketProfileOwnerView(
        listings: MarketProfileOwnerView.previewListings
    )
    .environment(UserProfileService())
}
