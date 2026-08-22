import SwiftUI
import UIKit

/// Withdraw USDC from the personal OnePlan Wallet (Figma 4251:4124).
///
/// Presented as a sheet from the wallet detail screen. Amount + destination
/// live on one screen so the member sees both before they sign.
struct WalletWithdrawView: View {
    var onFinished: () -> Void = {}
    /// Prefill from settlement Send (creditor wallet + cash-debt amount).
    var prefilledAddress: String = ""
    var prefilledAmountMicro: UInt64? = nil

    @State private var wallet = WalletWithdrawService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var address = ""
    @State private var digits = ""
    @State private var balanceMicro: UInt64 = 0
    @State private var recipientIsNew = false
    @State private var addressError: String?
    @State private var isCheckingAddress = false
    @State private var isSending = false
    @State private var isEditingAddress = false
    @State private var result: WalletWithdrawResult?
    @State private var errorMessage: String?

    private var amountMicro: UInt64 {
        ContributeToVaultView.microUSDC(from: digits)
    }

    private var hasAddress: Bool {
        !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var overCapacity: Bool {
        amountMicro > balanceMicro
    }

    private var canSend: Bool {
        hasAddress && addressError == nil && amountMicro > 0
            && !overCapacity && !isSending
    }

    private var displayAmount: String {
        digits.isEmpty ? "$0" : "$\(digits)"
    }

    var body: some View {
        Group {
            if let result {
                WalletWithdrawResultView(
                    result: result,
                    onDone: {
                        onFinished()
                        dismiss()
                    },
                    onSendAgain: {
                        self.result = nil
                    }
                )
            } else {
                form
            }
        }
        .task {
            applyPrefill()
            await load()
            if hasAddress {
                await checkAddress()
            }
        }
        .alert(
            "Withdrawal failed",
            isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(errorMessage ?? "") }
        )
        .sheet(isPresented: $isEditingAddress) {
            addressEditor
                .presentationDetents([.height(220)])
                .presentationCornerRadius(28)
        }
    }

