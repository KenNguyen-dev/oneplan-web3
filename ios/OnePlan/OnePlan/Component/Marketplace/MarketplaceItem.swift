//
//  MarketplaceItem.swift
//  OnePlan
//
//  Created by ken on 26/3/26.
//

import SwiftUI

struct RecommendedMarketplaceItem: Identifiable {
    let id: UUID
    let creatorName: String
    let creatorAvatarUrl: String?
    let isCreatorVerified: Bool
    var title: String
    var priceText: String
    var tags: [Components.Schemas.ListingTag]
    let listingId: Int?
    let createdById: Int?
    var thumbnailUrl: String?
    var durationDays: Int?
    var activityCount: Int?
    var appliedCount: Int?
    var isAcquired: Bool
    var averageRating: Double?
    var ratingCount: Int
    var cityName: String?
    var countryName: String?

    init(
        id: UUID = UUID(),
        creatorName: String,
        creatorAvatarUrl: String? = nil,
        isCreatorVerified: Bool,
        title: String,
        priceText: String,
        tags: [Components.Schemas.ListingTag],
        listingId: Int? = nil,
        createdById: Int? = nil,
        thumbnailUrl: String? = nil,
        durationDays: Int? = nil,
        activityCount: Int? = nil,
        appliedCount: Int? = nil,
        isAcquired: Bool = false,
        averageRating: Double? = nil,
        ratingCount: Int = 0,
        cityName: String? = nil,
        countryName: String? = nil
    ) {
        self.id = id
        self.creatorName = creatorName
        self.creatorAvatarUrl = creatorAvatarUrl
        self.isCreatorVerified = isCreatorVerified
        self.title = title
        self.priceText = priceText
        self.tags = tags
        self.listingId = listingId
        self.createdById = createdById
        self.thumbnailUrl = thumbnailUrl
        self.durationDays = durationDays
        self.activityCount = activityCount
        self.appliedCount = appliedCount
        self.isAcquired = isAcquired
        self.averageRating = averageRating
        self.ratingCount = ratingCount
        self.cityName = cityName
        self.countryName = countryName
    }
}

enum MarketplaceRatingFormatter {
    static func formatRatingText(average: Double?, count: Int) -> String {
        guard let avg = average, count > 0 else { return String(localized: "No ratings yet") }
        let avgStr = String(format: "%.1f", avg)
        let countStr: String
        switch count {
        case ..<1000: countStr = String(localized: "\(count) ratings")
        case ..<10_000: countStr = String(localized: "1K+ ratings")
        default: countStr = String(localized: "10K+ ratings")
        }
        return "\(avgStr) · \(countStr)"
    }
}

enum MarketplaceItemMode {
    case view
    case edit
}

/// Small pill rendered next to "Applied N" on the owner card so creators can
/// see at a glance whether their listing is publicly visible.
struct ListingStatusBadge: View {
    let status: Components.Schemas.MarketplaceListingStatus

    var body: some View {
        Text(label)
            .font(Font.custom("Be Vietnam Pro", size: 11))
            .foregroundStyle(foreground)
            .tracking(-0.5)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background)
            .clipShape(Capsule())
    }

    private var label: String {
        switch status {
        case .PENDING_REVIEW: return "Pending review"
        case .APPROVED: return "Approved"
        case .REJECTED: return "Rejected"
        case .DRAFT: return "Draft"
        }
    }

    private var foreground: Color {
        switch status {
        case .PENDING_REVIEW: return Color(red: 0.65, green: 0.45, blue: 0.0)
        case .APPROVED: return Color(red: 0.10, green: 0.55, blue: 0.20)
        case .REJECTED: return Color(red: 0.78, green: 0.15, blue: 0.15)
        case .DRAFT: return .white
        }
    }

    private var background: Color {
        switch status {
        case .PENDING_REVIEW: return Color(red: 1.0, green: 0.94, blue: 0.78)
        case .APPROVED: return Color(red: 0.85, green: 0.95, blue: 0.85)
        case .REJECTED: return Color(red: 1.0, green: 0.88, blue: 0.88)
        case .DRAFT: return Color.secondary
        }
    }
}

