import SwiftUI

/// Vault trip leave — member sheet (Figma 4711:1772 / 1973 / 2140).
///
/// Entire sheet is **USDC** (vault ledger). Merchant VND stays on History tab.
///
/// - net < 0: Deposit exact owed (gross for 0.1% skim) → then Announce
/// - net >= 0: Announce host
struct VaultLeaveBottomSheet: View {
    let preview: Components.Schemas.LeavePreviewDto
    var isWorking: Bool = false
    var onDeposit: () -> Void
    var onAnnounce: () async -> Void

    @Environment(\.dismiss) private var dismiss

    private var netMicro: Int64 {
        Int64(preview.netMicro ?? "0") ?? 0
    }

    /// Below $0.01 displays as `$0.00` — treat as balanced (Figma “All good”).
    private static let displayDustMicro: Int64 = 10_000

    private var isOweDisplay: Bool {
        netMicro <= -Self.displayDustMicro
    }

    private var isReceiveDisplay: Bool {
        netMicro >= Self.displayDustMicro
    }

    private var owedMicro: UInt64 {
        UInt64(preview.owedMicro ?? "0") ?? 0
    }

    /// Amount the member must send (includes 0.1% skim so vault nets `owed`).
    private var depositGrossMicro: UInt64 {
        ContributeToVaultView.grossDeposit(forNet: owedMicro)
    }

    private var heroAmountMicro: UInt64 {
        if isOweDisplay { return owedMicro }
        if isReceiveDisplay { return UInt64(netMicro) }
        return 0
    }

    private var statusLabel: String {
        if isOweDisplay {
            return String(localized: "You owe the group")
        }
        if isReceiveDisplay {
            return String(localized: "You’ll receive")
        }
        return String(localized: "All good")
    }

    private var totalDepositedMicro: Int64 {
        preview.lines.reduce(0) { sum, line in
            let signed = Int64(line.amountMicro) ?? 0
            return signed > 0 ? sum + signed : sum
        }
    }

    private var totalExpensesMicro: Int64 {
        preview.lines.reduce(0) { sum, line in
            let signed = Int64(line.amountMicro) ?? 0
            return signed < 0 ? sum + signed : sum
        }
    }

    private var settlementValue: String {
        if isOweDisplay {
            return String(localized: "Deposit \(formatUsdc(depositGrossMicro))")
        }
        if isReceiveDisplay {
            return String(localized: "Receive \(formatUsdc(UInt64(netMicro)))")
        }
        return formatUsdc(0)
    }

    private var ctaTitle: String {
        if preview.leaveRequestPending {
            return String(localized: "Announce sent")
        }
        if isOweDisplay {
            return String(localized: "Deposit \(formatUsdc(depositGrossMicro))")
        }
        return String(localized: "Announce host")
    }

    /// Local gate — don’t rely only on `canAnnounce` (stale preview / dust).
    private var canTapAnnounce: Bool {
        !preview.leaveRequestPending && !isOweDisplay
    }

