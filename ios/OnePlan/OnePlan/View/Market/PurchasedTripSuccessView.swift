//
//  PurchasedTripSuccessView.swift
//  OnePlan
//
//  Created by ken on 28/3/26.
//

import SwiftUI

struct PurchasedTripSuccessView: View {
    let listingName: String
    let placesText: String
    let durationText: String
    var thumbnailUrl: String? = nil
    var tripId: Int? = nil
    var listingId: Int? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var acquisitionService = MarketplaceAcquisitionService()
    @State private var applyError: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            successContent

            actionButton
        }
        .overlay(alignment: .topTrailing) {
            ToolbarIconButton(systemName: "xmark") {
                dismiss()
            }
        }
        .padding()
        .background(Constants.Background)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .alert(
            "Couldn't apply plan",
            isPresented: Binding(
                get: { applyError != nil },
                set: { if !$0 { applyError = nil } }
            ),
            presenting: applyError
        ) { _ in
            Button("OK", role: .cancel) { applyError = nil }
        } message: { error in
            Text(error)
        }
    }

    private var successContent: some View {
        VStack(alignment: .center, spacing: 24) {
            VStack(alignment: .center, spacing: 12) {
                Text("Your plan is ready")
                    .font(Font.custom("Be Vietnam Pro", size: 32))
                    .tracking(-1.28)
                    .multilineTextAlignment(.center)
                    .foregroundColor(Constants.ContentB)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text("Select a trip and start date to apply this plan.")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .tracking(-0.28)
                    .multilineTextAlignment(.center)
                    .foregroundColor(Constants.ContentB)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .center, spacing: 19) {
                MarketplaceThumbnailImageHolder(
                    thumbnailImageName: "defaultTripPlaceholder",
                    thumbnailUrl: thumbnailUrl,
                    size: 160
                )
                .rotationEffect(.degrees(-10))
                .frame(width: 185.35, height: 185.35)

                VStack(alignment: .center, spacing: 8) {
                    Text(listingName)
                        .font(Font.beVietnamPro(24, weight: .medium))
                        .tracking(-0.48)
                        .foregroundColor(Constants.ContentB)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .center)

                    metadataRow
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.bottom, hasActionButton ? 72 : 0)
    }

    private var metadataRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(placesText)
                .font(Font.custom("Be Vietnam Pro", size: 15))
                .tracking(-0.3)
                .foregroundColor(Constants.Neutral600)
                .lineLimit(1)

            Circle()
                .fill(Constants.Neutral600)
                .frame(width: 3.8, height: 3.8)
                .accessibilityHidden(true)

            Text(durationText)
                .font(Font.custom("Be Vietnam Pro", size: 15))
                .tracking(-0.3)
                .foregroundColor(Constants.Neutral600)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var actionButton: some View {
        if let tripId, let listingId {
            PrimaryButton(
                title: acquisitionService.isApplyingToTrip ? "Applying..." : "Apply to current trip"
            ) {
                Task {
                    await acquisitionService.applyMarketplaceToTrip(
                        tripId: tripId,
                        listingId: listingId
                    )
                    if acquisitionService.applyToTripSuccess {
                        dismiss()
                    } else {
                        applyError = acquisitionService.applyToTripError
                            ?? String(localized: "Couldn't apply this plan to your trip.")
                    }
                }
            }
            .disabled(acquisitionService.isApplyingToTrip)
        } else if let listingId {
            PrimaryButton(
                title: acquisitionService.isCreatingTrip ? "Creating..." : "Create new trip"
            ) {
                Task {
                    await acquisitionService.createTripFromListing(listingId: listingId)
                    if let newTripId = acquisitionService.createdTripId {
                        NotificationCenter.default.post(
                            name: .tripCreated,
                            object: nil,
                            userInfo: ["tripId": newTripId]
                        )
                        dismiss()
                    }
                }
            }
            .disabled(acquisitionService.isCreatingTrip)
        }
    }

    private var hasActionButton: Bool {
        listingId != nil
    }
}

#Preview {
    PurchasedTripSuccessView(
        listingName: "Da Lat Trip for Friends",
        placesText: "21 activities",
        durationText: "3 days"
    )
}
