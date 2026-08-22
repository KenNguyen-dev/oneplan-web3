import SwiftUI

/// Personal wallet detail (Figma 4245:15020): balance, actions, history.
///
/// History has no API yet — the list stays empty until `GET /wallet/history`
/// lands. Prefer a server endpoint over the app talking to Solana RPC.
struct OnePlanWalletView: View {
    /// When true, present the deposit sheet after the detail screen appears
    /// (welcome "Add money" deep link).
    var openDepositOnAppear: Bool = false

    @Environment(UserProfileService.self) private var userProfileService
    @Environment(\.dismiss) private var dismiss

    @State private var wallet = WalletWithdrawService.shared
    @State private var balanceMicro: UInt64 = 0
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isShowingWithdraw = false
    @State private var isShowingDeposit = false
    /// One-shot: do not re-present deposit when returning to this screen.
    @State private var didConsumeOpenDepositIntent = false
    /// Filled once a personal-wallet history endpoint exists.
    @State private var history: [OnePlanWalletHistoryEntry] = []

    /// Indicative only — same ballpark as trip vault UX until live FX is wired.
    private static let indicativeUsdcToVnd: Double = 26_500

    private var balanceUsdc: Double { Double(balanceMicro) / 1_000_000 }
    private var balanceVnd: Double { balanceUsdc * Self.indicativeUsdcToVnd }

    private var usdAmountText: String {
        if balanceUsdc == floor(balanceUsdc) {
            return String(format: "%.0f", balanceUsdc)
        }
        return String(format: "%.2f", balanceUsdc)
    }

    var body: some View {
        ZStack(alignment: .top) {
            skyGradient
                .ignoresSafeArea(edges: .top)

            ScrollView {
                VStack(spacing: 0) {
                    // Figma 4245:15020 places the balance near y≈386 — large empty
                    // gradient above, not content hugging the nav.
                    balanceBlock
                        .padding(.top, 280)
                        .padding(.horizontal, 16)

                    actionButtons
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .padding(.horizontal, 12)

                    historyCard
                        .padding(.top, 16)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 24)
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(Constants.White.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                backChrome
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await load() }
        .task(id: openDepositOnAppear) {
            guard openDepositOnAppear, !didConsumeOpenDepositIntent else { return }
            didConsumeOpenDepositIntent = true
            try? await Task.sleep(for: .milliseconds(350))
            isShowingDeposit = true
        }
        .sheet(isPresented: $isShowingWithdraw, onDismiss: {
            Task { await load() }
        }) {
            WalletWithdrawView {
                isShowingWithdraw = false
            }
            .presentationDetents([.large])
            .presentationCornerRadius(48)
        }
        .sheet(isPresented: $isShowingDeposit, onDismiss: {
            Task { await load() }
        }) {
            DepositToOnePlanWalletView {
                isShowingDeposit = false
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

    /// Soft blue → peach → white wash behind the balance (Figma gradient).
    private var skyGradient: some View {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0.706, green: 0.875, blue: 1), location: 0),
                .init(color: Color(red: 0.984, green: 0.925, blue: 0.843), location: 0.51),
                .init(color: Constants.White, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 345)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var backChrome: some View {
        HStack(spacing: 5) {
            Button(action: { dismiss() }) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Constants.Neutral900)
                    .frame(width: 32, height: 32)
            }
            .vaultHeaderChip()

            Button(action: { dismiss() }) {
                Text("Back")
                    .font(Font.beVietnamPro(15))
                    .tracking(-0.3)
                    .foregroundStyle(Constants.Neutral900)
                    .frame(width: 61, height: 34)
            }
            .vaultHeaderChip()
        }
    }

    private var balanceBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                ProgressView()
                    .controlSize(.large)
                    .padding(.vertical, 12)
            } else {
                HStack(spacing: 3) {
                    Text("$")
                        .font(Font.beVietnamPro(48))
                        .tracking(-0.96)
                        .foregroundStyle(Constants.ContentL)
                    Text(usdAmountText)
                        .font(Font.beVietnamPro(48))
                        .tracking(-0.96)
                        .foregroundStyle(Constants.ContentB)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.4)

                Text("\(CurrencyFormatter.formatWhole(balanceVnd)) VND")
                    .font(Font.beVietnamPro(16))
                    .tracking(-0.64)
                    .foregroundStyle(Constants.Neutral600)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Balance \(usdAmountText) USDC, about \(CurrencyFormatter.formatWhole(balanceVnd)) VND"
        )
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
            // Figma 4251:3537 / 4251:3538 — same 15pt / 42pt pair as vault card.
            Button { isShowingWithdraw = true } label: {
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

            Button { isShowingDeposit = true } label: {
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

    private var historyCard: some View {
        VStack(spacing: 0) {
            if history.isEmpty {
                Text("No activity yet")
                    .font(Font.beVietnamPro(14))
                    .foregroundStyle(Constants.ContentM)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .padding(.horizontal, 10)
            } else {
                ForEach(Array(history.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Divider()
                            .overlay(Constants.Neutral100)
                    }
                    OnePlanWalletHistoryRow(entry: entry)
                }
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity)
        .background(Constants.Neutral50, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            if WalletService.shared.isConfigured {
                _ = try await WalletService.shared.ensureLinked()
            }
            let info = try await wallet.myWallet()
            balanceMicro = UInt64(info.balanceMicro) ?? 0
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        // History is best-effort: a Solana RPC blip must not blank the balance.
        do {
            history = try await wallet.history().map(Self.mapHistory)
        } catch {
            history = []
        }
    }

    private static func mapHistory(
        _ row: Components.Schemas.WalletHistoryEntryDto
    ) -> OnePlanWalletHistoryEntry {
        let amount = Double(row.amountMicro).map { $0 / 1_000_000 } ?? 0
        let kind: OnePlanWalletHistoryEntry.Kind =
            row.kind == "withdraw" ? .withdraw : .deposit
        return OnePlanWalletHistoryEntry(
            id: row.id,
            kind: kind,
            address: row.address,
            amountUsdc: amount,
            time: formatTime(row.createdAt, blockTime: row.blockTime)
        )
    }

    private static func formatTime(_ createdAt: String, blockTime: String) -> String {
        let date: Date?
        if let parsed = Self.iso8601.date(from: createdAt) {
            date = parsed
        } else if let seconds = TimeInterval(blockTime), seconds > 0 {
            date = Date(timeIntervalSince1970: seconds)
        } else {
            date = nil
        }
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

#Preview {
    NavigationStack {
        OnePlanWalletView()
    }
}
