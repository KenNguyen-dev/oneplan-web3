//
//  EmptyHome.swift
//  OnePlan
//
//  Created by Codex on 27/3/26.
//

import SwiftUI

struct EmptyHome: View {
    var onStartNewTripTapped: () -> Void = {}

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 14) {
                Image("emptyHome")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 191.64, height: 191.64)

                Text("No trip planned.\nPlan new trip now with friends")
                    .font(Font.custom("Be Vietnam Pro", size: 16))
                    .foregroundStyle(Constants.ContentM)
                    .multilineTextAlignment(.center)
                    .tracking(-0.64)
            }
            .frame(maxWidth: .infinity)

            PrimaryButton(title: "Start new trip", action: onStartNewTripTapped)
                .frame(width: 220)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    AppScreenContainer {
        EmptyHome()
            .padding(.horizontal, 16)
    }
}
