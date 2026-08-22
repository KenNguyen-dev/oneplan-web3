import SwiftUI

struct LocationDetailHeaderSection: View {
    let title: String
    let address: String
    var openingHours: String? = nil
    var descriptionText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(
                    Font.beVietnamPro(24, weight: .medium)
                )
                .foregroundColor(Constants.ContentB)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            HStack(alignment: .top, spacing: 4) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Constants.ContentM)
                    .frame(width: 20, height: 20)

                Text(address)
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundColor(Constants.ContentM)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            .padding(.top, 5)

            if let openingHours {
                HStack(alignment: .center, spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Constants.ContentM)
                        .frame(width: 20, height: 20)

                    Text(openingHours)
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .foregroundColor(Constants.ContentM)
                }
                .padding(.top, 8)
            }

            if let descriptionText {
                Text(descriptionText)
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundStyle(Constants.ContentM)
                    .tracking(-0.7)
                    .padding(.top, 20)
            }
        }
    }
}

#Preview("LocationDetailHeaderSection") {
    LocationDetailHeaderSection(
        title: "Hotpot",
        address: "251 Nguyen Van Troi, P12, Da Lat City",
        openingHours: "Open until 10:00 PM",
        descriptionText: "This place combines casual dining with warm local service."
    )
    .padding(16)
    .background(Constants.Surface)
}
