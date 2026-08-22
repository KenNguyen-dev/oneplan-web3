//
//  OngoingCard.swift
//  OnePlan
//
//  Created by ken on 25/2/26.
//

import SwiftUI

struct OngoingCard: View {
    private static let avatarSize: CGFloat = 23.84
    private static let avatarStep: CGFloat = 11.22
    private static let avatarOverlapSpacing: CGFloat = avatarStep - avatarSize

    let tripName: String
    let coverImageUrl: String?
    let locationLabel: String?
    let memberAvatarUrls: [String?]
    let onCardTapped: (() -> Void)?
    let onNewExpenseTapped: (() -> Void)?
    @State private var suppressCardTap = false

    init(
        tripName: String = "Dubai, 2025",
        coverImageUrl: String? = nil,
        locationLabel: String? = "Dubai, UAE",
        memberAvatarUrls: [String?] = [],
        onCardTapped: (() -> Void)? = nil,
        onNewExpenseTapped: (() -> Void)? = nil
    ) {
        self.tripName = tripName
        self.coverImageUrl = coverImageUrl
        self.locationLabel = locationLabel
        self.memberAvatarUrls = memberAvatarUrls
        self.onCardTapped = onCardTapped
        self.onNewExpenseTapped = onNewExpenseTapped
    }

    private var displayedAvatarUrls: [String?] {
        let source =
            memberAvatarUrls.isEmpty
            ? [nil, nil, nil]
            : memberAvatarUrls
        return Array(source.prefix(3))
    }

    private var remainingAvatarCount: Int {
        max(memberAvatarUrls.count - 3, 0)
    }

    private var cardContent: some View {
        HStack(alignment: .top) {
            ZStack(alignment: .center) {
                Rectangle()
                    .foregroundColor(.clear)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        Group {
                            if let urlString = coverImageUrl,
                                let url = URL(string: urlString)
                            {
                                CachedRemoteImage(
                                    url: url,
                                    targetSize: CGSize(width: 137, height: 176)
                                ) { image in
                                    image.resizable().aspectRatio(
                                        contentMode: .fill
                                    )
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
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                    )

                if let locationLabel {
                    HStack(alignment: .center, spacing: 10) {
                        Text(locationLabel)
                            .font(Font.custom("Be Vietnam Pro", size: 14))
                            .foregroundColor(Constants.ContentB)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Constants.Neutral100)
                    .cornerRadius(57)
                    .padding(8)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .bottomLeading
                    )
                }
            }
            .frame(width: 137, height: 176)
            .background(Constants.Neutral100)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .inset(by: 1)
                    .stroke(Constants.Neutral200, lineWidth: 2)
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 3) {
                    HStack(spacing: OngoingCard.avatarOverlapSpacing) {
                        ForEach(
                            Array(displayedAvatarUrls.enumerated()),
                            id: \.offset
                        ) { _, avatarUrl in
                            avatarView(urlString: avatarUrl)
                        }
                    }

                    HStack(alignment: .center, spacing: 0) {
                        Image(systemName: "plus")
                            .frame(width: 16, height: 16)
                            .foregroundStyle(Constants.BlueBase)
                    }
                    .frame(
                        width: OngoingCard.avatarSize,
                        height: OngoingCard.avatarSize,
                        alignment: .center
                    )
                    .background(Constants.BlueAlpha10)
                    .cornerRadius(.infinity)
                    .overlay(
                        RoundedRectangle(cornerRadius: 57)
                            .inset(by: 0.5)
                            .stroke(
                                Constants.BlueBase,
                                style: StrokeStyle(lineWidth: 1, dash: [2, 2])
                            )
                    )

                    if remainingAvatarCount > 0 {
                        Text("+\(remainingAvatarCount)")
                            .font(Font.custom("Be Vietnam Pro", size: 14))
                            .foregroundColor(Constants.ContentB)
                            .lineLimit(1)
                    }
                }
                .padding(0)

                // Header
                Text(tripName)
                    .font(Font.custom("Be Vietnam Pro", size: 18))
                    .foregroundColor(Constants.ContentB)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                Spacer()

                NewExpenseButton {
                    suppressCardTap = true
                    onNewExpenseTapped?()
                    DispatchQueue.main.async {
                        suppressCardTap = false
                    }
                }
            }
            .padding(10)
            .frame(width: 210, height: 180, alignment: .topLeading)

        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Constants.Surface)
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.06), radius: 8.95, x: 0, y: 0)
    }

    @ViewBuilder
    var body: some View {
        if let onCardTapped {
            cardContent
                .contentShape(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                )
                .onTapGesture {
                    guard !suppressCardTap else { return }
                    onCardTapped()
                }
        } else {
            cardContent
        }
    }

    @ViewBuilder
    private func avatarView(urlString: String?) -> some View {
        if let urlString, let url = URL(string: urlString) {
            CachedRemoteImage(
                url: url,
                targetSize: CGSize(
                    width: OngoingCard.avatarSize,
                    height: OngoingCard.avatarSize
                )
            ) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Image("avatarPlaceholder")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .frame(
                width: OngoingCard.avatarSize,
                height: OngoingCard.avatarSize
            )
            .clipShape(Circle())
        } else {
            Image("avatarPlaceholder")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(
                    width: OngoingCard.avatarSize,
                    height: OngoingCard.avatarSize
                )
                .clipShape(Circle())
        }
    }
}

#Preview {
    OngoingCard()
}
