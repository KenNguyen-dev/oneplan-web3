//
//  EmptyOffline.swift
//  OnePlan
//
//  Shown on the Home / Trip tabs when the device is offline and there is no
//  ongoing trip cached to display.
//

import SwiftUI

struct EmptyOffline: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Constants.ContentM)

            Text("You're offline\nOnly an ongoing trip can be viewed offline")
                .font(Font.custom("Be Vietnam Pro", size: 16))
                .foregroundStyle(Constants.ContentM)
                .multilineTextAlignment(.center)
                .tracking(-0.64)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    AppScreenContainer {
        EmptyOffline()
            .padding(.horizontal, 16)
    }
}
