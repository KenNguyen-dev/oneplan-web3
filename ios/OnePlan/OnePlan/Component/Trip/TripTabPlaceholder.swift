//
//  TripTabPlaceholder.swift
//  OnePlan
//
//  Created by Codex on 26/2/26.
//

import SwiftUI

struct TripTabPlaceholder: View {
    let title: String

    var body: some View {
        Text("\(title) content")
            .font(Font.custom("Be Vietnam Pro", size: 14))
            .foregroundColor(Constants.ContentM)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
    }
}

#Preview {
    TripTabPlaceholder(title: "Photo")
        .padding()
}
