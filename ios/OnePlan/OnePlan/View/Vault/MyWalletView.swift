import SwiftUI

/// The member's own wallet: where their USDC sits before it joins the group.
///
/// Money has to pass through here. The group vault only records who contributed
/// when the deposit instruction runs, and a transfer sent straight into the
/// vault from an exchange has no attributable sender — settlement is built on
/// knowing who put in what, so an unattributable balance cannot be split.
struct MyWalletView: View {
    let tripId: Int
    /// When false, this sheet is only for funding the personal wallet (QR /
    /// copy). Used from the contribute screen's "+" so we do not nest another
    /// contribute sheet.
    var showsContributeAction: Bool = true
    var onContribute: (UInt64) -> Void = { _ in }

    @State private var vault = TripVaultService.shared
    @State private var address: String?
    @State private var balanceMicro: UInt64 = 0
    @State private var isLoading = true
    @State private var isContributing = false
    @State private var hasCopied = false
    @State private var errorMessage: String?

    private var balanceUsdc: Double { Double(balanceMicro) / 1_000_000 }

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Constants.Neutral200)
                .frame(width: 35, height: 5)
                .padding(.top, 12)

            VStack(spacing: 1) {
                Text("Your wallet")
                    .font(Font.beVietnamPro(20))
                    .tracking(-0.8)
                    .foregroundStyle(Constants.ContentB)

                chainWarning
                    .font(Font.beVietnamPro(14))
                    .tracking(-0.42)
                    .foregroundStyle(Constants.ContentM)
                    .multilineTextAlignment(.center)
            }

            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                card
                Spacer(minLength: 0)
                actions
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Constants.Surface)
        .task { await load() }
        .alert(
            "Could not load your wallet",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(errorMessage ?? "") }
        )
        .sheet(isPresented: $isContributing) {
            ContributeToVaultView(tripId: tripId) { amount in
                isContributing = false
                onContribute(amount)
            }
            .presentationDetents([.large])
            .presentationCornerRadius(48)
        }
    }

    private var card: some View {
        VStack(spacing: 16) {
            VStack(spacing: 2) {
                Text("Available")
                    .font(Font.beVietnamPro(14))
                    .foregroundStyle(Constants.ContentM)
                Text(String(format: "%.2f USDC", balanceUsdc))
                    .font(Font.beVietnamPro(28))
                    .tracking(-0.56)
                    .foregroundStyle(Constants.ContentB)
            }

            if let address {
                StyledQRCodeView(
                    content: address,
                    color: Constants.Black,
                    size: 220,
                    moduleRoundness: 0.5
                )
                addressText(address)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Constants.Background)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if showsContributeAction {
                Button {
                    isContributing = true
                } label: {
                    Text("Contribute to the group")
                        .font(Font.beVietnamPro(17))
                        .tracking(-0.68)
                        .foregroundStyle(Constants.White)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(
                            balanceMicro > 0 ? VaultPalette.accent : Constants.Neutral400,
                            in: Capsule()
                        )
                }
                .disabled(balanceMicro == 0)
            }

            Button(action: copyAddress) {
                Text(hasCopied ? "Copied" : "Copy address")
                    .font(Font.beVietnamPro(15))
                    .tracking(-0.75)
                    .foregroundStyle(Constants.ContentB)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .background(Constants.Surface, in: Capsule())
            .shadow(color: .black.opacity(0.10), radius: 1)
            .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
        }
    }

    /// "Solana" is emphasised because it is the part that must not be misread:
    /// USDC exists on many chains and the wrong one loses the funds.
    private var chainWarning: Text {
        Text("Send USDC here via ")
            + Text("Solana")
                .font(Font.beVietnamProItalic(14, weight: .bold))
                .foregroundColor(Constants.Black)
            + Text(" only, then contribute to the group.")
    }

    private func addressText(_ address: String) -> Text {
        let highlight = 6
        let font = Font.beVietnamPro(14)
        guard address.count > highlight * 2 else {
            return Text(address).font(font).foregroundColor(Constants.BlueBase)
        }
        return Text(String(address.prefix(highlight))).font(font)
            .foregroundColor(Constants.BlueBase)
            + Text(String(address.dropFirst(highlight).dropLast(highlight)))
                .font(font).foregroundColor(Constants.ContentB)
            + Text(String(address.suffix(highlight))).font(font)
                .foregroundColor(Constants.BlueBase)
    }

    private func copyAddress() {
        guard let address else { return }
        UIPasteboard.general.string = address
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation { hasCopied = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { hasCopied = false }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let wallet = try await vault.myWallet(tripId: tripId)
            address = wallet.publicKey
            balanceMicro = UInt64(wallet.balanceMicro) ?? 0
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
