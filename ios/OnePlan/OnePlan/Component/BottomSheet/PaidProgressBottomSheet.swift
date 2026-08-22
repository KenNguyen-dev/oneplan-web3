//
//  PaidProgressBottomSheet.swift
//  OnePlan
//
//  Created by Codex on 8/3/26.
//

import SwiftUI

struct PaidProgressItem: Identifiable, Hashable {
    let id: String
    let budgetId: Int
    let paymentId: Int
    let title: String
    let amount: String
    let isPaid: Bool
}

struct PaidProgressBottomSheet: View {
    @Environment(\.dismiss) private var dismiss

    var items: [PaidProgressItem] = []
    var onClose: () -> Void = {}
    var onSave: () -> Void = {}
    var onTogglePayment: ((PaidProgressItem) -> Void)?

    private var isReadOnly: Bool {
        onTogglePayment == nil
    }

    private var sheetHeight: CGFloat {
        // Generous estimates so the detent ≥ content for typical counts (avoids the
        // marginal-overflow regime where the sheet resizes instead of the list scrolling).
        let base: CGFloat = 150     // toolbar + spacing + bottom padding + drag indicator
        let rowHeight: CGFloat = 90 // row content + .padding(.vertical, 24) + 8pt spacing
        let contentHeight = base + CGFloat(items.count) * rowHeight
        return min(max(contentHeight, 220), 600)
    }

    var body: some View {
        VStack(spacing: 12) {
            toolbar

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(items) { item in
                        paidProgressRow(item)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 19)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Constants.Background)
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
    }

    private var toolbar: some View {
        HStack(alignment: .center) {
            Button {
                onClose()
                dismiss()
            } label: {
                ZStack {
                    Circle()
                        .fill(Constants.OnSurface)
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Constants.ContentM)
                }
                .frame(width: 43, height: 43)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Paid progress")
                .font(Font.custom("Be Vietnam Pro", size: 18))
                .foregroundColor(Constants.ContentB)

            Spacer()

            Button {
                onSave()
                dismiss()
            } label: {
                ZStack {
                    Circle()
                        .fill(Constants.BlueBase)
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }
                .frame(width: 43, height: 43)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 16)
    }

    private func paidProgressRow(_ item: PaidProgressItem) -> some View {
        Button {
            onTogglePayment?(item)
        } label: {
            HStack(spacing: 5) {
                selectionIndicator(isSelected: item.isPaid)
                    .frame(width: 24, height: 24)

                Text(item.title)
                    .font(.system(size: 16))
                    .lineLimit(1)
                    .foregroundColor(.black)

                Spacer(minLength: 8)

                Text(item.amount)
                    .font(.system(size: 16))
                    .lineLimit(1)
                    .foregroundColor(.black)
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Constants.Neutral50)
            .cornerRadius(19)
        }
        .buttonStyle(.plain)
        .disabled(isReadOnly)
        .opacity(isReadOnly ? 0.65 : 1)
    }

    private func selectionIndicator(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(
                    isSelected
                        ? Color(red: 0.20, green: 0.78, blue: 0.35) : .clear
                )
                .overlay(
                    Circle()
                        .stroke(
                            isSelected
                                ? Color.clear
                                : Color(red: 0.78, green: 0.78, blue: 0.80),
                            lineWidth: 1.5
                        )
                )

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: 22, height: 22)
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            PaidProgressBottomSheet(
                items: [
                    PaidProgressItem(id: "1", budgetId: 1, paymentId: 1, title: "Budget 1", amount: "1,000,000đ", isPaid: true),
                    PaidProgressItem(id: "2", budgetId: 2, paymentId: 2, title: "Budget 2", amount: "2,000,000đ", isPaid: false),
                    PaidProgressItem(id: "3", budgetId: 1, paymentId: 1, title: "Budget 1", amount: "1,000,000đ", isPaid: true),
                    PaidProgressItem(id: "4", budgetId: 2, paymentId: 2, title: "Budget 2", amount: "2,000,000đ", isPaid: false),
                    PaidProgressItem(id: "5", budgetId: 1, paymentId: 1, title: "Budget 1", amount: "1,000,000đ", isPaid: true),
                    PaidProgressItem(id: "6", budgetId: 2, paymentId: 2, title: "Budget 2", amount: "2,000,000đ", isPaid: false),
                ]
            )
        }
}
