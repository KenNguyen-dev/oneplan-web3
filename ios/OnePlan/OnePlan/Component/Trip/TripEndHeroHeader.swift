//
//  TripEndHeroHeader.swift
//  OnePlan
//
//  Created by ken on 25/3/26.
//

import SwiftUI

struct TripEndHeroHeader: View {
    let coverImageUrl: String?
    let totalSpent: Double
    let unsettledPaymentCount: Int
    var currency: Currency = .VND
    var showsSettlementStatus: Bool = true

    private var settlementStatusText: String {
        if unsettledPaymentCount == 0 {
            return String(localized: "Trip ended • All settled up!", comment: "Settlement status when everyone has settled")
        }
        // Pluralized in the String Catalog by the count argument.
        return String(localized: "Trip ended • \(unsettledPaymentCount) people need to settle up", comment: "Settlement status; %lld = number of people who still owe")
    }

    var body: some View {
        VStack(spacing: 0) {
            TripEndPioneerHero(coverImageUrl: coverImageUrl)

            VStack(alignment: .leading, spacing: 8) {
                Text("Total spent")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Constants.ContentB)
                    .frame(maxWidth: .infinity, alignment: .top)

                HStack(alignment: .center, spacing: 3) {
                    Text(currency.symbol)
                        .font(Font.custom("Be Vietnam Pro", size: 36))
                        .multilineTextAlignment(.center)
                        .foregroundColor(Constants.ContentL)

                    Text(CurrencyFormatter.formatWhole(totalSpent))
                        .font(Font.custom("Be Vietnam Pro", size: 36))
                        .multilineTextAlignment(.center)
                        .foregroundColor(Constants.ContentB)

                    if currency.decimalPlaces > 0 {
                        Text(CurrencyFormatter.formatDecimal(totalSpent))
                            .font(Font.custom("Be Vietnam Pro", size: 36))
                            .multilineTextAlignment(.center)
                            .foregroundColor(Constants.ContentL)
                    }
                }
                .padding(0)
                .frame(maxWidth: .infinity, alignment: .center)

                if showsSettlementStatus {
                    Text(settlementStatusText)
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .multilineTextAlignment(.center)
                        .foregroundColor(Constants.Neutral700)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 16)
        }
    }
}

private struct TripEndPioneerHero: View {
    let coverImageUrl: String?
    private let avatarSize: CGFloat = 140
    private let crownSize = CGSize(width: 26, height: 26)

    var body: some View {
        VStack(spacing: -12) {
            PioneerAvatar(size: avatarSize, imageUrl: coverImageUrl)

            Text("Pioneer")
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundStyle(Constants.ContentB)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Constants.White, in: Capsule())
                .rotationEffect(.degrees(-8))
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                .accessibilityLabel("Pioneer")
                .overlay(alignment: .bottomTrailing) {
                    crownBadge
                        .offset(x: 12, y: -16)
                }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
    }

    private var crownBadge: some View {
        ZStack {
            Image("crown")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: crownSize.width, height: crownSize.height)
        }
        .rotationEffect(.degrees(12))
        .accessibilityHidden(true)
    }
}
