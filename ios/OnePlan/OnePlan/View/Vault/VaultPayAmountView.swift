import SwiftUI

/// Types the amount to pay a scanned merchant.
///
/// Most Vietnamese shop codes are static and carry no amount, so this is the
/// normal path rather than an edge case. When the code does carry one the field
/// starts filled and the user only confirms.
///
/// The recipient's name comes from the bank, not from the code, which is what
/// tells someone they are paying who they think they are. It is fetched
/// separately from pricing, because pricing needs an amount and this screen
/// exists to collect one.
struct VaultPayAmountView: View {
    let recipientName: String
    let balanceVnd: Double
    /// Amount already carried by the QR code, if any.
    let prefilledAmountVnd: UInt64?
    /// VND per USDC, used only for the indicative line.
    let indicativeRate: Double
    var onBack: () -> Void = {}
    var onNext: (UInt64) -> Void = { _ in }

    @State private var digits: String = ""

    private var amountVnd: UInt64 { UInt64(digits) ?? 0 }

    private var formattedAmount: String {
        digits.isEmpty ? "0" : CurrencyFormatter.applyLiveFormatting(to: digits)
    }

    private var usdcText: String {
        guard indicativeRate > 0 else { return "" }
        return String(format: "$%.2f", Double(amountVnd) / indicativeRate)
    }

    private var overBalance: Bool {
        amountVnd > 0 && Double(amountVnd) > balanceVnd
    }

    private var canContinue: Bool { amountVnd > 0 && !overBalance }

    var body: some View {
        ZStack(alignment: .bottom) {
            Constants.Background.ignoresSafeArea()

            // The amount sits a little above centre in the design rather than
            // filling the space left over by the keypad.
            VStack(spacing: 20) {
                Text(formattedAmount)
                    .font(Font.beVietnamPro(48))
                    .tracking(-2.4)
                    .foregroundStyle(
                        overBalance
                            ? Constants.Secondary
                            : (amountVnd > 0 ? Constants.ContentB : Constants.ContentL)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)

                Text(usdcText)
                    .font(Font.beVietnamPro(14))
                    .tracking(-0.56)
                    .foregroundStyle(Constants.Neutral600)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 235)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Amount \(formattedAmount) dong, about \(usdcText)")

            VStack(spacing: 0) {
                recipientRow
                    .padding(.bottom, 12)
                keypadCard
            }
        }
        .safeAreaInset(edge: .top) { header }
        .onAppear {
            if let prefilledAmountVnd, digits.isEmpty {
                digits = String(prefilledAmountVnd)
            }
        }
    }

    /// Sizes read from the node: a 32pt square for the arrow, a 61pt pill for
    /// the word, five points apart, and the balance pinned to the right.
    private var header: some View {
        HStack(spacing: 5) {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Constants.Neutral900)
                    .frame(width: 32, height: 32)
            }
            .vaultHeaderChip()

            Button(action: onBack) {
                Text("Back")
                    .font(Font.beVietnamPro(15))
                    .tracking(-0.3)
                    .foregroundStyle(Constants.Neutral900)
                    .frame(width: 61, height: 34)
            }
            .vaultHeaderChip()

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Text("Balance")
                    .tracking(-0.3)
                Text(CurrencyFormatter.format(balanceVnd, currency: .VND, showDecimals: false))
                    .tracking(-0.6)
            }
            .font(Font.beVietnamPro(15))
            .foregroundStyle(Constants.Neutral900)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .vaultHeaderChip()
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var recipientRow: some View {
        HStack(spacing: 6) {
            // The exported flag rather than the emoji: the emoji renders as a
            // small glyph inside a grey circle, where the design fills the
            // circle with the flag itself.
            Image("flagVietnam")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 28, height: 28)
                .background(Constants.OnSurface)
                .clipShape(Circle())

            Text(recipientName)
                .font(Font.beVietnamPro(16))
                .tracking(-0.32)
                .foregroundStyle(Constants.Neutral900)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: 359)
        .background(Constants.Surface)
        .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
    }

    /// The keypad lives on a white card. That is what makes the keys visible:
    /// they are the same grey as the page behind it.
    private var keypadCard: some View {
        VStack(spacing: 12) {
            AmountKeypad(digits: $digits)

            if overBalance {
                Text("Insufficient balance")
                    .font(Font.beVietnamPro(13))
                    .foregroundStyle(Constants.Secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                onNext(amountVnd)
            } label: {
                Text("Next")
                    .font(Font.beVietnamPro(17))
                    .tracking(-0.68)
                    .foregroundStyle(Constants.White)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        canContinue ? Constants.Black : Constants.Neutral400,
                        in: Capsule()
                    )
            }
            .disabled(!canContinue)
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity)
        .background(Constants.Surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.09), radius: 4.5)
    }
}

#Preview {
    VaultPayAmountView(
        recipientName: "Nguyen Van A",
        balanceVnd: 5_000_000,
        prefilledAmountVnd: nil,
        indicativeRate: 26_500
    )
}
