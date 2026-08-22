//
//  OfflineBanner.swift
//  OnePlan
//
//  Subtle banner shown when the ongoing trip is being served from the offline
//  cache (no connectivity). Read-only context — see TripDetailView gating.
//

import SwiftUI

struct OfflineBanner: View {
    /// When the displayed data was last cached. Drives the "updated …" suffix.
    var cachedAt: Date?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Constants.Warning500)

            Text(message)
                .font(Font.beVietnamPro(12, weight: .medium))
                .foregroundStyle(Constants.Black)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Constants.Warning500.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }

    private var message: String {
        guard let cachedAt else {
            return String(localized: "Offline")
        }
        let relative = cachedAt.formatted(.relative(presentation: .named))
        return String(
            localized: "Offline · updated \(relative)",
            comment: "Offline banner; the placeholder is a relative time like \"2 hours ago\""
        )
    }
}

#Preview {
    VStack(spacing: 12) {
        OfflineBanner(cachedAt: Date().addingTimeInterval(-3600))
        OfflineBanner(cachedAt: nil)
    }
    .padding()
}
