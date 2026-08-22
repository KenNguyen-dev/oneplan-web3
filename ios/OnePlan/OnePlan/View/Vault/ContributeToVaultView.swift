import SwiftUI

/// Moves USDC from the member's own wallet into the group vault (Figma 4251:15126).
///
/// Opened from the contribute screen's "+" — the personal-wallet QR
/// screen (`DepositToOnePlanWalletView`) is only for topping up first.
struct ContributeToVaultView: View {
    let tripId: Int
    /// Optional micro-USDC to show when opened from leave deposit.
    var prefilledAmountMicro: UInt64? = nil
    /// When true (leave owed deposit), amount cannot be edited — avoids overpay.
    var locksAmount: Bool = false
    var onContribute: (UInt64) -> Void

    @State private var vault = TripVaultService.shared
    @State private var availableMicro: UInt64 = 0
    @State private var isLoading = true
    @State private var isShowingFundWallet = false
    @State private var digits = ""
    @State private var errorMessage: String?

    init(
        tripId: Int,
        prefilledAmountMicro: UInt64? = nil,
        locksAmount: Bool = false,
        onContribute: @escaping (UInt64) -> Void
    ) {
        self.tripId = tripId
        self.prefilledAmountMicro = prefilledAmountMicro
        self.locksAmount = locksAmount
        self.onContribute = onContribute
        if let prefilledAmountMicro, prefilledAmountMicro > 0 {
            let value = Double(prefilledAmountMicro) / 1_000_000
            let text = value == value.rounded()
                ? String(format: "%.0f", value)
                : String(format: "%.2f", value)
            _digits = State(initialValue: text)
        }
    }

    /// Typed USDC (supports decimals) → micro-USDC.
    private var amountMicro: UInt64 {
        if locksAmount, let prefilledAmountMicro, prefilledAmountMicro > 0 {
            return prefilledAmountMicro
        }
        return Self.microUSDC(from: digits)
    }

    private var isValid: Bool {
        amountMicro > 0 && amountMicro <= availableMicro
    }

    private var availableUsdc: Double { Double(availableMicro) / 1_000_000 }

    private var overCapacity: Bool {
        amountMicro > availableMicro
    }