struct MarketplaceItem: View {
    var mode: MarketplaceItemMode = .view
    var creatorName: String = "Vivian solo"
    var isCreatorVerified: Bool = true
    var unlockText: String = String(localized: "Unlock & Apply")
    var isAcquired: Bool = false
    var appliedText: String = "1,253"
    var title: String = "Da Lat Trip for Friends"
    var averageRating: Double? = nil
    var ratingCount: Int = 0
    var activitiesText: String = "21 activities"
    var durationText: String = "3 days"
    var priceText: String = "From 2,500,000đ/person"
    var tags: [Components.Schemas.ListingTag] = [.FRIENDS]
    var avatarImageName: String = "avatarPlaceholder"
    var avatarUrl: String? = nil
    var thumbnailImageName: String = "defaultTripPlaceholder"
    var thumbnailUrl: String? = nil
    var listingStatus: Components.Schemas.MarketplaceListingStatus? = nil
    var isOwnListing: Bool = false
    var onEditTap: (() -> Void)?

    private var ratingText: String {
        MarketplaceRatingFormatter.formatRatingText(average: averageRating, count: ratingCount)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            HStack(alignment: .center, spacing: 10) {
                MarketplaceThumbnailImageHolder(
                    thumbnailImageName: thumbnailImageName,
                    thumbnailUrl: thumbnailUrl
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Font.custom("Be Vietnam Pro", size: 17))
                        .foregroundStyle(Constants.ContentB)
                        .tracking(-0.85)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Label {
                            Text(ratingText)
                                .font(Font.custom("Be Vietnam Pro", size: 14))
                                .foregroundStyle(Constants.ContentM)
                                .tracking(-0.6)
                        } icon: {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color(red: 1, green: 0.84, blue: 0.2))
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

                    HStack(spacing: 6) {
                        Text(priceText)
                            .font(Font.custom("Be Vietnam Pro", size: 14))
                            .foregroundStyle(Constants.ContentM)
                            .tracking(-0.6)
                            .lineLimit(1)

                        if let primaryTag = tags.first {
                            ListingTag(tag: primaryTag)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
        .background(Constants.White)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder
    private var header: some View {
        switch mode {
        case .view:
            viewHeader
        case .edit:
            editHeader
        }
    }

    private var viewHeader: some View {
        HStack {
            HStack(spacing: 5) {
                avatarView

                Text(creatorName)
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundStyle(Constants.ContentB)
                    .tracking(-0.7)
                    .lineLimit(1)

                if isCreatorVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Constants.BlueBase)
                }
            }

            Spacer()

            if !isOwnListing {
                Text(unlockText)
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundStyle(isAcquired ? Constants.ContentM : Constants.White)
                    .tracking(-0.7)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        isAcquired
                            ? AnyShapeStyle(Constants.Neutral100)
                            : AnyShapeStyle(
                                LinearGradient(
                                    colors: [Color(red: 0.28, green: 0.73, blue: 1), Color(red: 0.2, green: 0.64, blue: 1)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(isAcquired ? 0 : 0.12), radius: 8, x: 0, y: 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Constants.Neutral50)
                .frame(height: 1)
        }
    }

    private var editHeader: some View {
        HStack {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Text("Applied")
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .foregroundStyle(Constants.ContentL)
                        .tracking(-0.7)
                        .lineLimit(1)

                    Text(appliedText)
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .foregroundStyle(Constants.ContentB)
                        .tracking(-0.7)
                        .lineLimit(1)
                }

                if let listingStatus {
                    ListingStatusBadge(status: listingStatus)
                }
            }

            Spacer()

            Button {
                onEditTap?()
            } label: {
                Text("Edit")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundStyle(Constants.White)
                    .tracking(-0.7)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Constants.Neutral600)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.10), radius: 2, x: 0, y: 0)
                    .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 1)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Constants.Neutral50)
                .frame(height: 1)
        }
    }

    private var dot: some View {
        Circle()
            .fill(Constants.ContentM)
            .frame(width: 3.8, height: 3.8)
    }

    @ViewBuilder
    private var avatarView: some View {
        if let avatarUrl, let url = URL(string: avatarUrl) {
            CachedRemoteImage(
                url: url,
                targetSize: CGSize(width: 24, height: 24)
            ) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Image(avatarImageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .frame(width: 24, height: 24)
            .clipShape(Circle())
        } else {
            Image(avatarImageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 24, height: 24)
                .clipShape(Circle())
        }
    }
}

#Preview {
    MarketplaceItem()
        .padding()
        .background(Constants.Background)
}
