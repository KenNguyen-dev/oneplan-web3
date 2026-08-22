//
//  MarketplaceDestinationStrip.swift
//  OnePlan
//
//  Created by Codex on 26/3/26.
//

import SwiftUI

struct MarketplaceDestinationStrip: View {
    let destinationNames: [String]
    var thumbnailImageName: String = "defaultTripPlaceholder"

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(destinationNames, id: \.self) { destination in
                    VStack(spacing: 4) {
                        Image(thumbnailImageName)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .background(Constants.Neutral100)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        Text(destination)
                            .font(Font.custom("Be Vietnam Pro", size: 14))
                            .foregroundStyle(Constants.Neutral700)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(width: 80, alignment: .center)
                    }
                }
            }
        }
    }
}

#Preview {
    MarketplaceDestinationStrip(
        destinationNames: ["Ha Noi", "Bangkok", "Da Nang", "Beijing", "New York"]
    )
}
