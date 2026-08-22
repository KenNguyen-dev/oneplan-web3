import SwiftUI

struct LocationDetailSummaryStrip: View {
    let distanceText: String?
    let visitorsText: String?
    let visitorsAvatarCount: Int

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Constants.Neutral100)
                .frame(height: 1)

            HStack(spacing: 8) {
                if let distanceText {
                    SummaryPill(
                        iconSystemName: "arrow.left.arrow.right",
                        title: distanceText
                    )
                }

                if let visitorsText {
                    SummaryPill(
                        title: visitorsText,
                        avatarCount: visitorsAvatarCount
                    )
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 4)
        .padding(.bottom, 20)
    }
}

#Preview("LocationDetailSummaryStrip") {
    LocationDetailSummaryStrip(
        distanceText: "395km",
        visitorsText: "1,200+ visited",
        visitorsAvatarCount: 3
    )
    .padding(.vertical, 16)
    .background(Constants.Surface)
}