    private var sheetHeight: CGFloat {
        let rowEstimate = CGFloat(max(preview.lines.count, 1)) * 80
        return min(720, max(520, 300 + rowEstimate))
    }

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.3))
                .frame(width: 35.194, height: 4.888)
                .padding(.top, 12)

            header

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    historyCard
                    totals
                }
            }

            cta
                .padding(.bottom, 32)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Constants.White)
        .presentationDetents([.height(sheetHeight), .large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(44)
    }

    private var header: some View {
        VStack(spacing: 24) {
            Button { dismiss() } label: {
                Image("vaultLeaveBackArrow")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .rotationEffect(.degrees(90))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Back"))

            VStack(spacing: 4) {
                Text(statusLabel)
                    .font(Font.beVietnamPro(14))
                    .tracking(-0.42)
                    .foregroundStyle(Constants.ContentM)

                Text(formatUsdc(heroAmountMicro))
                    .font(Font.beVietnamPro(32))
                    .tracking(-1.28)
                    .foregroundStyle(Constants.Neutral950)
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
        }
    }

    private var historyCard: some View {
        VStack(spacing: 2) {
            ForEach(Array(preview.lines.enumerated()), id: \.offset) { index, line in
                if index > 0 {
                    Divider()
                        .overlay(Constants.Neutral100)
                }
                VaultHistoryRow(
                    entry: mapEntry(line, id: index),
                    emphasizesSignedAmount: true,
                    usesOutlinedAllChip: true
                )
            }
        }
        .background(Constants.Neutral50, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var totals: some View {
        VStack(spacing: 8) {
            totalRow(
                label: String(localized: "Total deposited"),
                value: formatUsdc(UInt64(max(0, totalDepositedMicro)))
            )
            totalRow(
                label: String(localized: "Total expenses"),
                value: formatSignedUsdc(totalExpensesMicro)
            )
            totalRow(
                label: String(localized: "Settlement"),
                value: settlementValue
            )
        }
    }

    private func totalRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(Font.beVietnamPro(14))
                .tracking(-0.28)
                .foregroundStyle(Constants.ContentM)
            Spacer(minLength: 8)
            Text(value)
                .font(Font.beVietnamPro(14))
                .tracking(-0.28)
                .foregroundStyle(Constants.ContentB)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var cta: some View {
        if preview.leaveRequestPending {
            Text(ctaTitle)
                .font(Font.beVietnamPro(17))
                .tracking(-0.68)
                .foregroundStyle(Constants.ContentM)
                .frame(maxWidth: .infinity, minHeight: 52)
        } else if isOweDisplay {
            Button(action: onDeposit) {
                Text(ctaTitle)
                    .font(Font.beVietnamPro(17))
                    .tracking(-0.68)
                    .foregroundStyle(Constants.White)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.plain)
            .background(Constants.Neutral900, in: Capsule())
            .disabled(isWorking)
        } else {
            Button {
                Task { await onAnnounce() }
            } label: {
                if isWorking {
                    ProgressView()
                        .tint(Constants.White)
                        .frame(maxWidth: .infinity, minHeight: 52)
                } else {
                    Text(ctaTitle)
                        .font(Font.beVietnamPro(17))
                        .tracking(-0.68)
                        .foregroundStyle(Constants.White)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
            }
            .buttonStyle(.plain)
            .background(Constants.Neutral900, in: Capsule())
            .disabled(isWorking || !canTapAnnounce)
            .opacity(canTapAnnounce ? 1 : 0.45)
        }
    }

    private func mapEntry(
        _ line: Components.Schemas.LeaveLedgerLineDto,
        id: Int
    ) -> VaultHistoryEntry {
        let signedMicro = Int64(line.amountMicro) ?? 0
        let usdc = Double(signedMicro) / 1_000_000
        let kindUpper = line.kind.uppercased()
        let isDeposit = kindUpper == "DEPOSIT"
        let isSettlement = kindUpper == "SETTLEMENT"
        let category = line.category
            .flatMap { CategoryChip.Category(apiValue: $0) } ?? .other
        let time = line.time
        let subtitle = line.subtitle

        let kind: VaultHistoryEntry.Kind
        if isDeposit {
            kind = .deposit(fromAddress: subtitle ?? "")
        } else if isSettlement {
            kind = .settlement(toName: subtitle ?? "")
        } else if subtitle == nil || subtitle == "All" {
            kind = .expense(paidBy: nil, shareWith: [])
        } else {
            let people = (subtitle ?? "")
                .split(separator: ",")
                .map {
                    VaultHistoryEntry.Person(
                        name: $0.trimmingCharacters(in: .whitespaces),
                        avatarUrl: nil
                    )
                }
            kind = .expense(paidBy: nil, shareWith: people)
        }

        return VaultHistoryEntry(
            id: id,
            title: line.title,
            category: category,
            kind: kind,
            amount: usdc,
            currency: .USD,
            time: time
        )
    }

    private func formatUsdc(_ micro: UInt64) -> String {
        let usdc = Double(micro) / 1_000_000
        return "$" + CurrencyFormatter.formatUsdc(usdc)
    }

    private func formatSignedUsdc(_ signedMicro: Int64) -> String {
        let prefix = signedMicro < 0 ? "-" : (signedMicro > 0 ? "+" : "")
        return prefix + formatUsdc(UInt64(abs(signedMicro)))
    }
}
