//
//  EmptyMarket.swift
//  OnePlan
//
//  Created by Codex on 27/3/26.
//

import SwiftUI

struct EmptyMarket: View {
    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            Image("emptyMarket")
                .resizable()
                .scaledToFit()
                .frame(width: 224.277, height: 221.709)

            Text("Almost there!\nWe're bringing amazing trips to you.")
                .font(Font.custom("Be Vietnam Pro", size: 16))
                .foregroundStyle(Constants.ContentM)
                .multilineTextAlignment(.center)
                .tracking(-0.64)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

#Preview {
    AppScreenContainer {
        EmptyMarket()
    }
}
