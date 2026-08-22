//
//  MarketProfileHeader.swift
//  OnePlan
//
//  Created by ken on 26/3/26.
//

import SwiftUI

struct MarketProfileHeader: View {
    var displayName: String = "Huong Local"
    var appliedText: String = "2K+ Applied"
    var memberSinceText: String = "Member since Mar 2026"
    var isVerified: Bool = true
    var avatarImageURL: URL? = nil
    var avatarImageName: String = "avatarPlaceholder"

    private let avatarSize: CGFloat = 72

    var body: some View {
        VStack(alignment: .center, spacing: 19) {
            avatarView

            VStack(alignment: .center, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Text(displayName)
                        .font(Font.custom("Be Vietnam Pro", size: 20))
                        .foregroundStyle(Constants.ContentB)
                        .lineLimit(1)

                    if isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Constants.BlueBase)
                            .frame(width: 18, height: 18)
                            .accessibilityLabel(Text("Verified"))
                    }
                }

                HStack(alignment: .center, spacing: 4) {
                    Text(appliedText)
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .foregroundStyle(Constants.ContentM)
                        .tracking(-0.6)
                        .lineLimit(1)

                    Circle()
                        .fill(Constants.ContentM)
                        .frame(width: 3.8, height: 3.8)
                        .accessibilityHidden(true)

                    Text(memberSinceText)
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .foregroundStyle(Constants.ContentM)
                        .tracking(-0.6)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private var avatarImage: some View {
        if let avatarImageURL {
            CachedRemoteImage(
                url: avatarImageURL,
                targetSize: CGSize(width: avatarSize, height: avatarSize)
            ) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Image(avatarImageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        } else {
            Image(avatarImageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
    }

    private var avatarView: some View {
        ZStack {
            Constants.Background
            avatarImage
        }
        .frame(width: avatarSize, height: avatarSize)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.black, lineWidth: 2.48)
        )
    }
}

#Preview {
    MarketProfileHeader()
        .padding()
        .background(Constants.Background)
}
