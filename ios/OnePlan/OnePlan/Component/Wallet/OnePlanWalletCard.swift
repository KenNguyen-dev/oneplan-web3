import SwiftUI

/// Personal OnePlan Wallet summary card (Figma 4245:15486).
struct OnePlanWalletCard: View {
    let email: String
    let balanceUsdc: Double
    var balanceVnd: Double
    var isLoading: Bool = false
    /// Header + balance open the wallet detail; buttons stay separate.
    var onOpenDetail: () -> Void = {}
    var onWithdraw: () -> Void = {}
    var onDeposit: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onOpenDetail) {
                VStack(spacing: 0) {
                    header
                        .padding(16)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Constants.Neutral100)
                                .frame(height: 1)
                        }

                    Spacer(minLength: 12)

                    balanceBlock
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)

                    Spacer(minLength: 12)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens OnePlan Wallet")

            buttons
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 220)
        .background(Constants.White)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 8.95, y: 0)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image("depositOptionWallet")
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .frame(width: 40, height: 40)
                .background(Color(white: 0.74).opacity(0.1), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("OnePlan Wallet")
                    .font(Font.beVietnamPro(14))
                    .tracking(-0.42)
                    .foregroundStyle(Constants.Neutral950.opacity(0.4))

                Text(email.isEmpty ? "—" : email)
                    .font(Font.beVietnamPro(18))
                    .tracking(-0.54)
                    .foregroundStyle(Constants.Neutral950)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var balanceBlock: some View {
        VStack(spacing: 5) {
            if isLoading {
                ProgressView()
                    .controlSize(.regular)
                    .padding(.vertical, 8)
            } else {
                HStack(spacing: 3) {
                    Text("$")
                        .font(Font.beVietnamPro(36))
                        .tracking(-0.72)
                        .foregroundStyle(Constants.ContentL)
                    Text(usdAmountText)
                        .font(Font.beVietnamPro(36))
                        .tracking(-0.72)
                        .foregroundStyle(Constants.ContentB)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)

                Text("\(CurrencyFormatter.formatWhole(balanceVnd)) VND")
                    .font(Font.beVietnamPro(14))
                    .tracking(-0.56)
                    .foregroundStyle(Constants.Neutral600)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Balance \(usdAmountText) USDC, about \(CurrencyFormatter.formatWhole(balanceVnd)) VND"
        )
    }

    private var buttons: some View {
        HStack(spacing: 6) {
            Button(action: onWithdraw) {
                Text("Withdraw")
                    .font(Font.beVietnamPro(15))
                    .tracking(-0.75)
                    .foregroundStyle(Constants.ContentB)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Constants.White)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .inset(by: 0.5)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.07), radius: 12, y: 6)
                    .shadow(
                        color: Color(red: 0.8, green: 0.86, blue: 0.94).opacity(0.35),
                        radius: 18,
                        y: 10
                    )
            }
            .buttonStyle(.plain)

            Button(action: onDeposit) {
                Text("Deposit")
                    .font(Font.beVietnamPro(15))
                    .tracking(-0.6)
                    .foregroundStyle(Constants.White)
                    .frame(maxWidth: .infinity, minHeight: 42)
            }
            .buttonStyle(.plain)
            .glassEffectCompat(in: Capsule(), interactive: true, tint: Constants.Black)
        }
    }

    /// Whole dollars when exact; otherwise two decimal places.
    private var usdAmountText: String {
        if balanceUsdc == floor(balanceUsdc) {
            return String(format: "%.0f", balanceUsdc)
        }
        return String(format: "%.2f", balanceUsdc)
    }
}

#Preview {
    OnePlanWalletCard(
        email: "namdinh252000@gmail.com",
        balanceUsdc: 120,
        balanceVnd: 3_157_620
    )
    .padding()
    .background(Constants.Background)
}
