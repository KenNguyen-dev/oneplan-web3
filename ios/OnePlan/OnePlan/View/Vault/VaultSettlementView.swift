import SwiftUI

/// Post-end Settlement tab for vault trips — Figma `4013:13084` / `4013:12968`.
///
/// After the vault has been wound up on chain, this screen is about cash debts
/// that involve the caller: expandable receive / pay rows, Mark as done, and
/// Show QR for the personal OnePlan Wallet.
struct VaultSettlementView: View {
    let tripId: Int
    var coverImageUrl: String? = nil
    var totalSpent: Double = 0
    var currency: Currency = .VND
    var members: [TripMemberDto] = []

    @Environment(UserProfileService.self) private var userProfileService
    @State private var vault = TripVaultService.shared
    @State private var preview: Components.Schemas.SettlementPreviewDto?
    @State private var errorMessage: String?
    @State private var isShowingWalletQR = false
    @State private var sendTarget: SendTarget?
    @State private var usdcToVnd: Double = 26_500

    private struct SendTarget: Identifiable {
        let id = UUID()
        let address: String
        let amountMicro: UInt64
    }

    private var myUserId: Int {
        userProfileService.profile?.id ?? 0
    }

    private var myDebts: [Components.Schemas.CashDebtDto] {
        guard let preview else { return [] }
        return preview.cashDebts.filter {
            $0.fromUserId == myUserId || $0.toUserId == myUserId
        }
    }

    private var unsettledCount: Int {
        myDebts.filter { !$0.isConfirmed }.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                TripEndHeroHeader(
                    coverImageUrl: coverImageUrl,
                    totalSpent: totalSpent,
                    unsettledPaymentCount: unsettledCount,
                    currency: currency
                )

                if let preview {
                    if !preview.isSettled {
                        settlingBanner
                    } else if myDebts.isEmpty {
                        Text("Nothing left to settle in cash")
                            .font(Font.beVietnamPro(14))
                            .foregroundStyle(Constants.ContentM)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 12)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(myDebts, id: \.pairKey) { debt in
                                VaultSettlementRow(
                                    entry: mapEntry(debt),
                                    onMarkAsDone: {
                                        await confirm(fromUserId: debt.fromUserId)
                                    },
                                    onShowQR: { isShowingWalletQR = true },
                                    onSendToWallet: {
                                        guard let address = debt.toWalletAddress,
                                              !address.isEmpty,
                                              let micro = UInt64(debt.amountMicro)
                                        else { return }
                                        sendTarget = SendTarget(
                                            address: address,
                                            amountMicro: micro
                                        )
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .scrollIndicators(.hidden)
        .background(.clear)
        .task { await load() }
        .onReceive(
            NotificationCenter.default.publisher(for: .vaultSettlementUpdated)
        ) { note in
            guard (note.userInfo?["tripId"] as? Int) == tripId else { return }
            Task { await load() }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .vaultBalanceChanged)
        ) { note in
            if let id = note.userInfo?["tripId"] as? Int, id != tripId {
                return
            }
            Task { await load() }
        }
        .alert(
            "Settlement failed",
            isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(errorMessage ?? "") }
        )
        .sheet(isPresented: $isShowingWalletQR) {
            DepositToOnePlanWalletView(
                mode: .receive,
                onBack: { isShowingWalletQR = false }
            )
            .presentationDetents([.fraction(0.8)])
            .presentationCornerRadius(48)
        }
        .sheet(item: $sendTarget) { target in
            WalletWithdrawView(
                onFinished: {
                    sendTarget = nil
                },
                prefilledAddress: target.address,
                prefilledAmountMicro: target.amountMicro
            )
            .presentationDetents([.large])
            .presentationCornerRadius(48)
        }
    }

    private var settlingBanner: some View {
        Text("Settling the trip fund…")
            .font(Font.beVietnamPro(14))
            .foregroundStyle(Constants.ContentM)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.top, 8)
    }

    private func mapEntry(
        _ debt: Components.Schemas.CashDebtDto
    ) -> VaultSettlementEntry {
        let isReceiving = debt.toUserId == myUserId
        let counterpartId = isReceiving ? debt.fromUserId : debt.toUserId
        let counterpartName = isReceiving ? debt.fromDisplayName : debt.toDisplayName
        let avatar = members.first(where: { Int($0.userId) == counterpartId })?.avatarUrl
        let usdc = Double(UInt64(debt.amountMicro) ?? 0) / 1_000_000
        let vnd = usdc * usdcToVnd
        let lines: [VaultSettlementEntry.Line] = debt.lines.map { line in
            let lineUsdc = Double(UInt64(line.amountMicro) ?? 0) / 1_000_000
            return .init(
                title: line.title,
                amount: lineUsdc * usdcToVnd,
                amountUsdc: lineUsdc
            )
        }

        return VaultSettlementEntry(
            id: counterpartId,
            name: counterpartName,
            avatarUrls: avatar.map { [$0] } ?? [],
            extraCount: 0,
            direction: isReceiving ? .receiving : .paying,
            amount: vnd,
            currency: .VND,
            amountUsdc: usdc,
            lines: lines,
            state: debt.isConfirmed ? .markedDone : .outstanding,
            // Send only when the caller owes and the creditor has a wallet.
            walletAddress: isReceiving ? nil : debt.toWalletAddress,
            canConfirm: debt.canConfirm
        )
    }

    private func confirm(fromUserId: Int) async {
        do {
            try await vault.confirmCashDebt(tripId: tripId, fromUserId: fromUserId)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func load() async {
        async let rateTask = ExchangeRateService.shared.rate(from: .USD, to: .VND)
        do {
            preview = try await vault.settlementPreview(tripId: tripId)
        } catch {
            errorMessage = error.localizedDescription
        }
        if let rate = try? await rateTask, rate > 0 {
            usdcToVnd = rate
        }
    }
}

private extension Components.Schemas.CashDebtDto {
    var pairKey: String { "\(fromUserId)-\(toUserId)" }
}
