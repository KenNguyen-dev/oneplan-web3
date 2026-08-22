//
//  QuotaExceededSheet.swift
//  OnePlan
//
//  Presented when the server rejects a pin extraction with HTTP 402 — the
//  user has no scan credits available. Surfaces the structured balance state
//  (available=0, nextProGrantAt) and the buy / upgrade paths.
//

import SwiftUI

struct QuotaExceededSheet: View {
    let error: InsufficientScanCreditsError
    var onBuyCredits: () -> Void
    var onUpgrade: () -> Void
    var onDismiss: () -> Void

    @Environment(\.dismiss) private var systemDismiss

    var body: some View {
        VStack(spacing: 24) {
            Image("outOfQuotaExtraction")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundStyle(.orange)
                .padding(.top, 24)

            VStack(spacing: 8) {
                Text("Out of scan credits")
                    .font(.title2.bold())
                Text(bodyMessage)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
            }

            VStack(spacing: 12) {
                PrimaryButton(title: "Buy scan credits") {
                    onBuyCredits()
                    systemDismiss()
                }

                Button("Upgrade to Pro") {
                    onUpgrade()
                    systemDismiss()
                }
                .font(.system(size: 16))
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(440)])
        .presentationDragIndicator(.visible)
    }

    private var bodyMessage: String {
        if let next = error.nextProGrantAt {
            let when = next.formatted(
                .dateTime.weekday(.wide).month().day()
            )
            return String(
                localized: "You're out of scan credits. Your Pro plan adds more on \(when).",
                comment: "%@ = formatted date of the next Pro credit grant"
            )
        }
        return String(localized: "You're out of scan credits. Buy a pack, or go Pro for a batch of scan credits.")
    }
}
