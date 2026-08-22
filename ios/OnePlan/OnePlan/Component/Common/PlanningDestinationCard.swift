import SwiftUI

struct PlanningDestinationCard: View {
    let trip: TripSummaryDto
    var rotation: Angle = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlanningImageHolder(
                imageUrl: trip.coverImageUrl,
                rotation: rotation
            )
            

            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Constants.ContentB)

                Text(trip.name)
                    .font(
                        Font.beVietnamPro(14, weight: .medium)
                    )
                    .foregroundColor(Constants.ContentB)
                    .lineLimit(1)
            }
        }
    }
}
