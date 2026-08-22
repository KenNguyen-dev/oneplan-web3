//
//  WhoDepositView.swift
//  OnePlan
//
//  Created by ken on 20/3/26.
//

import SwiftUI

struct WhoDepositEntry: Identifiable {
    let id: String
    let userId: Int
    let name: String
    let amountText: String
    let paidText: String
    let progressSegments: [Bool]
    let avatarUrl: String?
    let fallbackImageName: String

    init(
        id: String = UUID().uuidString,
        userId: Int = 0,
        name: String,
        amountText: String,
        paidText: String,
        progressSegments: [Bool],
        avatarUrl: String? = nil,
        fallbackImageName: String = "avatarPlaceholder"
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.amountText = amountText
        self.paidText = paidText
        self.progressSegments = progressSegments
        self.avatarUrl = avatarUrl
        self.fallbackImageName = fallbackImageName
    }
}

private struct DepositProgressBar: View {
    let segments: [Bool]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(displayedSegments.enumerated()), id: \.offset) {
                _,
                isPaid in
                RoundedRectangle(cornerRadius: 11)
                    .fill(isPaid ? Constants.ContentM : Constants.Neutral200)
                    .frame(maxWidth: 60)
                    .frame(height: 6)

            }
        }
    }

    private var displayedSegments: [Bool] {
        segments
    }
}

private struct WhoDepositRow: View {
    let entry: WhoDepositEntry

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            avatar

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.name)
                    .font(Font.custom("Be Vietnam Pro", size: 16))
                    .kerning(-0.7)
                    .foregroundColor(Constants.ContentB)
                    .lineLimit(1)

                DepositProgressBar(segments: entry.progressSegments)
            }
            .frame(width: 200, alignment: .leading)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(entry.amountText)
                    .font(Font.custom("Be Vietnam Pro", size: 16))
                    .kerning(-0.7)
                    .foregroundColor(Constants.Green500)
                    .lineLimit(1)

                Text(entry.paidText)
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .kerning(-0.6)
                    .foregroundColor(Constants.ContentM)
                    .lineLimit(1)
            }
            .multilineTextAlignment(.trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var avatar: some View {
        if let avatarUrl = entry.avatarUrl, let url = URL(string: avatarUrl) {
            CachedRemoteImage(
                url: url,
                targetSize: CGSize(width: 48, height: 48)
            ) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Image(entry.fallbackImageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())
        } else {
            Image(entry.fallbackImageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 48, height: 48)
                .clipShape(Circle())
        }
    }
}

private struct WhoDepositHistoryRow: View {
    let entry: TripHistoryEntry
    let showsDivider: Bool
    let onEdit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                HStack(alignment: .center, spacing: 6) {
                    Circle()
                        .fill(Constants.Green100)
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "creditcard")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(Constants.Green500)
                        }

                    Text(entry.title)
                        .font(Font.custom("Be Vietnam Pro", size: 15))
                        .foregroundColor(Constants.ContentB)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(entry.amount)
                        .font(Font.custom("Be Vietnam Pro", size: 16))
                        .foregroundColor(Constants.Green500)
                        .lineLimit(1)

                    Text(entry.time)
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .foregroundColor(Constants.ContentM)
                        .lineLimit(1)
                }

                Button(action: onEdit) {
                    Text("Edit")
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .foregroundColor(Constants.White)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 14)

            if showsDivider {
                Divider()
                    .overlay(Constants.Neutral100)
            }
        }
    }
}

