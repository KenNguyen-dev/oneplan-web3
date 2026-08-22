import SwiftUI

/// Screen 2: every member reviews the vault ledger and Approves or Denies ending.
/// Figma `4569:1596` Confirmation.
struct TripEndReviewView: View {
    let tripId: Int
    var coverImageUrl: String? = nil
    var onApproved: (_ request: TripEndRequestDto) -> Void = { _ in }
    var onDenied: (_ request: TripEndRequestDto) -> Void = { _ in }
    var onBack: () -> Void = {}

    @Environment(UserProfileService.self) private var userProfileService
    @State private var review: TripEndReviewDto?
    @State private var isWorking = false
    @State private var errorMessage: String?
    /// USD≈USDC → VND for cash-debt labels. Falls back until the rate fetch lands.
    @State private var usdcToVnd: Double = 26_500

    private var myUserId: Int {
        userProfileService.profile?.id ?? 0
    }

    private var historyEntries: [VaultHistoryEntry] {
        (review?.history ?? []).map(Self.mapHistory)
    }

    private var historyTotal: Double {
        historyEntries.reduce(0) { $0 + $1.amount }
    }

    private var settlementTotal: Double {
        (review?.mySettlement ?? []).reduce(0) { sum, debt in
            let usdc = Double(UInt64(debt.amountMicro) ?? 0) / 1_000_000
            return sum + (debt.toUserId == myUserId ? usdc : -usdc)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TripEndConsensusChrome.BackHeader(onBack: onBack)

            if review != nil {
                ScrollView {
                    VStack(spacing: 28) {
                        heroCopy
                        ledgerSections
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }

                voteBar
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Constants.Background)
        .task { await load() }
        .alert(
            "Could not load review",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(errorMessage ?? "") }
        )
    }

    private var heroCopy: some View {
        VStack(spacing: 28) {
            PioneerAvatar(size: 140, imageUrl: coverImageUrl)

            VStack(spacing: 3) {
                Text("You are preparing to end your trip.")
                    .font(Font.beVietnamPro(20))
                    .tracking(-0.8)
                    .foregroundStyle(Constants.Neutral950)
                    .multilineTextAlignment(.center)

                Text(
                    "Please review the transaction details below. Select \"Approve\" if you participated in all the listed transactions. Select \"Deny\" if the information is incorrect, then notify the host to make corrections."
                )
                .font(Font.beVietnamPro(14))
                .tracking(-0.42)
                .foregroundStyle(Constants.ContentM)
                .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var ledgerSections: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionCaption(
                title: "History",
                total: formatSignedTotal(historyTotal, currency: historyCurrency)
            )

            historyCard

            sectionCaption(
                title: "Settlement",
                total: formatSignedTotal(settlementTotal, currency: .USD)
            )

            settlementCard
        }
    }

    private var historyCurrency: Currency {
        historyEntries.first(where: { $0.currency != .USD })?.currency
            ?? historyEntries.first?.currency
            ?? .VND
    }

    private func sectionCaption(title: LocalizedStringKey, total: String) -> some View {
        HStack {
            Text(title)
                .font(Font.beVietnamPro(14))
                .tracking(-0.28)
            Spacer(minLength: 8)
            Text(total)
                .font(Font.beVietnamPro(14))
                .tracking(-0.28)
        }
        .foregroundStyle(Constants.ContentM)
    }

    @ViewBuilder
    private var historyCard: some View {
        if historyEntries.isEmpty {
            Text("No vault activity yet")
                .font(Font.beVietnamPro(14))
                .foregroundStyle(Constants.ContentM)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(historyEntries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Divider().padding(.leading, 56)
                    }
                    VaultHistoryRow(
                        entry: entry,
                        emphasizesSignedAmount: true
                    )
                }
            }
            .padding(.vertical, 2)
            .background(Constants.Surface)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    @ViewBuilder
    private var settlementCard: some View {
        let debts = review?.mySettlement ?? []
        if debts.isEmpty {
            Text("Nothing left to settle in cash")
                .font(Font.beVietnamPro(14))
                .foregroundStyle(Constants.ContentM)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 0) {
                ForEach(debts, id: \.pairKey) { debt in
                    settlementRow(debt)
                }
            }
            .padding(8)
            .background(Constants.Surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Constants.White, lineWidth: 1)
            )
        }
    }

