import SwiftUI

/// One personal-wallet movement in the detail history list (Figma 4245:15020).
struct OnePlanWalletHistoryEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        case withdraw
        case deposit
    }

    let id: String
    let kind: Kind
    /// Counterparty address (Solana base58), shown truncated.
    let address: String
    /// Absolute USDC amount (sign comes from `kind`).
    let amountUsdc: Double
    let time: String
}

struct OnePlanWalletHistoryRow: View {
    let entry: OnePlanWalletHistoryEntry

    var body: some View {
        HStack(spacing: 6) {
            Image(entry.kind == .withdraw ? "walletHistoryWithdraw" : "walletHistoryDeposit")
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .frame(width: 40, height: 40)
                .background(Constants.OnSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.kind == .withdraw
                     ? String(localized: "Withdraw USDC")
                     : String(localized: "Deposit USDC"))
                    .font(Font.beVietnamPro(16))
                    .tracking(-0.64)
                    .foregroundStyle(Constants.ContentB)
                    .lineLimit(1)

                Text(truncatedAddress(entry.address))
                    .font(Font.beVietnamPro(14))
                    .tracking(-0.28)
                    .foregroundStyle(Constants.ContentM)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 3) {
                Text(amountText)
                    .font(Font.beVietnamPro(16))
                    .tracking(-0.32)
                    .foregroundStyle(
                        entry.kind == .withdraw ? Constants.Warning500 : Constants.ContentB
                    )
                    .lineLimit(1)

                Text(entry.time)
                    .font(Font.beVietnamPro(14))
                    .tracking(-0.28)
                    .foregroundStyle(Constants.ContentM)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    private var amountText: String {
        let value: String
        if entry.amountUsdc == floor(entry.amountUsdc) {
            value = String(format: "%.0f", entry.amountUsdc)
        } else {
            value = String(format: "%.2f", entry.amountUsdc)
        }
        return entry.kind == .withdraw ? "-$\(value)" : "+$\(value)"
    }

    private func truncatedAddress(_ address: String) -> String {
        guard address.count > 8 else { return address }
        return "\(address.prefix(4))...\(address.suffix(4))"
    }
}

#Preview {
    VStack(spacing: 0) {
        OnePlanWalletHistoryRow(
            entry: .init(
                id: "1",
                kind: .withdraw,
                address: "D3ade7xyzabcdefghijklmnop",
                amountUsdc: 20,
                time: "08:20"
            )
        )
        Divider()
        OnePlanWalletHistoryRow(
            entry: .init(
                id: "2",
                kind: .deposit,
                address: "D3ade7xyzabcdefghijklmnop",
                amountUsdc: 100,
                time: "08:10"
            )
        )
    }
    .padding(4)
    .background(Constants.Neutral50, in: RoundedRectangle(cornerRadius: 24))
    .padding()
}
