import SwiftUI

/// One party in the end-of-trip settlement.
struct VaultSettlementEntry: Identifiable, Equatable {
    enum Direction: Equatable {
        /// This person owes the current user.
        case receiving
        /// The current user owes this person.
        case paying
    }

    enum State: Equatable {
        case outstanding
        /// Settled off-chain, by someone tapping Mark as done.
        case markedDone
        /// Settled on chain. Carries the transaction signature.
        case sentOnChain(signature: String)
    }

    struct Line: Equatable {
        var title: String
        var amount: Double
        /// When set (vault cash debts), shown beside VND for transfer clarity.
        var amountUsdc: Double? = nil
    }

    let id: Int
    var name: String
    var avatarUrls: [String]
    /// Extra faces beyond the ones shown, as in the group row.
    var extraCount: Int
    var direction: Direction
    var amount: Double
    var currency: Currency
    /// Vault cash debts: USDC face value for Send / dual display.
    var amountUsdc: Double? = nil
    var lines: [Line]
    var state: State
    /// Present only when the member has linked an embedded wallet, which is what
    /// makes an on-chain transfer possible at all.
    var walletAddress: String?
    /// Creditor may confirm receipt (Mark as done).
    var canConfirm: Bool = false
}

/// Expandable settlement card — Figma `4013:13084` / `4013:12968`.
struct VaultSettlementRow: View {
    let entry: VaultSettlementEntry
    var onMarkAsDone: () async -> Void = {}
    var onShowQR: () -> Void = {}
    var onSendToWallet: () async -> Void = {}

    @State private var isExpanded = false
    @State private var isWorking = false

