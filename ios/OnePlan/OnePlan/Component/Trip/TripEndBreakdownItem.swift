import SwiftUI

/// Classic (non-vault) settlement card — Figma `4013:13084` / `4013:12968`.
///
/// Maps the per-member breakdown into the same expandable card chrome as vault
/// cash debts (`VaultSettlementRow`).
struct TripEndBreakdownItem: View {
    let member: MemberBreakdownDto
    let isCurrentUser: Bool
    let memberAvatarUrls: [String?]
    var currency: Currency = .VND
    var onSettleAll: () async -> Void
    var onShowQR: () -> Void = {}

    @State private var isConfirmSheetPresented = false

    private var entry: VaultSettlementEntry {
        let settled = member.isAllSettled || member.netBalance == 0
        let receiving = member.netBalance > 0
        let amount = settled && member.netBalance == 0
            ? 0
            : abs(member.netBalance != 0 ? member.netBalance : member.totalShare)

        let lines: [VaultSettlementEntry.Line] = member.expenses.map {
            .init(title: $0.expenseName, amount: $0.shareAmount)
        }

        let avatarUrls: [String]
        let extraCount: Int
        if isCurrentUser, receiving, memberAvatarUrls.count > 1 {
            // Figma Group row: stack other members when you are owed by the group.
            avatarUrls = memberAvatarUrls.compactMap { $0 }
            extraCount = max(0, memberAvatarUrls.count - 3)
        } else if let url = member.avatarUrl {
            avatarUrls = [url]
            extraCount = 0
        } else {
            avatarUrls = []
            extraCount = 0
        }

        let name: String
        if isCurrentUser, receiving, memberAvatarUrls.count > 1 {
            name = String(localized: "Group")
        } else {
            name = isCurrentUser ? String(localized: "You") : member.displayName
        }

        return VaultSettlementEntry(
            id: Int(member.userId),
            name: name,
            avatarUrls: avatarUrls,
            extraCount: isCurrentUser && receiving ? max(extraCount, memberAvatarUrls.count > 3 ? memberAvatarUrls.count - 3 : (memberAvatarUrls.count > 1 ? 0 : 0)) : extraCount,
            direction: receiving ? .receiving : .paying,
            amount: amount,
            currency: currency,
            lines: lines,
            state: settled ? .markedDone : .outstanding,
            walletAddress: nil,
            canConfirm: isCurrentUser && !settled
        )
    }

    var body: some View {
        VaultSettlementRow(
            entry: patchedEntry,
            onMarkAsDone: {
                isConfirmSheetPresented = true
            },
            onShowQR: onShowQR
        )
        .sheet(isPresented: $isConfirmSheetPresented) {
            TripEndConfirmBottomSheet(
                amount: abs(member.netBalance),
                isReceiving: member.netBalance > 0,
                onConfirm: {
                    await onSettleAll()
                }
            )
        }
    }

    /// ExtraCount badge: Figma `+3` when more than 3 faces in the group stack.
    private var patchedEntry: VaultSettlementEntry {
        var e = entry
        if isCurrentUser, member.netBalance > 0, memberAvatarUrls.count > 3 {
            e.extraCount = memberAvatarUrls.count - 3
        } else if isCurrentUser, member.netBalance > 0, memberAvatarUrls.count > 1 {
            // Show stack without requiring +N when 2–3 faces.
            e.extraCount = 0
            e.name = String(localized: "Group")
        }
        // Paying / settled zero: Figma shows name only for $0 success peers.
        if member.isAllSettled, member.netBalance == 0, !isCurrentUser {
            e = VaultSettlementEntry(
                id: e.id,
                name: member.displayName,
                avatarUrls: e.avatarUrls,
                extraCount: 0,
                direction: .paying,
                amount: 0,
                currency: currency,
                lines: [],
                state: .markedDone,
                canConfirm: false
            )
        }
        return e
    }
}

#Preview("TripBreakdownItem") {
    let expenses: [BreakdownExpenseItemDto] = [
        BreakdownExpenseItemDto(
            expenseId: 1, expenseName: "Lẩu bò Nhà Gỗ",
            shareAmount: 1_000_000, isSettled: false, shareId: 1
        ),
        BreakdownExpenseItemDto(
            expenseId: 2, expenseName: "Homestay lần 2",
            shareAmount: 300_000, isSettled: false, shareId: 2
        ),
    ]
    let member = MemberBreakdownDto(
        userId: 1,
        displayName: "Ken",
        totalDeposit: 2_500_000,
        totalPaid: 3_000_000,
        totalShare: 1_200_000,
        netBalance: 1_500_000,
        isAllSettled: false,
        expenses: expenses
    )
    TripEndBreakdownItem(
        member: member,
        isCurrentUser: true,
        memberAvatarUrls: [nil, nil, nil, nil],
        onSettleAll: {}
    )
    .padding()
    .background(Constants.Background)
}
