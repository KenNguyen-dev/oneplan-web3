//
//  HomeSectionHeader.swift
//  OnePlan
//
//  Created by ken on 3/7/26.
//

import SwiftUI

// Section header used across the redesigned Home: "Ongoing", "Quick access",
// "Popular plans", "Your Boards". Optional trailing "See all" action.
struct HomeSectionHeader: View {
    let title: LocalizedStringKey
    var onSeeAll: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.beVietnamPro(16, weight: .medium))
                .foregroundStyle(Constants.ContentM)
                .tracking(-0.32)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let onSeeAll {
                Button(action: onSeeAll) {
                    Text("See all")
                        .font(.beVietnamPro(14))
                        .foregroundStyle(Constants.ContentM)
                        .tracking(-0.28)
                        .lineLimit(1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
