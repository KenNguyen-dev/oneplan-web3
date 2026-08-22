
//
//  PrimaryButton.swift
//  OnePlan
//
//  Created by ken on 24/2/26.
//

import SwiftUI

struct UpgradeProButton: View {
    var action: () -> Void = {}

    private let cornerRadius: CGFloat = 31

    var body: some View {
        Button(action: action) {
            Text("Upgrade to Pro")
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .multilineTextAlignment(.center)
                .foregroundColor(Constants.White)
                .frame(maxWidth: .infinity, minHeight: 46, alignment: .center)
                .background(
                    buttonBackground
                )
                .shadow(
                    color: Color(red: 0.584, green: 0.82, blue: 1).opacity(0.25),
                    radius: 11.4 / 2,
                    x: 0,
                    y: 13
                )
                .shadow(
                    color: Color(red: 0.392, green: 0.573, blue: 1).opacity(0.39),
                    radius: 6.1 / 2,
                    x: 0,
                    y: 3
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .inset(by: 0.75)
                        .stroke(Constants.White, lineWidth: 1.5)
                )
                .overlay(innerShadowOverlay)
        }
        .buttonStyle(.plain)
    }

    private var buttonBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            Gradient.Stop(
                                color: Color(red: 0.278, green: 0.424, blue: 1).opacity(
                                    0.5
                                ),
                                location: 0
                            ),
                            Gradient.Stop(
                                color: Color(red: 0, green: 0.314, blue: 0.851),
                                location: 1
                            ),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var innerShadowOverlay: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return ZStack {
            shape
                .stroke(Color(red: 0.302, green: 0.804, blue: 1), lineWidth: 2)
                .blur(radius: 7)
                .offset(y: -4)
                .mask(shape)

            shape
                .stroke(Constants.White, lineWidth: 2)
                .blur(radius: 4.45)
                .offset(x: -3, y: -3)
                .mask(shape)
        }
    }
}

#Preview {
    UpgradeProButton()
}
