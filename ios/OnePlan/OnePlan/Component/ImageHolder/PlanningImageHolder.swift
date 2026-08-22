//
//  PlanningImageHolder.swift
//  OnePlan
//
//  Created by ken on 25/2/26.
//

import SwiftUI

struct PlanningImageHolder: View {
    var imageName: String = "defaultTripPlaceholder"
    var imageUrl: String? = nil
    var rotation: Angle = .zero

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Rectangle()
                .foregroundColor(.clear)
                .frame(width: 170, height: 170)
                .background(
                    Group {
                        if let urlString = imageUrl, let url = URL(string: urlString) {
                            CachedRemoteImage(url: url, targetSize: CGSize(width: 170, height: 170)) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Image(imageName)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            }
                        } else {
                            Image(imageName)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                    }
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
                    .clipped()
                )
        }
        .padding(0)
        .frame(height: 170, alignment: .leading)
        .background(.white)
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .inset(by: 1.5)
                .stroke(Constants.Neutral100, lineWidth: 3)
        )
        .rotationEffect(rotation)
    }
}

#Preview {
    PlanningImageHolder(
        rotation: .degrees(1.4)
    )
}