    private func settlementRow(_ debt: Components.Schemas.CashDebtDto) -> some View {
        let isReceiving = debt.toUserId == myUserId
        let counterpartId = isReceiving ? debt.fromUserId : debt.toUserId
        let counterpartName = isReceiving ? debt.fromDisplayName : debt.toDisplayName
        let avatarUrl = review?.request.members
            .first(where: { $0.userId == counterpartId })?
            .avatarUrl
        let usdc = Double(UInt64(debt.amountMicro) ?? 0) / 1_000_000
        let sign = isReceiving ? "+" : "-"
        let usdcLabel = sign + CurrencyFormatter.formatUsdc(usdc)
        let vndLabel = sign + CurrencyFormatter.format(
            usdc * usdcToVnd,
            currency: .VND,
            showDecimals: false
        )

        return HStack(spacing: 8) {
            avatar(avatarUrl, name: counterpartName)

            VStack(alignment: .leading, spacing: 2) {
                Text(isReceiving ? "Receive from" : "Pay")
                    .font(Font.beVietnamPro(14))
                    .tracking(-0.28)
                    .foregroundStyle(Constants.Neutral700)
                Text(counterpartName)
                    .font(Font.beVietnamPro(16, weight: .medium))
                    .tracking(-0.32)
                    .foregroundStyle(Constants.ContentB)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 3) {
                    Text(usdcLabel)
                        .font(Font.beVietnamPro(18))
                        .tracking(-0.36)
                        .foregroundStyle(Constants.ContentB)
                    Text("USDC")
                        .font(Font.beVietnamPro(18))
                        .tracking(-0.36)
                        .foregroundStyle(Constants.ContentL)
                }
                Text(vndLabel)
                    .font(Font.beVietnamPro(14))
                    .tracking(-0.28)
                    .foregroundStyle(Constants.ContentM)
            }
        }
        .padding(.trailing, 12)
        .padding(.vertical, 2)
    }

    private var voteBar: some View {
        HStack(spacing: 7) {
            Button {
                Task { await vote(.DENIED) }
            } label: {
                Text("Deny")
                    .font(Font.beVietnamPro(17))
                    .tracking(-0.68)
                    .foregroundStyle(Constants.White)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Constants.Black, in: Capsule())
            }
            .disabled(isWorking)

            Button {
                Task { await vote(.APPROVED) }
            } label: {
                Text(isWorking ? "…" : "Approve")
                    .font(Font.beVietnamPro(17))
                    .tracking(-0.68)
                    .foregroundStyle(Constants.White)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .glassEffectCompat(
                in: Capsule(),
                interactive: true,
                tint: VaultPalette.accent
            )
            .disabled(isWorking)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Constants.Background)
    }

    private func avatar(_ urlString: String?, name: String) -> some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                CachedRemoteImage(url: url, targetSize: CGSize(width: 52, height: 52)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle().fill(Constants.Neutral200)
                }
            } else {
                ZStack {
                    Circle().fill(Constants.Neutral200)
                    Text(String(name.prefix(1)).uppercased())
                        .font(Font.beVietnamPro(16))
                        .foregroundStyle(Constants.ContentM)
                }
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(Circle())
        .overlay(Circle().stroke(Constants.White, lineWidth: 2))
    }

    private func formatSignedTotal(_ value: Double, currency: Currency) -> String {
        let sign = value < 0 ? "-" : (value > 0 ? "+" : "")
        let magnitude = abs(value)
        if currency == .USD {
            return sign + currency.symbol + CurrencyFormatter.formatUsdc(magnitude)
        }
        return sign
            + CurrencyFormatter.format(
                magnitude,
                currency: currency,
                showDecimals: currency.decimalPlaces > 0
            )
    }

    private func vote(_ decision: TripEndVoteDecision) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await TripEndConsensusService.shared.vote(
                tripId: tripId,
                decision: decision
            )
            if decision == .DENIED || result.status.value1 == .DENIED {
                onDenied(result)
            } else {
                onApproved(result)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func load() async {
        async let rateTask = ExchangeRateService.shared.rate(from: .USD, to: .VND)
        do {
            review = try await TripEndConsensusService.shared.getReview(tripId: tripId)
        } catch {
            errorMessage = error.localizedDescription
        }
        if let rate = try? await rateTask, rate > 0 {
            usdcToVnd = rate
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static func mapHistory(
        _ entry: Components.Schemas.VaultHistoryEntryDto
    ) -> VaultHistoryEntry {
        let usdc = Double(UInt64(entry.amountMicro) ?? 0) / 1_000_000
        let vnd = entry.amountVnd.flatMap { Double($0) }
        let isDeposit = entry.kind == "DEPOSIT"
        let isSettlement = entry.kind == "SETTLEMENT"
        let isIncoming = isDeposit || isSettlement
        let category = entry.category
            .flatMap { CategoryChip.Category(apiValue: $0.value1.rawValue) } ?? .other
        let amount = isIncoming ? usdc : (vnd ?? usdc)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: entry.createdAt)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: entry.createdAt)
        }

        return VaultHistoryEntry(
            id: entry.id,
            title: entry.title ?? (isDeposit ? "Deposit" : "Payment"),
            category: category,
            kind: isDeposit
                ? .deposit(fromAddress: entry.fromAddress ?? "")
                : isSettlement
                ? .settlement(toName: entry.recipient?.value1.displayName ?? "")
                : .expense(
                    paidBy: entry.paidBy.map {
                        .init(name: $0.value1.displayName, avatarUrl: $0.value1.avatarUrl)
                    },
                    shareWith: entry.shareWith.map {
                        .init(name: $0.displayName, avatarUrl: $0.avatarUrl)
                    }
                ),
            amount: isIncoming ? amount : -amount,
            currency: isIncoming ? .USD : (vnd != nil ? .VND : .USD),
            time: timeFormatter.string(from: date ?? Date()),
            isAwaitingApproval: entry.needsApproval
        )
    }
}

private extension Components.Schemas.CashDebtDto {
    var pairKey: String { "\(fromUserId)-\(toUserId)" }
}
