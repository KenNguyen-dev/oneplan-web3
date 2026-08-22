import SwiftUI

/// In-flight deposit wait sheet (Figma `4539:34723` Depositing).
///
/// Shown on the trip card while the chain confirms. **Details** opens the
/// Move money receipt (Processing → Done).
struct VaultDepositingSheet: View {
    let amountMicro: UInt64
    let fromAddress: String
    let toAddress: String
    var onDetails: () -> Void

    private var amountText: String {
        Self.formatAmount(amountMicro)
    }

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.3))
                .frame(width: 35.194, height: 4.888)
                .padding(.top, 12)

            VStack(spacing: 24) {
                Image("depositContributeArrow")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)

                VStack(spacing: 4) {
                    Text(amountText)
                        .font(Font.beVietnamPro(32))
                        .tracking(-1.28)
                        .foregroundStyle(Constants.Neutral950)

                    Text(
                        "You're depositing \(amountText) from your OnePlan Wallet to TripFund. Please wait a few seconds."
                    )
                    .font(Font.beVietnamPro(14))
                    .tracking(-0.42)
                    .foregroundStyle(Constants.ContentM)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                }

                VStack(spacing: 8) {
                    addressRow(
                        label: "From",
                        value: Self.shorten(fromAddress)
                    )
                    addressRow(
                        label: "To",
                        value: Self.shorten(toAddress)
                    )
                }
                .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity)

            Button(action: onDetails) {
                Text("Details")
                    .font(Font.beVietnamPro(17))
                    .tracking(-0.68)
                    .foregroundStyle(Constants.White)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Constants.Neutral900, in: Capsule())
            }
            .padding(.horizontal, 1)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Constants.White)
    }

    private func addressRow(label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(label)
                .font(Font.beVietnamPro(15))
                .tracking(-0.45)
                .foregroundStyle(Constants.ContentM)
            Spacer(minLength: 8)
            Text(value)
                .font(Font.beVietnamPro(16))
                .tracking(-0.48)
                .foregroundStyle(Color(red: 0.224, green: 0.224, blue: 0.224))
        }
    }

    /// Figma truncates as `9RqQ...DzQi` (4 + 4).
    static func shorten(_ text: String) -> String {
        guard text.count > 8 else { return text }
        return "\(text.prefix(4))...\(text.suffix(4))"
    }

    static func formatAmount(_ amountMicro: UInt64) -> String {
        let value = Double(amountMicro) / 1_000_000
        if value == value.rounded() {
            return String(format: "$%.0f", value)
        }
        return String(format: "$%.2f", value)
    }
}

#Preview {
    VaultDepositingSheet(
        amountMicro: 5_000_000,
        fromAddress: "9RqQabcdefghijklmnopDzQi",
        toAddress: "6yTjabcdefghijklmnopoeRkh",
        onDetails: {}
    )
}