private struct WhoDepositHistorySection: View {
    let groupedHistory: [(date: String, entries: [TripHistoryEntry])]
    let onEditBudget: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(groupedHistory, id: \.date) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(TripDetailService.formatDateLabel(group.date))
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .kerning(-0.42)
                        .foregroundColor(Constants.ContentM)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 0) {
                        ForEach(Array(group.entries.enumerated()), id: \.element.id)
                        { index, entry in
                            WhoDepositHistoryRow(
                                entry: entry,
                                showsDivider: index < group.entries.count - 1,
                                onEdit: {
                                    if let budgetId = entry.budgetId {
                                        onEditBudget(budgetId)
                                    }
                                }
                            )
                        }
                    }
                    .background(Constants.Surface)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 24,
                            style: .continuous
                        )
                    )
                }
            }
        }
    }
}

struct WhoDepositView: View {
    @Environment(UserProfileService.self) private var userProfileService

    let tripId: Int
    let service: TripDetailService
    private let previewEntries: [WhoDepositEntry]?
    private let previewGroupedHistory: [(date: String, entries: [TripHistoryEntry])]?

    @State private var selectedUserId: Int?
    @State private var editingBudgetId: Int?

    init(
        tripId: Int,
        service: TripDetailService,
        previewEntries: [WhoDepositEntry]? = nil,
        previewGroupedHistory: [(date: String, entries: [TripHistoryEntry])]? = nil
    ) {
        self.tripId = tripId
        self.service = service
        self.previewEntries = previewEntries
        self.previewGroupedHistory = previewGroupedHistory
    }

    private func canToggle(for userId: Int) -> Bool {
        guard let currentUserId = userProfileService.profile?.id else { return false }

        let tripCreatorId = service.trip?.createdById
        return currentUserId == userId || currentUserId == tripCreatorId
    }

    private var entries: [WhoDepositEntry] {
        if let previewEntries {
            return previewEntries
        }

        var userMap:
            [Int: (
                name: String, avatarUrl: String?, paidAmount: Double,
                paidCount: Int, segments: [Bool]
            )] = [:]

        for budget in service.budgets {
            for payment in budget.payments {
                let uid = Int(payment.userId)
                var info =
                    userMap[uid] ?? (
                        name: payment.displayName,
                        avatarUrl: payment.avatarUrl,
                        paidAmount: 0,
                        paidCount: 0,
                        segments: []
                    )
                info.segments.append(payment.isPaid)
                if payment.isPaid {
                    info.paidAmount += payment.amount
                    info.paidCount += 1
                }
                userMap[uid] = info
            }
        }

        return userMap.map { (uid, info) in
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = ","
            formatter.maximumFractionDigits = 0
            let formattedAmount =
                formatter.string(from: NSNumber(value: info.paidAmount))
                ?? "\(Int(info.paidAmount))"

            let currencySymbol = Currency(from: service.trip?.currency.value1)?.symbol ?? "đ"
            return WhoDepositEntry(
                id: "\(uid)",
                userId: uid,
                name: info.name,
                amountText: "+\(formattedAmount)\(currencySymbol)",
                paidText: String(localized: "\(info.paidCount)/\(service.budgets.count) paid", comment: "%1$lld = paid count, %2$lld = total"),
                progressSegments: info.segments,
                avatarUrl: info.avatarUrl
            )
        }.sorted { $0.name < $1.name }
    }

    private func paymentItems(for userId: Int) -> [PaidProgressItem] {
        return service.budgets.compactMap { budget in
            guard
                let payment = budget.payments.first(where: {
                    Int($0.userId) == userId
                })
            else { return nil }
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = ","
            formatter.maximumFractionDigits = 0
            let formatted =
                formatter.string(from: NSNumber(value: payment.amount))
                ?? "\(Int(payment.amount))"
            let currencySymbol = Currency(from: service.trip?.currency.value1)?.symbol ?? "đ"
            return PaidProgressItem(
                id: "\(payment.id)",
                budgetId: Int(budget.id),
                paymentId: Int(payment.id),
                title: budget.name,
                amount: "\(formatted)\(currencySymbol)",
                isPaid: payment.isPaid
            )
        }
    }

