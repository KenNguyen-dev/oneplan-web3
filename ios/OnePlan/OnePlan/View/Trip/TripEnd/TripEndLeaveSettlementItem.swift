//
//  TripEndLeaveSettlementItem.swift
//  OnePlan
//

import SwiftUI

/// Shows the leaving member's settlement card in TripEndBreakdown.
struct TripEndLeaveSettlementItem: View {
    let settlement: LeaveSettlementDto
    let userAvatarUrl: String?
    var currency: Currency = .VND
    let onMarkAsDone: () -> Void

    @State private var isExpanded = true
    @State private var isConfirmSheetPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // Header Row
            HStack(alignment: .center, spacing: 10) {
                memberAvatar

                Text(settlement.displayName)
                    .font(
                        Font.beVietnamPro(16, weight: .medium)
                    )
                    .foregroundColor(Constants.ContentB)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    HStack(alignment: .center, spacing: 3) {
                        Text(currency.symbol)
                            .font(Font.custom("Be Vietnam Pro", size: 18))
                            .foregroundColor(Constants.ContentL)

                        Text(CurrencyFormatter.formatWhole(totalShare))
                            .font(Font.custom("Be Vietnam Pro", size: 18))
                            .foregroundColor(Constants.ContentB)

                        if currency.decimalPlaces > 0 {
                            Text(CurrencyFormatter.formatDecimal(totalShare))
                                .font(Font.custom("Be Vietnam Pro", size: 18))
                                .foregroundColor(Constants.ContentL)
                        }
                    }

                    netBalanceText
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                isExpanded
                                    ? Constants.BlueAlpha16 : Constants.OnSurface
                            )
                        Image(
                            systemName: isExpanded ? "chevron.down" : "chevron.right"
                        )
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(
                            isExpanded ? Constants.BlueBase : Constants.ContentL
                        )
                    }
                    .frame(width: 32, height: 32)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 2)

            // Expanded Content
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    // Budget refund row (at top)
                    if settlement.totalBudgetRefund > 0 {
                        HStack {
                            Text("Total Paid Budget")
                                .font(Font.custom("Be Vietnam Pro", size: 14))
                                .foregroundColor(Constants.ContentB)
                                .frame(maxWidth: .infinity, alignment: .topLeading)

                            Text("+\(CurrencyFormatter.formatWhole(settlement.totalBudgetRefund))\(currency.symbol)")
                                .font(Font.custom("Be Vietnam Pro", size: 14))
                                .multilineTextAlignment(.trailing)
                                .foregroundColor(Constants.Green500)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Constants.Surface)
                        .cornerRadius(24)
                    }

                    // Expense list
                    ForEach(Array(settlement.expenses.enumerated()), id: \.offset) { _, expense in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .center, spacing: 6) {
                                Text(expense.expenseName)
                                    .font(Font.custom("Be Vietnam Pro", size: 14))
                                    .foregroundColor(Constants.ContentB)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)

                                Text("-\(CurrencyFormatter.formatWhole(expense.shareAmount))\(currency.symbol)")
                                    .font(Font.custom("Be Vietnam Pro", size: 14))
                                    .multilineTextAlignment(.trailing)
                                    .foregroundColor(expense.isSettled ? Constants.ContentM : .red)
                            }
                            .padding(.horizontal, 0)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 0)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .background(Constants.Surface)
                        .cornerRadius(24)
                    }

                    // Net balance row
                    if settlement.netSettlement != 0 {
                        settlementRow
                    }

                    // Mark as Done button
                    if !isAllSettled {
                        SecondaryButton(title: "Mark as Done", variant: .dark) {
                            isConfirmSheetPresented = true
                        }
                    }
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.25), value: isExpanded)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Constants.Surface)
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.06), radius: 8.95, x: 0, y: 0)
        .sheet(isPresented: $isConfirmSheetPresented) {
            TripEndConfirmBottomSheet(
                amount: abs(settlement.netSettlement),
                isReceiving: settlement.netSettlement > 0,
                onConfirm: {
                    onMarkAsDone()
                }
            )
        }
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
    }

    // MARK: - Computed Properties

    private var totalShare: Double {
        settlement.expenses.reduce(0) { $0 + $1.shareAmount }
    }

    private var isAllSettled: Bool {
        settlement.expenses.allSatisfy { $0.isSettled } && settlement.netSettlement == 0
    }

    @ViewBuilder
    private var memberAvatar: some View {
        CachedRemoteImage(
            url: userAvatarUrl.flatMap { URL(string: $0) },
            targetSize: CGSize(width: 52, height: 52)
        ) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Image("avatarPlaceholder")
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
        .frame(width: 52, height: 52)
        .clipShape(Circle())
    }

    // MARK: - Subviews

    @ViewBuilder
    private var netBalanceText: some View {
        if isAllSettled {
            Text("All Settled")
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .multilineTextAlignment(.trailing)
                .foregroundColor(Constants.ContentM)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
        } else if settlement.netSettlement > 0 {
            Text("+\(CurrencyFormatter.formatWhole(settlement.netSettlement)) (to receive)")
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .multilineTextAlignment(.trailing)
                .foregroundColor(Constants.Green500)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
        } else if settlement.netSettlement < 0 {
            Text("-\(CurrencyFormatter.formatWhole(abs(settlement.netSettlement))) (to send)")
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .multilineTextAlignment(.trailing)
                .foregroundColor(.red)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
        } else {
            Text("All Settled")
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .multilineTextAlignment(.trailing)
                .foregroundColor(Constants.ContentM)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
        }
    }

    private var settlementRow: some View {
        let isReceiving = settlement.netSettlement > 0
        let absAmount = abs(settlement.netSettlement)

        return HStack(alignment: .center, spacing: 6) {
            ZStack {
                Circle()
                    .fill(Constants.BlueAlpha16)
                Image(systemName: "person.2.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Constants.BlueBase)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(isReceiving ? String(localized: "Receive from group") : String(localized: "Pay to group"))
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundColor(Constants.ContentB)
                    .lineLimit(1)

                HStack(alignment: .center, spacing: 3) {
                    Text("\(isReceiving ? "+" : "-")\(currency.symbol)")
                        .font(Font.custom("Be Vietnam Pro", size: 16))
                        .foregroundColor(Constants.ContentL)

                    Text(CurrencyFormatter.formatWhole(absAmount))
                        .font(
                            Font.beVietnamPro(16, weight: .medium)
                        )
                        .foregroundColor(Constants.ContentB)

                    Text(CurrencyFormatter.formatDecimal(absAmount))
                        .font(Font.custom("Be Vietnam Pro", size: 16))
                        .foregroundColor(Constants.ContentL)
                }
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        isReceiving
                            ? Color(red: 0.82, green: 0.95, blue: 0.89)
                            : Color(red: 0.95, green: 0.82, blue: 0.82)
                    )

                Image(systemName: isReceiving ? "tray.and.arrow.down" : "tray.and.arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(
                        isReceiving
                            ? Color(red: 0.62, green: 0.88, blue: 0.76)
                            : Color(red: 0.88, green: 0.62, blue: 0.62)
                    )
            }
            .frame(width: 40, height: 40)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 63, alignment: .leading)
        .background(
            isReceiving
                ? Color(red: 0.95, green: 0.98, blue: 0.97)
                : Color(red: 0.98, green: 0.95, blue: 0.95)
        )
        .cornerRadius(16)
    }
}

#Preview {
    TripEndLeaveSettlementItem(
        settlement: LeaveSettlementDto(
            displayName: "Ken",
            totalBudgetRefund: 500_000,
            totalExpenseShare: 200_000,
            netSettlement: 300_000,
            expenses: [
                LeaveSettlementExpenseDto(
                    expenseName: "Dinner at restaurant",
                    shareAmount: 150_000,
                    isSettled: false
                ),
                LeaveSettlementExpenseDto(
                    expenseName: "Taxi ride",
                    shareAmount: 50_000,
                    isSettled: true
                )
            ]
        ),
        userAvatarUrl: nil as String?,
        onMarkAsDone: {}
    )
    .padding(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    .background(Constants.Background)
}
