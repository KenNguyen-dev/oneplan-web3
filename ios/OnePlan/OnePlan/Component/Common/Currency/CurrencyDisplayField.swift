//
//  CurrencyDisplayField.swift
//  OnePlan

import SwiftUI

/// Read-only currency amount display with comma formatting.
/// Used by HomeCard to show the balance.
struct CurrencyDisplayField: View {
    let label: LocalizedStringKey
    let amount: Double
    var currency: Currency = .VND
    var showDecimals: Bool = true
    var subtitle: LocalizedStringKey? = nil

    private var shouldShowDecimals: Bool {
        showDecimals && currency.decimalPlaces > 0
    }

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Text(label)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .tracking(-0.28)
                .multilineTextAlignment(.center)
                .foregroundStyle(Constants.ContentB)
                .frame(maxWidth: .infinity, alignment: .top)

            HStack(alignment: .center, spacing: 3) {
                Text(currency.symbol)
                    .font(.system(size: 36, weight: .regular, design: .rounded))
                    .tracking(-0.72)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Constants.ContentB.opacity(0.3))

                Text(CurrencyFormatter.formatWhole(amount))
                    .font(Font.custom("Be Vietnam Pro", size: 36))
                    .tracking(-0.72)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Constants.ContentB)

                if shouldShowDecimals {
                    Text(CurrencyFormatter.formatDecimal(amount))
                        .font(Font.custom("Be Vietnam Pro", size: 36))
                        .tracking(-0.72)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Constants.ContentB.opacity(0.3))
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            if let subtitle {
                Text(subtitle)
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .tracking(-0.28)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Constants.ContentM)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        CurrencyDisplayField(label: "Balance (VND)", amount: 24_500_000.15, currency: .VND)
        CurrencyDisplayField(label: "Balance (USD)", amount: 1_234.56, currency: .USD)
        CurrencyDisplayField(label: "Balance (JPY)", amount: 150_000, currency: .JPY)
    }
}
