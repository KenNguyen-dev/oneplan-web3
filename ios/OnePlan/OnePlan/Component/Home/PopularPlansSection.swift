//
//  PopularPlansSection.swift
//  OnePlan
//
//  Created by ken on 3/7/26.
//
//  "Popular plans" section on Home (Figma 3823:17484): rotated polaroid-style
//  marketplace covers (admin-featured, falling back to trending) in a
//  two-column grid, each captioned with a compass icon + destination.
//  "See all" jumps to the Market tab.
//

import SwiftUI

struct PopularPlansSection: View {
    let items: [RecommendedMarketplaceItem]
    let onItemTapped: (RecommendedMarketplaceItem) -> Void
    let onSeeAll: () -> Void

    // Two-column grid (mirrors TripView's planning grid) so a single listing
    // sits in the leading cell instead of floating centered full-width.
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HomeSectionHeader(title: "Popular plans", onSeeAll: onSeeAll)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    PopularPlanPolaroid(
                        item: item,
                        rotation: index.isMultiple(of: 2) ? -2 : 2,
                        onTapped: { onItemTapped(item) }
                    )
                }
            }
        }
    }
}

private struct PopularPlanPolaroid: View {
    let item: RecommendedMarketplaceItem
    let rotation: Double
    let onTapped: () -> Void

    private var caption: String {
        item.cityName ?? item.countryName ?? item.title
    }

    var body: some View {
        Button(action: onTapped) {
            VStack(spacing: 12) {
                cover
                    .rotationEffect(.degrees(rotation))
                    .padding(.top, 4)

                HStack(spacing: 3) {
                    Image("boardCompassIcon")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(Constants.ContentB)

                    Text(caption)
                        .font(.beVietnamPro(14))
                        .tracking(-0.28)
                        .foregroundStyle(Constants.ContentB)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var cover: some View {
        Group {
            if let urlString = item.thumbnailUrl, let url = URL(string: urlString) {
                CachedRemoteImage(
                    url: url,
                    targetSize: CGSize(width: 170, height: 170)
                ) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image("defaultTripPlaceholder")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            } else {
                Image("defaultTripPlaceholder")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: 170, height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .background(Constants.White)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .inset(by: 1.5)
                .stroke(Constants.Neutral100, lineWidth: 3)
        )
    }
}

#Preview {
    ZStack {
        Constants.Background.ignoresSafeArea()
        PopularPlansSection(
            items: [
                RecommendedMarketplaceItem(
                    creatorName: "Vivian",
                    isCreatorVerified: false,
                    title: "Singapore in 5 days",
                    priceText: "Free",
                    tags: [],
                    listingId: 1,
                    cityName: "Singapore"
                ),
                RecommendedMarketplaceItem(
                    creatorName: "Ken",
                    isCreatorVerified: false,
                    title: "London calling",
                    priceText: "Free",
                    tags: [],
                    listingId: 2,
                    countryName: "United Kingdom"
                ),
            ],
            onItemTapped: { _ in },
            onSeeAll: {}
        )
        .padding(16)
    }
}
