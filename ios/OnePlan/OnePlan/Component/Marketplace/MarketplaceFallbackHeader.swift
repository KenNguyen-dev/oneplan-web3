//
//  MarketplaceFallbackHeader.swift
//  OnePlan
//

import SwiftUI

struct MarketplaceFallbackHeader: View {
    let originalName: String

    var body: some View {
        Text("No trips found in \(originalName)")
            .font(Font.custom("Be Vietnam Pro", size: 13))
            .foregroundStyle(Constants.ContentM)
            .tracking(-0.65)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    MarketplaceFallbackHeader(originalName: "Paris")
        .padding()
        .background(Constants.Background)
}
