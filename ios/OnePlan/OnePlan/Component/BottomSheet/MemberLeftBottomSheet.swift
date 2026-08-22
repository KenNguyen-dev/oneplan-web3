//
//  MemberLeftBottomSheet.swift
//  OnePlan
//

import SwiftUI

struct MemberLeftBottomSheet: View {
    @Environment(\.dismiss) private var dismiss

    let displayName: String
    let totalBudgetRefund: Double
    let netSettlement: Double

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Constants.OnSurface)
                    .frame(width: 64, height: 64)

                Image(systemName: "person.fill.xmark")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(Constants.ContentM)
            }
            .padding(.top, 24)

            Text("\(displayName) left the group")
                .font(
                    Font.beVietnamPro(18, weight: .semibold)
                )
                .foregroundColor(Constants.ContentB)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .padding(.horizontal, 24)

            VStack(spacing: 8) {
                if totalBudgetRefund > 0 {
                    infoRow(
                        label: "Budget refund",
                        value: "+\(CurrencyFormatter.formatWhole(totalBudgetRefund))",
                        valueColor: Constants.Green500
                    )
                }

                infoRow(
                    label: "Balance updated",
                    value: netBalanceText,
                    valueColor: netBalanceColor
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("OK")
                    .font(
                        Font.beVietnamPro(16, weight: .medium)
                    )
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            }
            .background(Constants.BlueBase)
            .cornerRadius(.infinity)
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Helpers

    private var netBalanceText: String {
        if netSettlement > 0 {
            return "+\(CurrencyFormatter.formatWhole(netSettlement))"
        } else if netSettlement < 0 {
            return "-\(CurrencyFormatter.formatWhole(abs(netSettlement)))"
        } else {
            return String(localized: "Settled")
        }
    }

    private var netBalanceColor: Color {
        if netSettlement > 0 {
            return Constants.Green500
        } else if netSettlement < 0 {
            return .red
        } else {
            return Constants.ContentM
        }
    }

    @ViewBuilder
    private func infoRow(label: LocalizedStringKey, value: String, valueColor: Color) -> some View {
        HStack {
            Text(label)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundColor(Constants.ContentM)

            Spacer()

            Text(value)
                .font(
                    Font.beVietnamPro(14, weight: .medium)
                )
                .foregroundColor(valueColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Constants.Surface)
        .cornerRadius(12)
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            MemberLeftBottomSheet(
                displayName: "Minh Tran",
                totalBudgetRefund: 500_000,
                netSettlement: 350_000
            )
        }
}
