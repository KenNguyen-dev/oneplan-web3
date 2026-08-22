//
//  PlanningImageHolder.swift
//  OnePlan
//
//  Created by ken on 25/2/26.
//

import SwiftUI

struct FriendImageHolder: View {
    let name: String
    let imageName: String

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 69, height: 89)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(4)
                .background(Constants.Neutral100)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Constants.Neutral200, lineWidth: 2)
                )

            Text(name)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .multilineTextAlignment(.center)
                .foregroundColor(Constants.ContentB)
                .lineLimit(1)
        }
    }
}

#Preview {
    FriendImageHolder(name: "Carlos", imageName: "defaultTripPlaceholder")
}
