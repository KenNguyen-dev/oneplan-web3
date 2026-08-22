//
//  LeaveTripBottomSheet.swift
//  OnePlan
//
//  Created by Codex on 12/4/26.
//

import SwiftUI

struct LeaveTripBottomSheet: View {
    @Environment(\.dismiss) private var dismiss

    let preview: LeavePreviewDto
    var currency: Currency = .VND
    let isLeaving: Bool
    let onLeave: () async -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Leave Trip")
                    .font(
                        Font.beVietnamPro(18, weight: .semibold)
                    )
                    .foregroundColor(Constants.ContentB)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Constants.OnSurface)
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Constants.ContentM)
                    }
                    .frame(width: 43, height: 43)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !preview.budgets.isEmpty {
                        budgetSection
                    }

                    expenseSection

                    Text("You will no longer have access to this trip's plans, expenses, and photos.")
                        .font(Font.custom("Be Vietnam Pro", size: 13))
                        .foregroundColor(Constants.ContentM)
                        .padding(.horizontal, 4)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }

            Spacer()

            Button {
                Task {
                    await onLeave()
                }
            } label: {
                if isLeaving {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                } else {
                    Text("Confirm Leave")
                        .font(
                            Font.beVietnamPro(16, weight: .medium)
                        )
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
            }
            .disabled(isLeaving)
            .background(Color.red)
            .cornerRadius(.infinity)
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Constants.Background)
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Budget Section

    @ViewBuilder
    private var budgetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Budget Contributions")
                .font(
                    Font.beVietnamPro(14, weight: .medium)
                )
                .foregroundColor(Constants.ContentB)

            VStack(spacing: 6) {
                ForEach(Array(preview.budgets.enumerated()), id: \.offset) { _, budget in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(budget.budgetName)
                                .font(Font.custom("Be Vietnam Pro", size: 14))
                                .foregroundColor(Constants.ContentB)

                            Text(budget.isPaid ? String(localized: "Paid") : String(localized: "Unpaid"))
                                .font(Font.custom("Be Vietnam Pro", size: 12))
                                .foregroundColor(budget.isPaid ? Constants.Green500 : Constants.ContentM)
                        }

                        Spacer()

                        if budget.refundAmount > 0 {
                            Text("+\(CurrencyFormatter.formatWhole(budget.refundAmount))\(currency.symbol)")
                                .font(Font.custom("Be Vietnam Pro", size: 14))
                                .foregroundColor(Constants.Green500)
                        } else {
                            Text("\(CurrencyFormatter.formatWhole(budget.amount))\(currency.symbol)")
                                .font(Font.custom("Be Vietnam Pro", size: 14))
                                .foregroundColor(Constants.ContentM)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Constants.Surface)
                    .cornerRadius(12)
                }
            }

            if preview.totalBudgetRefund > 0 {
                HStack {
                    Text("Total")
                        .font(
                            Font.beVietnamPro(14, weight: .medium)
                        )
                        .foregroundColor(Constants.ContentB)

                    Spacer()

                    Text("+\(CurrencyFormatter.formatWhole(preview.totalBudgetRefund))\(currency.symbol)")
                        .font(
                            Font.beVietnamPro(14, weight: .medium)
                        )
                        .foregroundColor(Constants.Green500)
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(Constants.OnSurface)
        .cornerRadius(16)
    }

    // MARK: - Settlement Section

    @ViewBuilder
    private var expenseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settlement Summary")
                .font(
                    Font.beVietnamPro(14, weight: .medium)
                )
                .foregroundColor(Constants.ContentB)

            VStack(spacing: 6) {
                if preview.totalBudgetRefund > 0 {
                    HStack {
                        Text("Budget contributed")
                            .font(Font.custom("Be Vietnam Pro", size: 14))
                            .foregroundColor(Constants.ContentB)

                        Spacer()

                        Text("+\(CurrencyFormatter.formatWhole(preview.totalBudgetRefund))\(currency.symbol)")
                            .font(Font.custom("Be Vietnam Pro", size: 14))
                            .foregroundColor(Constants.Green500)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Constants.Surface)
                    .cornerRadius(12)
                }

                HStack {
                    Text("Your expense share")
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .foregroundColor(Constants.ContentB)

                    Spacer()

                    Text("-\(CurrencyFormatter.formatWhole(preview.totalExpenseShare))\(currency.symbol)")
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .foregroundColor(preview.totalExpenseShare > 0 ? .red : Constants.ContentM)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Constants.Surface)
                .cornerRadius(12)
            }

            HStack {
                Text("Net Settlement")
                    .font(
                        Font.beVietnamPro(14, weight: .medium)
                    )
                    .foregroundColor(Constants.ContentB)

                Spacer()

                Text(netSettlementText)
                    .font(
                        Font.beVietnamPro(14, weight: .medium)
                    )
                    .foregroundColor(netSettlementColor)
            }
            .padding(.top, 4)
        }
        .padding(12)
        .background(Constants.OnSurface)
        .cornerRadius(16)
    }

    // MARK: - Helpers

    private var netSettlementText: String {
        let settlement = preview.netSettlement
        if settlement > 0 {
            return String(localized: "+\(CurrencyFormatter.formatWhole(settlement))\(currency.symbol) (refund)", comment: "%1$@ = amount, %2$@ = currency symbol")
        } else if settlement < 0 {
            return String(localized: "-\(CurrencyFormatter.formatWhole(abs(settlement)))\(currency.symbol) (you owe)", comment: "%1$@ = amount, %2$@ = currency symbol")
        } else {
            return String(localized: "Settled")
        }
    }

    private var netSettlementColor: Color {
        let settlement = preview.netSettlement
        if settlement > 0 {
            return Constants.Green500
        } else if settlement < 0 {
            return .red
        } else {
            return Constants.ContentM
        }
    }

    private var sheetHeight: CGFloat {
        let baseHeight: CGFloat = 220
        let budgetHeight: CGFloat = preview.budgets.isEmpty ? 0 : CGFloat(preview.budgets.count * 54 + 100)
        let expenseHeight: CGFloat = 180
        return min(baseHeight + budgetHeight + expenseHeight, 600)
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            LeaveTripBottomSheet(
                preview: LeavePreviewDto(
                    displayName: "Ken",
                    budgets: [
                        LeavePreviewBudgetDto(
                            budgetName: "Trip Fund",
                            amount: 500_000,
                            isPaid: true,
                            refundAmount: 500_000
                        )
                    ],
                    totalBudgetRefund: 500_000,
                    totalBudgetCancelled: 0,
                    totalExpenseShare: 150_000,
                    netSettlement: 350_000,
                    hasVault: false,
                    lines: [],
                    canAnnounce: false,
                    leaveRequestPending: false,
                    canLeave: true,
                    vaultLeaveCleared: false
                ),
                isLeaving: false,
                onLeave: {}
            )
        }
}