    private var isSettled: Bool {
        switch entry.state {
        case .outstanding: false
        case .markedDone, .sentOnChain: true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isExpanded {
                expandedBody
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(8)
        .background(Constants.Surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.09), radius: 8.95)
        .animation(.snappy(duration: 0.22), value: isExpanded)
    }

    private var header: some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                avatarBlock

                VStack(alignment: .leading, spacing: 2) {
                    if showsDirectionLabel {
                        Text(directionLabel)
                            .font(Font.beVietnamPro(14))
                            .tracking(-0.28)
                            .foregroundStyle(Constants.Neutral700)
                    }
                    Text(displayName)
                        .font(Font.beVietnamPro(16, weight: .medium))
                        .tracking(-0.32)
                        .foregroundStyle(Constants.ContentB)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 2) {
                    amountText
                    if isSettled {
                        Text("Success")
                            .font(Font.beVietnamPro(14))
                            .tracking(-0.28)
                            .foregroundStyle(Constants.ContentM)
                    }
                }

                trailingBadge
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var expandedBody: some View {
        VStack(spacing: 0) {
            if !entry.lines.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(entry.lines.enumerated()), id: \.offset) { index, line in
                        if index > 0 {
                            Divider()
                        }
                        HStack(spacing: 6) {
                            Text(line.title)
                                .font(Font.beVietnamPro(14))
                                .tracking(-0.7)
                                .foregroundStyle(Constants.ContentB)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 2) {
                                if let usdc = line.amountUsdc {
                                    Text(
                                        CurrencyFormatter.formatUsdc(usdc) + " USDC"
                                    )
                                    .font(Font.beVietnamPro(16))
                                    .tracking(-0.32)
                                    .foregroundStyle(Constants.ContentB)
                                    Text(lineAmount(line.amount))
                                        .font(Font.beVietnamPro(13))
                                        .tracking(-0.26)
                                        .foregroundStyle(Constants.ContentM)
                                } else {
                                    Text(lineAmount(line.amount))
                                        .font(Font.beVietnamPro(16))
                                        .tracking(-0.32)
                                        .foregroundStyle(Constants.ContentB)
                                }
                            }
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 4)
                    }
                }
            }

            if !isSettled {
                actionButtons
                    .padding(.top, entry.lines.isEmpty ? 8 : 4)
                    .padding(.bottom, 4)
            }
            // Settled: Success + checkmark only — no Send (debt already confirmed).
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if entry.direction == .receiving {
            // Figma `4575:2150`: Mark as done (black) + Show QR (BlueBase #335cff).
            HStack(spacing: 6) {
                Button {
                    Task { await run(onMarkAsDone) }
                } label: {
                    actionLabel(
                        isWorking ? nil : "Mark as done",
                        foreground: Constants.White
                    )
                    .background(Constants.Black, in: Capsule())
                }
                .disabled(isWorking || !entry.canConfirm)
                .opacity(entry.canConfirm ? 1 : 0.45)

                Button(action: onShowQR) {
                    actionLabel("Show QR", foreground: Constants.White)
                        .background(Constants.BlueBase, in: Capsule())
                }
                .disabled(isWorking)
            }
        } else if entry.walletAddress != nil {
            sendButton
        } else if entry.canConfirm {
            // Classic trip-end: settle your shares even when net is to pay.
            Button {
                Task { await run(onMarkAsDone) }
            } label: {
                actionLabel(
                    isWorking ? nil : "Mark as done",
                    foreground: Constants.White
                )
                .background(Constants.Black, in: Capsule())
            }
            .disabled(isWorking)
        } else {
            Text("Waiting for \(entry.name) to confirm")
                .font(Font.beVietnamPro(13))
                .foregroundStyle(Constants.ContentM)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        }
    }

    private var sendButton: some View {
        Button {
            Task { await run(onSendToWallet) }
        } label: {
            actionLabel(
                isWorking ? nil : "Send",
                foreground: Constants.White
            )
            .background(Constants.BlueBase, in: Capsule())
        }
        .disabled(isWorking)
    }

    private func actionLabel(
        _ title: LocalizedStringKey?,
        foreground: Color
    ) -> some View {
        Group {
            if let title {
                Text(title)
                    .font(Font.beVietnamPro(15))
                    .tracking(-0.75)
                    .foregroundStyle(foreground)
            } else {
                ProgressView().tint(foreground)
            }
        }
        // Figma Button XL: `px-20` / `py-12` — no extra minHeight (was 46).
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var trailingBadge: some View {
        if isSettled {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Constants.White)
                .frame(width: 32, height: 32)
                .background(Constants.BlueBase, in: Circle())
        } else {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Constants.ContentL)
                .frame(width: 32, height: 32)
                .background(Constants.OnSurface, in: Circle())
        }
    }

    private var avatarBlock: some View {
        Group {
            if entry.extraCount > 0 || entry.avatarUrls.count > 1 {
                avatarStack
            } else {
                singleAvatar(entry.avatarUrls.first)
            }
        }
        .frame(width: 52, height: 52)
    }

    private var avatarStack: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(entry.avatarUrls.prefix(3).enumerated()), id: \.offset) { index, url in
                avatar(url, size: 29)
                    .overlay(Circle().stroke(Constants.White, lineWidth: 2.6))
                    .offset(x: stackOffsets[index].x, y: stackOffsets[index].y)
            }
            if entry.extraCount > 0 {
                Text("+\(entry.extraCount)")
                    .font(Font.beVietnamPro(10, weight: .semibold))
                    .foregroundStyle(Constants.White)
                    .frame(width: 21, height: 21)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.34, green: 1, blue: 0.49),
                                Color(red: 0.01, green: 0.58, blue: 0),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        in: Circle()
                    )
                    .overlay(Circle().stroke(Constants.White, lineWidth: 1.5))
                    .offset(x: 26, y: 20)
            }
        }
        .frame(width: 52, height: 52, alignment: .topLeading)
    }

    private var stackOffsets: [(x: CGFloat, y: CGFloat)] {
        [(0, 5.7), (23, 0), (7, 23)]
    }

    private func singleAvatar(_ urlString: String?) -> some View {
        avatar(urlString, size: 52)
            .overlay(
                Circle()
                    .stroke(Constants.White.opacity(0.9), lineWidth: 0)
                    .shadow(color: .white.opacity(0.8), radius: 2)
            )
    }

    private func avatar(_ urlString: String?, size: CGFloat) -> some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                CachedRemoteImage(url: url, targetSize: CGSize(width: size, height: size)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle().fill(Constants.Neutral200)
                }
            } else {
                ZStack {
                    Circle().fill(Constants.Neutral200)
                    Text(String(entry.name.prefix(1)).uppercased())
                        .font(Font.beVietnamPro(size > 40 ? 18 : 11))
                        .foregroundStyle(Constants.ContentM)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var amountText: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let usdc = entry.amountUsdc {
                HStack(spacing: 3) {
                    Text(CurrencyFormatter.formatUsdc(usdc))
                        .foregroundStyle(Constants.ContentB)
                    Text("USDC")
                        .foregroundStyle(Constants.ContentL)
                }
                .font(Font.beVietnamPro(18))
                .tracking(-0.36)

                HStack(spacing: 3) {
                    Text(entry.currency.symbol)
                        .foregroundStyle(Constants.ContentL)
                    Text(CurrencyFormatter.formatWhole(entry.amount))
                        .foregroundStyle(Constants.ContentM)
                }
                .font(Font.beVietnamPro(14))
                .tracking(-0.28)
            } else {
                HStack(spacing: 3) {
                    Text(entry.currency.symbol)
                        .foregroundStyle(Constants.ContentL)
                    Text(CurrencyFormatter.formatWhole(entry.amount))
                        .foregroundStyle(Constants.ContentB)
                    if entry.currency.decimalPlaces > 0 {
                        Text(CurrencyFormatter.formatDecimal(entry.amount))
                            .foregroundStyle(Constants.ContentL)
                    }
                }
                .font(Font.beVietnamPro(18))
                .tracking(-0.36)
            }
        }
    }

    private func lineAmount(_ amount: Double) -> String {
        // Figma line amounts: `1,000,000đ` (symbol after).
        CurrencyFormatter.formatWhole(amount) + entry.currency.symbol
    }

    private var showsDirectionLabel: Bool {
        // Zero-balance settled peers show only the name (Figma `hmy` row).
        !(isSettled && entry.amount == 0)
    }

    /// Figma: collapsed `Nhận từ` / `Chuyển cho`; expanded receive `Bạn nhận từ`.
    private var directionLabel: String {
        if entry.direction == .receiving {
            return isExpanded
                ? String(localized: "Bạn nhận từ")
                : String(localized: "Nhận từ")
        }
        return String(localized: "Chuyển cho")
    }

    private var displayName: String {
        if let wallet = entry.walletAddress, entry.direction == .paying {
            return "\(entry.name) (\(Self.shorten(wallet)))"
        }
        return entry.extraCount > 0 ? String(localized: "Group") : entry.name
    }

    private func run(_ action: () async -> Void) async {
        isWorking = true
        defer { isWorking = false }
        await action()
    }

    private static func shorten(_ address: String) -> String {
        guard address.count > 10 else { return address }
        return "\(address.prefix(4))...\(address.suffix(4))"
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 8) {
            VaultSettlementRow(
                entry: VaultSettlementEntry(
                    id: 1, name: "Group",
                    avatarUrls: ["", "", ""],
                    extraCount: 3,
                    direction: .receiving, amount: 500_000, currency: .VND,
                    lines: [],
                    state: .outstanding, canConfirm: true
                )
            )
            VaultSettlementRow(
                entry: VaultSettlementEntry(
                    id: 2, name: "Hyydesi", avatarUrls: [], extraCount: 0,
                    direction: .receiving, amount: 1_500_000, currency: .VND,
                    lines: [
                        .init(title: "Lẩu bò Nhà Gỗ", amount: 1_000_000),
                        .init(title: "Homestay lần 2", amount: 300_000),
                        .init(title: "Homestay lần 2", amount: 200_000),
                    ],
                    state: .outstanding, canConfirm: true
                )
            )
            VaultSettlementRow(
                entry: VaultSettlementEntry(
                    id: 3, name: "Shin", avatarUrls: [], extraCount: 0,
                    direction: .paying, amount: 700_000, currency: .VND,
                    lines: [.init(title: "Lẩu bò Nhà Gỗ", amount: 1_000_000)],
                    state: .markedDone,
                    walletAddress: "0xd3ade7deadbeef"
                )
            )
        }
        .padding(16)
    }
    .background(Constants.Background)
}