    private var groupedBudgetHistory: [(date: String, entries: [TripHistoryEntry])] {
        if let previewGroupedHistory {
            return previewGroupedHistory
        }
        return service.groupedBudgetHistory
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if !groupedBudgetHistory.isEmpty {
                WhoDepositHistorySection(
                    groupedHistory: groupedBudgetHistory,
                    onEditBudget: { budgetId in
                        editingBudgetId = budgetId
                    }
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }

            VStack(alignment: .leading, spacing: 8) {
                // Title
                Text("Progress")
                  .font(
                    Font.beVietnamPro(16, weight: .medium)
                  )
                  .foregroundColor(Constants.ContentM)
                  .frame(maxWidth: .infinity, alignment: .topLeading)
                
                ForEach(entries) { entry in
                    Button {
                        selectedUserId = entry.userId
                    } label: {
                        WhoDepositRow(entry: entry)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 8)
        .background(Constants.Background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $editingBudgetId) { budgetId in
            if let budget = service.budgets.first(where: { Int($0.id) == budgetId }),
               let members = service.trip?.members {
                EditBudgetView(
                    tripId: tripId,
                    members: members,
                    service: service,
                    editingBudget: budget
                )
            }
        }
        .sheet(item: $selectedUserId.identifiable) { wrapper in
            PaidProgressBottomSheet(
                items: paymentItems(for: wrapper.id),
                onTogglePayment: canToggle(for: wrapper.id)
                    ? { item in
                        Task {
                            _ = await service.markPayment(
                                tripId: tripId,
                                budgetId: item.budgetId,
                                paymentId: item.paymentId,
                                isPaid: !item.isPaid
                            )
                        }
                    }
                    : nil
            )
        }
    }
}

#Preview("Figma") {
    NavigationStack {
        WhoDepositView(
            tripId: 1,
            service: TripDetailService(),
            previewEntries: [
                WhoDepositEntry(
                    userId: 1,
                    name: "Ken",
                    amountText: "+1,250,000đ",
                    paidText: "2/3 paid",
                    progressSegments: [true, true, false]
                ),
                WhoDepositEntry(
                    userId: 2,
                    name: "Linh",
                    amountText: "+650,000đ",
                    paidText: "1/3 paid",
                    progressSegments: [true, false, false]
                ),
                WhoDepositEntry(
                    userId: 3,
                    name: "Minh",
                    amountText: "+0đ",
                    paidText: "0/3 paid",
                    progressSegments: [false, false, false]
                ),
            ]
            ,
            previewGroupedHistory: [
                (
                    date: "2025-07-19",
                    entries: [
                        TripHistoryEntry(
                            title: "Budget 3",
                            scopeLabel: "",
                            participantLabel: "Group",
                            participantVariant: .green,
                            amount: "+1,000,000đ",
                            time: "12/12 paid",
                            iconName: "",
                            systemIconName: "creditcard",
                            type: .budget,
                            budgetId: 3,
                            dateKey: "2025-07-19"
                        )
                    ]
                ),
                (
                    date: "2025-06-18",
                    entries: [
                        TripHistoryEntry(
                            title: "Budget 2",
                            scopeLabel: "",
                            participantLabel: "Group",
                            participantVariant: .green,
                            amount: "+1,000,000đ",
                            time: "12/12 paid",
                            iconName: "",
                            systemIconName: "creditcard",
                            type: .budget,
                            budgetId: 2,
                            dateKey: "2025-06-18"
                        ),
                        TripHistoryEntry(
                            title: "Budget 1",
                            scopeLabel: "",
                            participantLabel: "Group",
                            participantVariant: .green,
                            amount: "+1,000,000đ",
                            time: "12/12 paid",
                            iconName: "",
                            systemIconName: "creditcard",
                            type: .budget,
                            budgetId: 1,
                            dateKey: "2025-06-18"
                        ),
                    ]
                ),
            ]
        )
        .navigationTitle("Who Deposit")
    }
        .environment(UserProfileService())
}