    private var form: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.3))
                .frame(width: 35.194, height: 4.888)
                .padding(.top, 12)

            header

            amountBlock
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 8) {
                addressPill

                if let addressError {
                    Text(addressError)
                        .font(Font.beVietnamPro(13))
                        .foregroundStyle(Constants.Secondary)
                        .multilineTextAlignment(.center)
                } else if recipientIsNew, hasAddress {
                    Text("This address has never held USDC. Check it carefully.")
                        .font(Font.beVietnamPro(13))
                        .foregroundStyle(Constants.Warning500)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    AmountKeypad(digits: $digits, allowsDecimal: true)

                    if overCapacity {
                        Text("Insufficient balance")
                            .font(Font.beVietnamPro(13))
                            .foregroundStyle(Constants.Secondary)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        Task { await send() }
                    } label: {
                        Group {
                            if isSending {
                                ProgressView().tint(Constants.White)
                            } else {
                                Text("Confirm & Withdraw")
                                    .font(Font.beVietnamPro(17))
                                    .tracking(-0.68)
                                    .foregroundStyle(Constants.White)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(
                            canSend ? Constants.Black : Constants.Neutral400,
                            in: Capsule()
                        )
                    }
                    .disabled(!canSend)
                    .padding(.horizontal, 8)

                    Text("Network fees are covered by One Plan.")
                        .font(Font.beVietnamPro(13))
                        .foregroundStyle(Constants.ContentM)
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Constants.White)
    }

    private var header: some View {
        VStack(spacing: 3) {
            (
                Text("Withdraw from ")
                    .font(Font.beVietnamPro(20))
                    .foregroundColor(Constants.Neutral950)
                    + Text("OnePlan Wallet")
                    .font(Font.beVietnamProItalic(20))
                    .foregroundColor(Constants.BlueBase)
            )
            .tracking(-0.8)
            .multilineTextAlignment(.center)

            Text("Withdrawing to your personal Solana wallet")
                .font(Font.beVietnamPro(14))
                .tracking(-0.42)
                .foregroundStyle(Constants.ContentM)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var amountBlock: some View {
        VStack(spacing: 12) {
            Text("Withdraw amount")
                .font(Font.beVietnamPro(14))
                .tracking(-0.7)
                .foregroundStyle(Constants.Neutral950)

            Text(displayAmount)
                .font(Font.beVietnamPro(48))
                .tracking(-2.4)
                .foregroundStyle(
                    digits.isEmpty
                        ? Constants.Neutral950.opacity(0.2)
                        : (overCapacity ? Constants.Secondary : Constants.Neutral950)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Withdraw amount \(displayAmount)")
    }

    private var addressPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.up")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Constants.BlueBase)
                .frame(width: 29, height: 29)
                .background(Constants.BlueBase.opacity(0.1), in: Circle())
                .accessibilityHidden(true)

            Button {
                isEditingAddress = true
            } label: {
                Text(hasAddress ? Self.shorten(address) : String(localized: "Wallet address"))
                    .font(Font.beVietnamPro(16))
                    .tracking(-0.32)
                    .foregroundStyle(
                        Color(red: 0.24, green: 0.24, blue: 0.24)
                            .opacity(hasAddress ? 1 : 0.4)
                    )
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                paste()
            } label: {
                Group {
                    if isCheckingAddress {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Constants.White)
                    } else {
                        Text("Paste")
                            .font(Font.beVietnamPro(14))
                            .tracking(-0.28)
                            .foregroundStyle(Constants.White)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Constants.Black, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isCheckingAddress)

            Button {
                isEditingAddress = true
            } label: {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Constants.ContentB)
                    .frame(width: 29, height: 29)
                    .background(Constants.OnSurface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Enter wallet address")
        }
        .padding(12)
        .background(Constants.Neutral50)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Constants.Neutral100, lineWidth: 1))
    }

    private var addressEditor: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Constants.Neutral200)
                .frame(width: 35, height: 5)
                .padding(.top, 12)

            Text("Wallet address")
                .font(Font.beVietnamPro(18))
                .foregroundStyle(Constants.ContentB)

            TextField("Solana address", text: $address)
                .font(Font.beVietnamPro(15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(Constants.Neutral50, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)

            Button {
                isEditingAddress = false
                Task { await checkAddress() }
            } label: {
                Text("Done")
                    .font(Font.beVietnamPro(17))
                    .foregroundStyle(Constants.White)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Constants.Black, in: Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Constants.White)
    }

    private func paste() {
        address = UIPasteboard.general.string?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? address
        Task { await checkAddress() }
    }

    private func applyPrefill() {
        if !prefilledAddress.isEmpty, address.isEmpty {
            address = prefilledAddress
        }
        if let micro = prefilledAmountMicro, digits.isEmpty, micro > 0 {
            let usdc = Double(micro) / 1_000_000
            digits = Self.trimmed(usdc)
        }
    }

    private func load() async {
        do {
            let mine = try await wallet.myWallet()
            balanceMicro = UInt64(mine.balanceMicro) ?? 0
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func checkAddress() async {
        guard hasAddress else {
            addressError = nil
            recipientIsNew = false
            return
        }
        isCheckingAddress = true
        defer { isCheckingAddress = false }
        do {
            let check = try await wallet.inspectRecipient(address: address)
            address = check.address
            recipientIsNew = check.isNew
            addressError = nil
        } catch {
            addressError = error.localizedDescription
        }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        do {
            result = try await wallet.withdraw(
                address: address,
                amountMicro: amountMicro
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func shorten(_ address: String) -> String {
        guard address.count > 10 else { return address }
        return "\(address.prefix(4))...\(address.suffix(4))"
    }

    private static func trimmed(_ value: Double) -> String {
        value == value.rounded()
            ? String(format: "%.0f", value)
            : String(format: "%.2f", value)
    }
}

#Preview {
    Color.gray
        .sheet(isPresented: .constant(true)) {
            WalletWithdrawView()
                .presentationDetents([.large])
                .presentationCornerRadius(48)
        }
}
