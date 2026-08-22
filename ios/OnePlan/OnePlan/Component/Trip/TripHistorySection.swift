//
//  TripHistorySection.swift
//  OnePlan
//
//  Created by Codex on 26/2/26.
//

import SwiftUI

struct TripHistorySection: View {
    let groupedHistory: [(date: String, entries: [TripHistoryEntry])]
    let isLoading: Bool
    var onBudgetTapped: ((Int) -> Void)?
    var onExpenseTapped: ((Int) -> Void)?

    init(
        groupedHistory: [(date: String, entries: [TripHistoryEntry])] =
            TripHistorySection.defaultGrouped,
        isLoading: Bool = false,
        onBudgetTapped: ((Int) -> Void)? = nil,
        onExpenseTapped: ((Int) -> Void)? = nil
    ) {
        self.groupedHistory = groupedHistory
        self.isLoading = isLoading
        self.onBudgetTapped = onBudgetTapped
        self.onExpenseTapped = onExpenseTapped
    }

    var body: some View {
        if isLoading && groupedHistory.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 100)
        } else if groupedHistory.isEmpty {
            TripHistoryEmpty()
        } else {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(groupedHistory, id: \.date) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(TripDetailService.formatDateLabel(group.date))
                            .font(Font.custom("Be Vietnam Pro", size: 14))
                            .foregroundColor(Constants.ContentM)
                            .frame(maxWidth: .infinity, alignment: .topLeading)

                        TripHistoryList(
                            entries: group.entries,
                            onBudgetTapped: onBudgetTapped,
                            onExpenseTapped: onExpenseTapped
                        )
                    }
                }
            }
            .padding(.bottom, 12)
        }
    }
}

extension TripHistorySection {
    fileprivate static let defaultGrouped:
        [(date: String, entries: [TripHistoryEntry])] = [
            (
                date: "Today",
                entries: [
                    TripHistoryEntry(
                        title: "Lẩu bò Nhà Gỗ",
                        scopeLabel: "All",
                        participantLabel: "Group",
                        participantVariant: .green,
                        amount: "-1,955,000đ",
                        time: "19:07",
                        iconName: "darkFoodIcon"
                    ),
                    TripHistoryEntry(
                        title: "Budget: Trip Fund",
                        scopeLabel: "",
                        participantLabel: "Group",
                        participantVariant: .green,
                        amount: "+19,000,000đ",
                        time: "12/12 paid",
                        iconName: "",
                        systemIconName: "creditcard",
                        type: .budget
                    ),
                    TripHistoryEntry(
                        title: "Homestay lần 2",
                        scopeLabel: "All",
                        participantLabel: "Ví của Hyydesi",
                        participantVariant: .blue,
                        amount: "-5,000,000đ",
                        time: "12:03",
                        iconName: "darkBuildingIcon"
                    ),
                ]
            )
        ]
}

#Preview {
    TripHistorySection()
        .padding()
        .background(Constants.Background)
}
