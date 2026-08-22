import SwiftUI

/// Deposits and payments for the trip vault, newest first.
///
/// Separate from the trip's expense history because it shows what the wallet
/// did, including deposits, which never become expenses and so appear nowhere
/// else.
///
/// When `embedsInParentScroll` is true the list is a plain stack for a parent
/// `ScrollView` (trip-end History tab). Standalone use keeps its own scroll.
struct VaultHistoryView: View {
    let tripId: Int
    var members: [TripMemberDto] = []
    /// False on trip-end — server rejects spend edits after the trip ends.
    var allowsEditing: Bool = true
    var onSendAgain: (String) -> Void = { _ in }
    /// Omit the outer `ScrollView` so trip-end can nest this under hero / plan.
    var embedsInParentScroll: Bool = false

    @State private var vault = TripVaultService.shared
    @State private var entries: [Components.Schemas.VaultHistoryEntryDto] = []
    @State private var selected: Components.Schemas.VaultTransactionDetailDto?
    /// History row title; DTO may lag the `name` field until Client regenerates.
    @State private var selectedName: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            // Only the first load gets a spinner. A reload after a payment
            // replaces a list that is already right apart from one new row, and
            // blanking it to a spinner reads as the screen having lost its data.
            if isLoading && entries.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, embedsInParentScroll ? 24 : 0)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: embedsInParentScroll ? nil : .infinity
                    )
            } else if entries.isEmpty {
                empty
            } else if embedsInParentScroll {
                listStack
            } else {
                ScrollView { listStack.padding(16) }
            }
        }
        .background(embedsInParentScroll ? Color.clear : Constants.Background)
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .vaultBalanceChanged)) { note in
            if let id = note.userInfo?["tripId"] as? Int, id != tripId { return }
            Task { await load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .vaultSettlementUpdated)) { note in
            if let id = note.userInfo?["tripId"] as? Int, id != tripId { return }
            Task { await load() }
        }
        .sheet(item: $selected) { detail in
            VaultTransactionDetailView(
                detail: map(detail, fallbackName: selectedName),
                tripId: tripId,
                vaultTransactionId: detail.id,
                members: members,
                allowsEditing: allowsEditing,
                onBack: { selected = nil },
                onSendAgain: detail.qrPayload.map { payload in
                    { onSendAgain(payload) }
                },
                onApprove: detail.canApprove
                    ? { await approve(vaultTransactionId: detail.id) }
                    : nil,
                onCancel: detail.canCancel
                    ? { await cancel(vaultTransactionId: detail.id) }
                    : nil,
                onEdited: { updated, savedName in
                    selected = updated
                    selectedName = savedName
                    Task { await load() }
                }
            )
        }
        .alert(
            "Could not load history",
            isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(errorMessage ?? "") }
        )
    }

    private var empty: some View {
        VStack(spacing: 4) {
            Text("No history")
                .font(Font.beVietnamPro(16))
                .foregroundStyle(Constants.ContentB)
            Text("Deposit USDC or pay a merchant to get started")
                .font(Font.beVietnamPro(14))
                .foregroundStyle(Constants.ContentM)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, embedsInParentScroll ? 24 : 0)
        .frame(
            maxWidth: .infinity,
            maxHeight: embedsInParentScroll ? nil : .infinity
        )
    }

    private var listStack: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(days, id: \.key) { day in
                HStack {
                    Text(day.title)
                        .font(Font.beVietnamPro(14))
                        .tracking(-0.28)
                        .foregroundStyle(Constants.ContentM)
                    Spacer(minLength: 8)
                    if let total = dayTotalLabel(for: day.entries) {
                        Text(total)
                            .font(Font.beVietnamPro(14))
                            .tracking(-0.28)
                            .foregroundStyle(Constants.ContentM)
                    }
                }

                VStack(spacing: 2) {
                    ForEach(Array(day.entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Divider().foregroundStyle(Constants.DividerStroke)
                        }
                        VaultHistoryRow(entry: map(entry)) {
                            Task { await open(entry) }
                        }
                    }
                }
                .padding(.horizontal, 4)
                .background(
                    Constants.Surface,
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                )
            }
        }
    }

    /// One card per day, newest first, the way the design lays the list out.
    ///
    /// The server already returns newest first, so the days come out in order
    /// from a single pass — sorting again would only risk disagreeing with it.
    private struct Day {
        let key: String
        let title: String
        var entries: [Components.Schemas.VaultHistoryEntryDto]
    }

    private var days: [Day] {
        var result: [Day] = []
        for entry in entries {
            let date = parse(entry.createdAt)
            let key = Self.dayKeyFormatter.string(from: date)
            if result.last?.key == key {
                result[result.count - 1].entries.append(entry)
            } else {
                result.append(Day(key: key, title: Self.dayTitle(for: date), entries: [entry]))
            }
        }
        return result
    }

    private static func dayTitle(for date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? String(localized: "Today")
            : dayTitleFormatter.string(from: date)
    }

    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let dayTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()

    /// Day header total in the dominant unit (VND spends, else USDC), Figma-style.
    private func dayTotalLabel(
        for dayEntries: [Components.Schemas.VaultHistoryEntryDto]
    ) -> String? {
        var spendVnd: Double = 0
        var netUsdc: Double = 0
        var hasVnd = false
        for entry in dayEntries {
            let usdc = Double(UInt64(entry.amountMicro) ?? 0) / 1_000_000
            let isIncoming = entry.kind == "DEPOSIT" || entry.kind == "SETTLEMENT"
            if isIncoming {
                netUsdc += usdc
            } else if let vnd = entry.amountVnd.flatMap({ Double($0) }) {
                spendVnd += vnd
                hasVnd = true
            } else {
                netUsdc -= usdc
            }
        }
        if hasVnd, spendVnd > 0 {
            return "-\(CurrencyFormatter.formatWhole(spendVnd))₫"
        }
        if netUsdc != 0 {
            let sign = netUsdc > 0 ? "+" : "-"
            return "\(sign)\(CurrencyFormatter.formatUsdc(abs(netUsdc)))"
        }
        return nil
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await vault.loadHistory(tripId: tripId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Only a payment has a receipt. A deposit is a transfer in with nothing
    /// more to say about it than the row already shows.
    private func open(_ entry: Components.Schemas.VaultHistoryEntryDto) async {
        guard entry.kind == "SPEND" else { return }
        // Includes a payment still waiting on approval: the receipt is where the
        // approve button lives, so it has to be reachable.
        do {
            selected = try await vault.transactionDetail(
                tripId: tripId,
                vaultTransactionId: entry.id
            )
            selectedName = entry.title ?? defaultTitle(for: entry.kind)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func map(
        _ entry: Components.Schemas.VaultHistoryEntryDto
    ) -> VaultHistoryEntry {
        let usdc = Double(UInt64(entry.amountMicro) ?? 0) / 1_000_000
        let vnd = entry.amountVnd.flatMap { Double($0) }
        let isDeposit = entry.kind == "DEPOSIT"
        let isSettlement = entry.kind == "SETTLEMENT"
        // Both hand USDC to a member rather than taking it from the group, so
        // both read as money in, and neither has a dong side.
        let isIncoming = isDeposit || isSettlement
        let category = entry.category
            .flatMap { CategoryChip.Category(apiValue: $0.value1.rawValue) } ?? .other

        // A payment is shown in dong because dong is what the merchant was
        // handed; the USDC figure is the vault's side of the same transfer and
        // belongs on the receipt, not here. A deposit has no dong side at all.
        let amount = isIncoming ? usdc : (vnd ?? usdc)

        return VaultHistoryEntry(
            id: entry.id,
            title: entry.title ?? defaultTitle(for: entry.kind),
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
            // Money in is positive, money out negative, which is how the row
            // decides its sign.
            amount: isIncoming ? amount : -amount,
            currency: isIncoming ? .USD : (vnd != nil ? .VND : .USD),
            time: Self.timeFormatter.string(from: parse(entry.createdAt)),
            // A spend still PENDING has not left the vault. Only a spend: a
            // pending deposit is money already sent, waiting on the chain.
            isAwaitingApproval: entry.needsApproval
        )
    }

    /// Adds the viewer's signature, which is the one that moves the money.
    private func approve(vaultTransactionId: Int) async {
        do {
            let outcome = try await vault.approve(
                tripId: tripId,
                vaultTransactionId: vaultTransactionId
            )
            switch outcome {
            case .confirmed(let id):
                // Refresh the same receipt so the approver sees the paid state
                // rather than being bounced back to the list.
                selected = try await vault.transactionDetail(
                    tripId: tripId,
                    vaultTransactionId: id
                )
                await load()
            case .pending, .awaitingApproval:
                selected = nil
                await load()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancel(vaultTransactionId: Int) async {
        do {
            try await vault.cancel(
                tripId: tripId,
                vaultTransactionId: vaultTransactionId
            )
            selected = nil
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func map(
        _ detail: Components.Schemas.VaultTransactionDetailDto,
        fallbackName: String = ""
    ) -> VaultTransactionDetail {
        VaultTransactionDetailView.map(detail, fallbackName: fallbackName)
    }

    private func defaultTitle(for kind: String) -> String {
        switch kind {
        case "DEPOSIT": return String(localized: "Deposit USDC")
        case "SETTLEMENT": return String(localized: "Settlement")
        case "REVERT": return String(localized: "Refund")
        default: return String(localized: "Payment")
        }
    }

    private func parse(_ iso: String) -> Date {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: iso) { return date }
        return ISO8601DateFormatter().date(from: iso) ?? Date()
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

extension Components.Schemas.VaultTransactionDetailDto: @retroactive Identifiable {}
