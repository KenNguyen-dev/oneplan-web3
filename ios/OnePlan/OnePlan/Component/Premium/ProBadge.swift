//
//  ProBadge.swift
//  OnePlan
//

import SwiftUI

/// A pill-shaped badge indicating Pro subscription status.
struct ProBadge: View {
    var body: some View {
        Text("Pro")
            .font(Font.custom("Be Vietnam Pro", size: 13))
            .tracking(-0.52)
            .foregroundStyle(Constants.BlueBase)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Constants.BlueBase, lineWidth: 1)
            }
    }
}

#Preview {
    ProBadge()
}
