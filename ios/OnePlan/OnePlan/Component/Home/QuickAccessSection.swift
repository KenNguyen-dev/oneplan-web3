//
//  QuickAccessSection.swift
//  OnePlan
//
//  Created by ken on 3/7/26.
//
//  "Quick access" section on Home (Figma 3823:11776): two side-by-side cards
//  — "Create new trip" and "Passport", each with a black capsule button.
//

import SwiftUI

struct QuickAccessSection: View {
    let onNewTripTapped: () -> Void
    let onPassportTapped: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HomeSectionHeader(title: "Quick access")

            HStack(alignment: .top, spacing: 8) {
                createTripCard
                passportCard
            }
        }
    }

    // MARK: - Create new trip

    private var createTripCard: some View {
        QuickAccessCard(
            title: "Create new trip",
            subtitle: "Let’s create your next trip with friends",
            buttonTitle: "New trip",
            action: onNewTripTapped
        ) {
            Image("homeTripMap")
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
        }
    }

    // MARK: - Passport

    private var passportCard: some View {
        QuickAccessCard(
            title: "Passport",
            subtitle: "Record every journey you've undertaken.",
            buttonTitle: "See more",
            action: onPassportTapped
        ) {
            Image("homePassport")
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
        }
    }
}

// One quick-access card: illustration, title, subtitle, full-width capsule
// button. Generic over the illustration view so both cards share the shell.
private struct QuickAccessCard<Illustration: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let buttonTitle: LocalizedStringKey
    let action: () -> Void
    @ViewBuilder let illustration: Illustration

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                illustration
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.beVietnamPro(16))
                        .tracking(-0.64)
                        .foregroundStyle(Constants.Neutral950)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.beVietnamPro(13))
                        .tracking(-0.65)
                        .foregroundStyle(Constants.Neutral600)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            Button(action: action) {
                Text(buttonTitle)
                    .font(.beVietnamPro(14))
                    .tracking(-0.28)
                    .foregroundStyle(Constants.White)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Constants.Black, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Constants.Surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 0)
    }
}

#Preview {
    ZStack {
        Constants.Background.ignoresSafeArea()
        QuickAccessSection(onNewTripTapped: {}, onPassportTapped: {})
            .padding(16)
    }
}
