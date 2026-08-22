//
//  RatingTripBottomSheet.swift
//  OnePlan
//
//  Created by ken on 7/4/26.
//

import SwiftUI

struct RatingTripBottomSheet: View {
    @Environment(\.dismiss) private var dismiss

    let listingName: String
    let placesText: String
    let durationText: String

    var thumbnailUrl: String? = nil
    var onClose: () -> Void = {}
    var onContinue: (_ rating: Int) -> Void = { _ in }

    @State private var selectedRating = 0

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            VStack(spacing: 24) {
                tripSummary
                ratingSection
            }
            .padding(.top, 9)
            .padding(.horizontal, 16)

            Spacer(minLength: 16)

            PrimaryButton(title: "Continue") {
                onContinue(selectedRating)
                dismiss()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(500)])
        .presentationDragIndicator(.visible)
    }

    private var toolbar: some View {
        HStack {
            Spacer()

            Button {
                onClose()
                dismiss()
            } label: {
                ZStack {
                    Circle()
                        .fill(Constants.OnSurface)
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Constants.ContentM)
                }
                .frame(width: 43, height: 43)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private var tripSummary: some View {
        VStack(alignment: .center, spacing: 19) {
            MarketplaceThumbnailImageHolder(
                thumbnailImageName: "defaultTripPlaceholder",
                thumbnailUrl: thumbnailUrl,
                size: 120
            )

            VStack(alignment: .center, spacing: 8) {
                Text(listingName)
                    .font(Font.custom("Be Vietnam Pro", size: 20))
                    .foregroundColor(Constants.ContentB)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack(alignment: .center, spacing: 4) {
                    Text(placesText)
                        .font(Font.custom("Be Vietnam Pro", size: 12))
                        .foregroundColor(Constants.ContentM)

                    Circle()
                        .fill(Constants.ContentM)
                        .frame(width: 3.8, height: 3.8)
                        .accessibilityHidden(true)

                    Text(durationText)
                        .font(Font.custom("Be Vietnam Pro", size: 12))
                        .foregroundColor(Constants.ContentM)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(width: 195)
    }

    private var ratingSection: some View {
        VStack(spacing: 16) {
            Text("Rate your experience with this Plan")
                .font(Font.custom("Be Vietnam Pro", size: 15))
                .foregroundColor(Constants.ContentB)
                .multilineTextAlignment(.center)
                .tracking(-0.75)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        selectedRating = value
                    } label: {
                        Image(systemName: "star.fill")
                            .font(.system(size: 37))
                            .foregroundStyle(
                                value <= selectedRating
                                    ? Color(red: 1, green: 0.76, blue: 0.21)
                                    : Constants.Neutral200
                            )
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            RatingTripBottomSheet(
                listingName: "Da Lat Trip for Friends",
                placesText: "21 places",
                durationText: "3 days"
            )
        }
}
