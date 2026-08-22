//
//  AddingPinToTripBottomSheet.swift
//  OnePlan
//
//  Created by ken on 11/5/26.
//

import SwiftUI

struct AddingPinTripOption: Identifiable, Equatable {
    let id: String
    let title: String
    let status: String
    let imageName: String

    init(
        id: String? = nil,
        title: String,
        status: String,
        imageName: String
    ) {
        self.id = id ?? title
        self.title = title
        self.status = status
        self.imageName = imageName
    }
}

struct AddingPinToTripBottomSheet: View {
    @Environment(\.dismiss) private var dismiss

    let trips: [AddingPinTripOption]
    var onSelectTrip: (AddingPinTripOption) -> Void
    // When set, a "New Trip" footer button appears; the host decides what
    // creating a new trip means (ProcessPinView opens GenerateTripBottomSheet).
    var onNewTrip: (() -> Void)?

    init(
        trips: [AddingPinTripOption] = Self.previewTrips,
        onSelectTrip: @escaping (AddingPinTripOption) -> Void = { _ in },
        onNewTrip: (() -> Void)? = nil
    ) {
        self.trips = trips
        self.onSelectTrip = onSelectTrip
        self.onNewTrip = onNewTrip
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 20) {
                header
                tripSection
            }
            .padding(.horizontal, 14)
            .padding(.top, 24)

            Spacer(minLength: 0)

            if let onNewTrip {
                PrimaryButton(title: "New Trip", action: onNewTrip)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Constants.Neutral50)
        .presentationDetents([.height(749)])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Adding to trip")
                .font(.custom("Be Vietnam Pro", size: 20))
                .foregroundStyle(Constants.Neutral950)
                .tracking(-0.8)
                .lineLimit(1)

            Text("Please select a trip to apply to.")
                .font(.custom("Be Vietnam Pro", size: 13))
                .foregroundStyle(Constants.Neutral950)
                .tracking(-0.65)
                .lineLimit(1)
        }
        .multilineTextAlignment(.center)
        .frame(width: 319)
    }

    private var tripSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your trips")
                .font(.beVietnamPro(16, weight: .medium))
                .foregroundStyle(Constants.ContentM)
                .tracking(-0.32)
                .lineLimit(1)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 150, maximum: 170), spacing: 24, alignment: .top),
                    GridItem(.flexible(minimum: 150, maximum: 170), spacing: 0, alignment: .top)
                ],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(trips) { trip in
                    Button {
                        onSelectTrip(trip)
                    } label: {
                        AddingPinTripCard(trip: trip)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(trip.title), \(trip.status)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static let previewTrips = [
        AddingPinTripOption(
            title: "Singapore (Oct 8-12)",
            status: "Ongoing",
            imageName: "addingPinSingapore"
        ),
        AddingPinTripOption(
            title: "United Kingdom",
            status: "Planning",
            imageName: "addingPinUnitedKingdom"
        ),
        AddingPinTripOption(
            title: "Beijing, China",
            status: "Planning",
            imageName: "addingPinBeijing"
        )
    ]
}

private struct AddingPinTripCard: View {
    let trip: AddingPinTripOption

    var body: some View {
        GeometryReader { proxy in
            let cardWidth = min(proxy.size.width, 170)

            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    Image(trip.imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: cardWidth, height: cardWidth)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Constants.Neutral100, lineWidth: 3)
                        }

                    Text(trip.status)
                        .font(.beVietnamPro(12, weight: .medium))
                        .foregroundStyle(Constants.Neutral700)
                        .tracking(-0.24)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Constants.Neutral100, in: Capsule())
                        .padding(5)
                }
                .frame(width: cardWidth, height: cardWidth)

                HStack(spacing: 3) {
                    Image("addingPinCompassIcon")
                        .resizable()
                        .renderingMode(.original)
                        .frame(width: 14, height: 14)
                        .accessibilityHidden(true)

                    Text(trip.title)
                        .font(.custom("Be Vietnam Pro", size: 14))
                        .foregroundStyle(Constants.ContentB)
                        .tracking(-0.28)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(width: cardWidth, alignment: .leading)
            }
            .frame(width: cardWidth, alignment: .topLeading)
        }
        .frame(height: 205, alignment: .top)
        .contentShape(Rectangle())
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            AddingPinToTripBottomSheet()
        }
}
