import SwiftUI

private struct EndedTripDetailDestinationView: View {
    let tripId: Int
    @State private var tripDetailService = TripDetailService()

    var body: some View {
        TripEndView(
            service: tripDetailService,
            tripId: tripId,
            entryMode: .endedList
        )
    }
}

struct EndedTripView: View {
    let trips: [TripSummaryDto]

    private let endedColumns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ended")
                .font(
                    Font.beVietnamPro(16, weight: .medium)
                )
                .foregroundColor(Constants.ContentM)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            LazyVGrid(columns: endedColumns, spacing: 10) {
                ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
                    NavigationLink {
                        EndedTripDetailDestinationView(tripId: Int(trip.id))
                    } label: {
                        PlanningDestinationCard(
                            trip: trip,
                            rotation: index.isMultiple(of: 2)
                                ? .degrees(-1.2)
                                : .degrees(1.2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
