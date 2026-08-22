//
//  BoardSummaryRow.swift
//  OnePlan
//
//  Created by Codex on 13/5/26.
//

import SwiftUI

struct BoardSummaryRow: View {
    enum Variant {
        case list
        case picker
        case detail
    }

    let board: BoardSummaryDto
    var coverImageUrl: String?
    var descriptionText: String?
    var locationLabel: String?
    var variant: Variant = .list

    init(
        board: BoardSummaryDto,
        coverImageUrl: String? = nil,
        descriptionText: String? = nil,
        locationLabel: String? = nil,
        variant: Variant = .list
    ) {
        self.board = board
        self.coverImageUrl = coverImageUrl ?? board.coverImageUrl
        self.descriptionText = descriptionText ?? board.description
        self.locationLabel = locationLabel ?? board.locationLabel
        self.variant = variant
    }

    private var primaryLocation: String? {
        guard let label = locationLabel,
              let first = label.split(separator: ",").first
        else { return nil }
        let trimmed = first.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        HStack(alignment: .top, spacing: variant == .picker ? 10 : 8) {
            coverImage

            VStack(alignment: .leading, spacing: variant == .picker ? 10 : 8) {
                textContent

                switch variant {
                case .list:
                    listMetadata
                case .picker:
                    pickerMetadata
                case .detail:
                    detailLocationPill
                }
            }
            .frame(
                maxWidth: .infinity,
                minHeight: variant == .picker ? 120 : nil,
                alignment: variant == .picker ? .center : .topLeading
            )
        }
        .padding(8)
        .background(
            Constants.Surface,
            in: RoundedRectangle(
                cornerRadius: variant == .picker ? 24 : 20,
                style: .continuous
            )
        )
    }

    private var coverImage: some View {
        CachedRemoteImage(
            url: URL(string: coverImageUrl ?? ""),
            targetSize: CGSize(width: 200, height: 240)
        ) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image("boardPlaceholder").resizable().scaledToFill()
        }
        .frame(
            width: variant == .detail ? 92 : 100,
            height: variant == .detail ? 112 : 120
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityHidden(true)
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(board.title)
                .font(.custom("Be Vietnam Pro", size: 18))
                .foregroundStyle(Constants.Neutral950)
                .tracking(variant == .detail ? -0.36 : 0)
                .lineLimit(variant == .list ? 1 : 2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let descriptionText, !descriptionText.isEmpty {
                Text(descriptionText)
                    .font(.custom("Be Vietnam Pro", size: 13))
                    .foregroundStyle(Constants.Neutral950)
                    .tracking(variant == .detail ? -0.65 : 0)
                    .lineLimit(variant == .detail ? 3 : 2)
                    .lineSpacing(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var listMetadata: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image("boardPinIcon")
                    .resizable()
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)

                Text("\(board.pinCount) pins")
                    .font(.custom("Be Vietnam Pro", size: 15))
                    .foregroundStyle(Constants.Neutral700)
                    .lineLimit(1)
            }

            if let primaryLocation {
                Rectangle()
                    .fill(Constants.Neutral100)
                    .frame(width: 1, height: 22)
                    .padding(.horizontal, 10)

                HStack(spacing: 6) {
                    Image("boardCompassIcon")
                        .resizable()
                        .renderingMode(.original)
                        .frame(width: 16, height: 16)
                        .accessibilityHidden(true)

                    Text(primaryLocation)
                        .font(.custom("Be Vietnam Pro", size: 15))
                        .foregroundStyle(Constants.Neutral700)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.85)
                }
            }
        }
        .padding(12)
        .frame(height: 46)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Constants.Neutral50,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private var pickerMetadata: some View {
        HStack(spacing: 12) {
            metadataItem(iconName: "boardPinIcon", title: "\(board.pinCount) pin")

            Divider()
                .frame(height: 22)
                .overlay(Constants.Neutral100)

            metadataItem(iconName: "boardCompassIcon", title: primaryLocation ?? "")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(height: 46)
        .frame(maxWidth: .infinity)
        .background(
            Constants.Neutral50,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    @ViewBuilder
    private var detailLocationPill: some View {
        if let locationLabel, !locationLabel.isEmpty {
            HStack(spacing: 4) {
                Image("boardCompassIcon")
                    .resizable()
                    .renderingMode(.original)
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)

                Text(locationLabel)
                    .font(.custom("Be Vietnam Pro", size: 15))
                    .foregroundStyle(Constants.Neutral700)
                    .tracking(-0.3)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Constants.Neutral50,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
    }

    private func metadataItem(iconName: String, title: String) -> some View {
        HStack(spacing: 4) {
            Image(iconName)
                .resizable()
                .renderingMode(.original)
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)

            Text(title)
                .font(.custom("Be Vietnam Pro", size: 15))
                .foregroundStyle(Constants.textSoft400)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