    private var displayAmount: String {
        if locksAmount, let prefilledAmountMicro, prefilledAmountMicro > 0 {
            let value = Double(prefilledAmountMicro) / 1_000_000
            let text = value == value.rounded()
                ? String(format: "%.0f", value)
                : String(format: "%.2f", value)
            return "$\(text)"
        }
        return digits.isEmpty ? "$0" : "$\(digits)"
    }

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.3))
                .frame(width: 35.194, height: 4.888)
                .padding(.top, 12)

            header

            amountBlock
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 10) {
                balancePill

                VStack(spacing: 12) {
                    if locksAmount {
                        Text("Amount is fixed to clear your leave balance.")
                            .font(Font.beVietnamPro(13))
                            .foregroundStyle(Constants.Neutral600)
                            .multilineTextAlignment(.center)
                    } else {
                        AmountKeypad(digits: $digits, allowsDecimal: true)
                    }

                    if overCapacity {
                        Text("Insufficient balance")
                            .font(Font.beVietnamPro(13))
                            .foregroundStyle(Constants.Secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        Text(feeDisclosure)
                            .font(Font.beVietnamPro(13))
                            .foregroundStyle(Constants.Neutral600)
                            .multilineTextAlignment(.center)
                            .accessibilityLabel(feeDisclosure)
                    }

                    Button {
                        onContribute(amountMicro)
                    } label: {
                        Text("Contribute to Trip Fund")
                            .font(Font.beVietnamPro(17))
                            .tracking(-0.68)
                            .foregroundStyle(Constants.White)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(
                                isValid ? Constants.Black : Constants.Neutral400,
                                in: Capsule()
                            )
                    }
                    .disabled(!isValid)
                    .padding(.horizontal, 8)
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Constants.White)
        .task { await loadBalance() }
        .onAppear {
            // Re-apply lock prefill if the sheet remounted without init digits.
            guard locksAmount, digits.isEmpty,
                  let prefilledAmountMicro, prefilledAmountMicro > 0
            else { return }
            let value = Double(prefilledAmountMicro) / 1_000_000
            digits = value == value.rounded()
                ? String(format: "%.0f", value)
                : String(format: "%.2f", value)
        }
        .sheet(isPresented: $isShowingFundWallet, onDismiss: {
            Task { await loadBalance() }
        }) {
            DepositToOnePlanWalletView {
                isShowingFundWallet = false
            }
            .presentationDetents([.fraction(0.8)])
            .presentationCornerRadius(48)
        }
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
                Text("Contribute via ")
                    .font(Font.beVietnamPro(20))
                    .foregroundColor(Constants.Neutral950)
                    + Text("OnePlan Wallet")
                    .font(Font.beVietnamProItalic(20))
                    .foregroundColor(Constants.BlueBase)
            )
            .tracking(-0.8)
            .multilineTextAlignment(.center)

            Text("Contributing to trip fund by using OnePlan Wallet")
                .font(Font.beVietnamPro(14))
                .tracking(-0.42)
                .foregroundStyle(Constants.ContentM)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var amountBlock: some View {
        VStack(spacing: 12) {
            Text("Contribute amount")
                .font(Font.beVietnamPro(14))
                .tracking(-0.7)
                .foregroundStyle(Constants.Neutral950)

            Text(displayAmount)
                .font(Font.beVietnamPro(48))
                .tracking(-2.4)
                .foregroundStyle(
                    (!locksAmount && digits.isEmpty)
                        ? Constants.Neutral950.opacity(0.2)
                        : (overCapacity ? Constants.Secondary : Constants.Neutral950)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Contribute amount \(displayAmount)")
    }

    private var balancePill: some View {
        HStack(spacing: 8) {
            Image("depositOptionWallet")
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            Text("Your balance")
                .font(Font.beVietnamPro(16))
                .tracking(-0.32)
                .foregroundStyle(Color(red: 0.24, green: 0.24, blue: 0.24).opacity(0.6))
                .lineLimit(1)

            Spacer(minLength: 0)

            Group {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(String(format: "$%.2f", availableUsdc))
                        .font(Font.beVietnamPro(18))
                        .tracking(-0.36)
                        .foregroundStyle(Color(red: 0.24, green: 0.24, blue: 0.24))
                }
            }

            Button {
                isShowingFundWallet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Constants.White)
                    .frame(width: 28, height: 28)
                    .background(Constants.Black, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add funds to your wallet")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Constants.Neutral50)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Constants.Neutral100, lineWidth: 1)
        )
    }

    /// Matches on-chain skim: 0.1% (10 bps). Shown before the member signs so
    /// the group balance they expect is the net, not the amount they typed.
    static let depositFeeBps: UInt64 = 10

    /// Gross send so vault net after the 0.1% skim is at least `netMicro`.
    /// `ceil(net * 10_000 / 9_990)`.
    static func grossDeposit(forNet netMicro: UInt64) -> UInt64 {
        guard netMicro > 0 else { return 0 }
        let keepBps = 10_000 - depositFeeBps
        return (netMicro * 10_000 + keepBps - 1) / keepBps
    }

    private var feeMicro: UInt64 {
        amountMicro * Self.depositFeeBps / 10_000
    }

    private var netMicro: UInt64 {
        amountMicro - feeMicro
    }

    private var feeDisclosure: String {
        guard amountMicro > 0 else {
            return String(localized: "A 0.1% fee goes to OnePlan.")
        }
        let net = String(format: "%.6f", Double(netMicro) / 1_000_000)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
        return String(
            localized: "0.1% fee to OnePlan · group receives \(net) USDC"
        )
    }

    private func loadBalance() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let wallet = try await vault.myWallet(tripId: tripId)
            availableMicro = UInt64(wallet.balanceMicro) ?? 0
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// `"12.34"` → 12_340_000 micro. Caps fractional digits at 6 (USDC decimals).
    static func microUSDC(from digits: String) -> UInt64 {
        guard !digits.isEmpty else { return 0 }
        let parts = digits.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let whole = UInt64(parts[0]) ?? 0
        guard parts.count > 1 else { return whole * 1_000_000 }
        let fracRaw = String(parts[1].prefix(6))
        let padded = fracRaw.padding(toLength: 6, withPad: "0", startingAt: 0)
        let frac = UInt64(padded) ?? 0
        return whole &* 1_000_000 &+ frac
    }
}

#Preview {
    ContributeToVaultView(tripId: 1) { _ in }
}
