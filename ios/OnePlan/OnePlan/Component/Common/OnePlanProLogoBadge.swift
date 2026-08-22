//
//  OnePlanProLogoBadge.swift
//  OnePlan
//

import SwiftUI

struct OnePlanProLogoBadge: View {
    var size: CGFloat = 32
    var showsShadow: Bool = true
    var imageName: String = "onePlanPro"

    private var outerCornerRadius: CGFloat { size * (10 / 32) }
    private var innerCornerRadius: CGFloat { size * (7 / 32) }
    private var innerPadding: CGFloat { size * (3 / 32) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
                .fill(Constants.White)

            RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                .fill(Constants.Black)
                .padding(innerPadding)

            Image(imageName)
                .resizable()
                .scaledToFit()
                .padding(innerPadding)
        }
        .frame(width: size, height: size)
        .modifier(OnePlanProLogoBadgeShadowModifier(enabled: showsShadow, size: size))
    }
}

private struct OnePlanProLogoBadgeShadowModifier: ViewModifier {
    let enabled: Bool
    let size: CGFloat

    func body(content: Content) -> some View {
        if enabled {
            content.shadow(
                color: .black.opacity(0.34),
                radius: size * (4.5 / 32),
                x: size * (-0.7 / 32),
                y: size * (2.8 / 32)
            )
        } else {
            content
        }
    }
}
