//
//  DismissButton.swift
//  OnePlan
//

import SwiftUI

struct DismissButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color(red: 0.925, green: 0.925, blue: 0.925), location: 0),
                                .init(color: Color(red: 0.7, green: 0.7, blue: 0.7), location: 0.745),
                                .init(color: Color(red: 0.922, green: 0.922, blue: 0.922), location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Circle()
                    .fill(Constants.White.opacity(0.85))
                    .frame(width: 43.658, height: 16.346)
                    .blur(radius: 2.3)
                    .offset(y: -18)
                    .blendMode(.plusLighter)

                Image(systemName: "xmark")
                    .font(.system(size: 17.8, weight: .light))
                    .foregroundStyle(Constants.ContentB.opacity(0.85))
            }
            .frame(width: 52, height: 52)
            .overlay {
                Circle()
                    .stroke(Constants.White, lineWidth: 1.5)
            }
            .shadow(
                color: Color(red: 0.588, green: 0.588, blue: 0.588).opacity(0.25),
                radius: 5.7,
                x: 0,
                y: 13
            )
            .shadow(
                color: Color(red: 0.765, green: 0.765, blue: 0.765).opacity(0.39),
                radius: 3.05,
                x: 0,
                y: 3
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss")
    }
}
