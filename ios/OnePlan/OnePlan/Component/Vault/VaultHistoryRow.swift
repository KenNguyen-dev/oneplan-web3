import SwiftUI

/// One line in the vault history.
///
/// Covers both an expense paid out of the vault and a deposit paid in, because
/// they sit in the same list and a member reading it does not think of them as
/// different kinds of thing.
struct VaultHistoryEntry: Identifiable, Equatable {
    /// Someone named on a row. The avatar is optional because a member who has
    /// never set one still has to appear in the chip — the design shows a face
    /// for every sharer, so a missing image becomes a default, not a gap.
    struct Person: Equatable {
        let name: String
        let avatarUrl: String?
    }

    enum Kind: Equatable {
        /// Money left the vault. `paidBy` is nil when the group paid.
        case expense(paidBy: Person?, shareWith: [Person])
        /// Money entered the vault, from the wallet shown.
        case deposit(fromAddress: String)
        /// The vault paid a member back when the trip wound up. Not an expense:
        /// nobody paid for it and nobody shares it, so it carries no chips.
        case settlement(toName: String)
    }

    let id: Int
    var title: String
    var category: CategoryChip.Category
    var kind: Kind
    /// Negative for money out, positive for money in.
    var amount: Double
    var currency: Currency
    var time: String
    /// True while the money is still in the vault — a payment over the trip's
    /// limit that no second member has approved yet. The row has to say so, or
    /// an unmoved balance next to a normal looking entry reads as a bug. Not the
    /// same as a pending payout, where the money has already gone.
    var isAwaitingApproval: Bool = false
}

struct VaultHistoryRow: View {
    let entry: VaultHistoryEntry
    var onTap: () -> Void = {}
    /// Figma confirmation/end-trip review: expenses use Secondary red.
    var emphasizesSignedAmount: Bool = false
    /// Leave sheet (Figma 4711:1772): outline "All" chip instead of solid blue.
    var usesOutlinedAllChip: Bool = false
    /// Leave sheet: `-355,000đ` (symbol after) instead of `-đ355,000`.
    var placesCurrencySymbolAfter: Bool = false

    private enum Metrics {
        static let avatar: CGFloat = 18
        /// The faces sit on top of one another, so the second starts before the
        /// first has finished.
        static let avatarOverlap: CGFloat = -7
        static let iconTile: CGFloat = 40
        static let icon: CGFloat = 32
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                icon

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(Font.beVietnamPro(15))
                        .tracking(-0.3)
                        .foregroundStyle(Constants.ContentB)
                        .lineLimit(1)

                    subtitle
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(amountText)
                        .font(Font.beVietnamPro(16))
                        .tracking(-0.32)
                        .foregroundStyle(amountColor)
                        .lineLimit(1)

                    Text(
                        entry.isAwaitingApproval
                            ? String(localized: "Needs approval")
                            : entry.time
                    )
                    .font(Font.beVietnamPro(14))
                    .tracking(-0.28)
                    .foregroundStyle(
                        entry.isAwaitingApproval ? Constants.Warning500 : Constants.ContentM
                    )
                    .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var icon: some View {
        Group {
            switch entry.kind {
            case .deposit, .settlement:
                // Neither has a category to illustrate, and both are the vault
                // moving money between wallets, so both get the coin.
                Image("catDeposit")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: Metrics.icon, height: Metrics.icon)
            case .expense:
                CategoryIcon(category: entry.category, size: Metrics.icon)
            }
        }
        .frame(width: Metrics.iconTile, height: Metrics.iconTile)
        .background(
            Constants.OnSurface,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    @ViewBuilder
    private var subtitle: some View {
        switch entry.kind {
        case .deposit(let address):
            Text(Self.shorten(address))
                .font(Font.beVietnamPro(14))
                .tracking(-0.28)
                .foregroundStyle(Constants.ContentM)

        case .settlement(let name):
            Text("Paid back to \(name)")
                .font(Font.beVietnamPro(14))
                .tracking(-0.28)
                .foregroundStyle(Constants.ContentM)

        case .expense(let paidBy, let shareWith):
            HStack(spacing: 4) {
                // Vault spends are always paid by the group (paidBy is null from
                // the API). Only show a payer chip when a named person paid —
                // never the redundant orange "Group" label.
                if let paidBy {
                    payerChip(paidBy)
                }
                shareChip(shareWith)
            }
        }
    }

    /// Who the money came from. Vault spends leave this nil (group paid); only
    /// a named person produces a chip.
    @ViewBuilder
    private func payerChip(_ payer: VaultHistoryEntry.Person) -> some View {
        HStack(spacing: 3) {
            avatar(payer.avatarUrl, name: payer.name)
            chipLabel(payer.name, color: Constants.DividerStroke)
        }
        .padding(.leading, 2)
        .padding(.trailing, 8)
        .padding(.vertical, 2)
        .background(Constants.Warning500, in: Capsule())
    }

    /// Shows a couple of faces and a count rather than every name: the row has
    /// to stay one line however many people share the expense.
    @ViewBuilder
    private func shareChip(_ people: [VaultHistoryEntry.Person]) -> some View {
        if people.isEmpty {
            // An empty share list is how the vault says everyone.
            if usesOutlinedAllChip {
                chipLabel(String(localized: "All"), color: Constants.ContentB)
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
                    .padding(.bottom, 3)
                    .overlay(Capsule().stroke(Constants.Neutral100, lineWidth: 1))
            } else {
                chipLabel(String(localized: "All"), color: Constants.White)
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
                    .padding(.bottom, 3)
                    .background(Constants.BlueBase, in: Capsule())
            }
        } else {
            let shown = Array(people.prefix(2))
            let remainder = people.count - shown.count

            HStack(spacing: 4) {
                HStack(spacing: Metrics.avatarOverlap) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { index, person in
                        avatar(person.avatarUrl, name: person.name)
                            .zIndex(Double(shown.count - index))
                    }
                }
                chipLabel(
                    remainder > 0 ? "+\(remainder)" : shown[0].name,
                    color: Constants.White
                )
            }
            .padding(.leading, 2)
            .padding(.trailing, 5)
            .padding(.vertical, 2)
            .background(Constants.BlueBase, in: Capsule())
        }
    }

