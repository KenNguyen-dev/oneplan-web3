import SwiftUI
import UIKit

/// Funds / receives to the member's personal OnePlan Wallet via Solana USDC.
///
/// Deposit mode: top-up from an external Solana wallet before contributing to a
/// trip vault. Receive mode: same QR, copy used by Settlement "Show QR".
struct DepositToOnePlanWalletView: View {
    enum Mode {
        case deposit
        case receive
    }

    var mode: Mode = .deposit
    var onBack: () -> Void = {}

    @State private var address: String?
    @State private var isLoading = true
    @State private var hasCopied = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.3))
                .frame(width: 35.194, height: 4.888)
                .padding(.top, 12)

            header

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let address {
                depositCard(address)
                Spacer(minLength: 0)
                goBackButton
            } else {
                Spacer(minLength: 0)
                goBackButton
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 31)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Constants.White)
        .overlay(alignment: .bottom) {
            if hasCopied {
                copiedToast
                    .padding(.bottom, 100)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: hasCopied)
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
    }

    private var header: some View {
        VStack(spacing: 3) {
            (
                Text(mode == .receive ? "Receive to " : "Deposit to ")
                    .font(Font.beVietnamPro(20))
                    .foregroundColor(Constants.Neutral950)
                    + Text("OnePlan Wallet")
                    .font(Font.beVietnamProItalic(20))
                    .foregroundColor(Constants.BlueBase)
            )
            .tracking(-0.8)
            .multilineTextAlignment(.center)

            Text(
                mode == .receive
                    ? String(localized: "Receive USDC on Solana to your OnePlan Wallet")
                    : String(localized: "Deposit to OnePlan Wallet\nfrom your personal Solana wallet")
            )
                .font(Font.beVietnamPro(14))
                .tracking(-0.42)
                .foregroundStyle(Constants.ContentM)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func depositCard(_ address: String) -> some View {
        VStack(spacing: 16) {
            chainWarning
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            StyledQRCodeView(
                content: address,
                color: Constants.Black,
                size: 283,
                moduleRoundness: 0.5
            )
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)

            Button(action: { copyAddress(address) }) {
                addressText(address)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 250)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(hasCopied ? "Address copied" : "Copy wallet address")
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Constants.White)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 6.3, y: 4)
    }

    /// "Solana" is emphasised because it is the part that must not be misread.
    private var chainWarning: Text {
        (
            Text(
                mode == .receive
                    ? "Make sure to send USDC\nvia "
                    : "Make sure to deposit USDC\nvia "
            )
                .font(Font.beVietnamPro(16))
                .foregroundColor(Constants.ContentM)
                + Text("Solana")
                .font(Font.beVietnamProItalic(16, weight: .semibold))
                .foregroundColor(Constants.Black)
                + Text(" chain only.")
                .font(Font.beVietnamPro(16))
                .foregroundColor(Constants.ContentM)
        )
    }

    /// Highlights the leading and trailing characters — how people actually
    /// check an address; nobody reads the middle.
    private func addressText(_ address: String) -> Text {
        let highlight = 6
        let font = Font.beVietnamPro(16)
        guard address.count > highlight * 2 else {
            return Text(address).font(font).foregroundColor(Constants.BlueBase)
        }
        let head = String(address.prefix(highlight))
        let tail = String(address.suffix(highlight))
        let middle = String(address.dropFirst(highlight).dropLast(highlight))
        return Text(head).font(font).foregroundColor(Constants.BlueBase)
            + Text(middle).font(font).foregroundColor(Constants.ContentB)
            + Text(tail).font(font).foregroundColor(Constants.BlueBase)
    }

    private var goBackButton: some View {
        Button(action: onBack) {
            Text("Go back")
                .font(Font.beVietnamPro(17))
                .tracking(-0.68)
                .foregroundStyle(Constants.White)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Constants.Black, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var copiedToast: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .medium))
            Text("Copied successfully")
                .font(Font.beVietnamPro(15))
                .tracking(-0.3)
        }
        .foregroundStyle(Constants.White)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Constants.Neutral900.opacity(0.92), in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func copyAddress(_ address: String) {
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
            // Post-login bootstrap may still be in flight; link here if needed.
            if WalletService.shared.isConfigured {
                _ = try await WalletService.shared.ensureLinked()
            }
            let wallet = try await WalletWithdrawService.shared.myWallet()
            let key = wallet.publicKey
            address = key.isEmpty ? nil : key
            if key.isEmpty {
                errorMessage = String(localized: "No wallet linked yet.")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    DepositToOnePlanWalletView()
}