    private func chipLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Font.beVietnamPro(14))
            .tracking(-0.28)
            .foregroundStyle(color)
            .lineLimit(1)
    }

    /// The white ring separates two overlapping avatars from one another.
    private func avatar(_ urlString: String?, name: String) -> some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                CachedRemoteImage(
                    url: url,
                    targetSize: CGSize(width: Metrics.avatar, height: Metrics.avatar)
                ) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    initialAvatar(name)
                }
            } else {
                initialAvatar(name)
            }
        }
        .frame(width: Metrics.avatar, height: Metrics.avatar)
        .clipShape(Circle())
        .overlay(Circle().stroke(Constants.White, lineWidth: 1))
    }

    private func initialAvatar(_ name: String) -> some View {
        Text(String(name.prefix(1)).uppercased())
            .font(Font.beVietnamPro(9))
            .foregroundStyle(Constants.ContentM)
            .frame(width: Metrics.avatar, height: Metrics.avatar)
            .background(Constants.Neutral200)
    }

    private var amountColor: Color {
        if entry.isAwaitingApproval { return Constants.ContentL }
        if emphasizesSignedAmount, entry.amount < 0 { return Constants.Secondary }
        return Constants.ContentB
    }

    private var amountText: String {
        let sign = entry.amount < 0 ? "-" : "+"
        let magnitude = abs(entry.amount)
        // Deposits/settlements are USDC — use the vault formatter, not the
        // 2-decimal fiat split that turns 0.999 into "$0.100".
        if entry.currency == .USD {
            return sign + entry.currency.symbol + CurrencyFormatter.formatUsdc(magnitude)
        }
        if placesCurrencySymbolAfter {
            let whole = CurrencyFormatter.formatWhole(magnitude)
            let decimals =
                entry.currency.decimalPlaces > 0
                ? CurrencyFormatter.formatDecimal(magnitude)
                : ""
            return "\(sign)\(whole)\(decimals)\(entry.currency.symbol)"
        }
        return sign
            + CurrencyFormatter.format(
                magnitude,
                currency: entry.currency,
                showDecimals: entry.currency.decimalPlaces > 0
            )
    }

    /// `0xd3...ade7` style, matching how the address is shown on the deposit
    /// screen: the ends are what identify it.
    private static func shorten(_ address: String) -> String {
        guard address.count > 10 else { return address }
        return "\(address.prefix(4))...\(address.suffix(4))"
    }
}

#Preview {
    VStack(spacing: 2) {
        VaultHistoryRow(
            entry: VaultHistoryEntry(
                id: 1,
                title: "Coffee",
                category: .coffee,
                kind: .expense(
                    paidBy: .init(name: "Cattie", avatarUrl: nil),
                    shareWith: [
                        .init(name: "Nam", avatarUrl: nil),
                        .init(name: "Hyy", avatarUrl: nil),
                        .init(name: "An", avatarUrl: nil),
                        .init(name: "Bi", avatarUrl: nil),
                    ]
                ),
                amount: -500_000,
                currency: .VND,
                time: "08:18"
            )
        )
        Divider()
        VaultHistoryRow(
            entry: VaultHistoryEntry(
                id: 2,
                title: "Homestay",
                category: .stay,
                kind: .expense(paidBy: nil, shareWith: []),
                amount: -5_000_000,
                currency: .VND,
                time: "12:03"
            )
        )
        Divider()
        VaultHistoryRow(
            entry: VaultHistoryEntry(
                id: 3,
                title: "Deposit USDC",
                category: .other,
                kind: .deposit(fromAddress: "8pjmDZvmRzjcSwzffqnsdzsPRb3nV9BiVDhGU3vmR7uD"),
                amount: 100,
                currency: .USD,
                time: "08:10"
            )
        )
    }
    .padding(.horizontal, 4)
    .background(Constants.Surface, in: RoundedRectangle(cornerRadius: 24))
    .padding(16)
    .background(Constants.Background)
}
