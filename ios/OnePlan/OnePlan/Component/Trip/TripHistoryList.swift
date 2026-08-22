//
//  TripHistoryList.swift
//  OnePlan
//
//  Created by ken on 25/2/26.
//

import SwiftUI

enum TripHistoryEntryType {
    case expense
    case budget
}

struct TripHistoryScopeMember: Identifiable {
    let id: Int
    let avatarUrl: String?
    let fallbackImageName: String

    init(
        id: Int,
        avatarUrl: String?,
        fallbackImageName: String = "avatarPlaceholder"
    ) {
        self.id = id
        self.avatarUrl = avatarUrl
        self.fallbackImageName = fallbackImageName
    }
}

struct TripHistoryEntry: Identifiable {
    let id = UUID()
    let title: String
    let scopeLabel: String
    let scopeMembers: [TripHistoryScopeMember]
    let participantLabel: String
    let participantVariant: Chip.Variant
    let amount: String
    let time: String
    let iconName: String
    let systemIconName: String?
    let type: TripHistoryEntryType
    let budgetId: Int?
    let expenseId: Int?
    let dateKey: String
    let sortDate: Date
    /// Small gray subtext showing the ORIGINAL (non-home) currency + amount
    /// for rows that were entered in a local currency. `nil` when the row
    /// was entered in the trip's home currency (or when legacy data pre-
    /// second-currency has no original). Rendered beneath `amount` in the
    /// history list.
    let originalSubtext: String?

    init(
        title: String,
        scopeLabel: String,
        scopeMembers: [TripHistoryScopeMember] = [],
        participantLabel: String,
        participantVariant: Chip.Variant,
        amount: String,
        time: String,
        iconName: String,
        systemIconName: String? = nil,
        type: TripHistoryEntryType = .expense,
        budgetId: Int? = nil,
        expenseId: Int? = nil,
        dateKey: String = "",
        sortDate: Date = .distantPast,
        originalSubtext: String? = nil
    ) {
        self.title = title
        self.scopeLabel = scopeLabel
        self.scopeMembers = scopeMembers
        self.participantLabel = participantLabel
        self.participantVariant = participantVariant
        self.amount = amount
        self.time = time
        self.iconName = iconName
        self.systemIconName = systemIconName
        self.type = type
        self.budgetId = budgetId
        self.expenseId = expenseId
        self.dateKey = dateKey
        self.sortDate = sortDate
        self.originalSubtext = originalSubtext
    }
}

private struct TripHistoryListItem: View {
    let entry: TripHistoryEntry
    let showsDivider: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Circle()
                    .fill(entry.type == .budget ? Constants.Green100 : Constants.Neutral100)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Group {
                            if let systemIconName = entry.systemIconName {
                                Image(systemName: systemIconName)
                                    .font(
                                        .system(
                                            size: entry.type == .budget ? 16 : 12,
                                            weight: .medium
                                        )
                                    )
                                    .foregroundColor(
                                        entry.type == .budget
                                            ? Constants.Green500
                                            : Constants.ContentB
                                    )
                            } else {
                                Image(entry.iconName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 24, height: 24)
                            }
                        }
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(
                            Font.beVietnamPro(16, weight: entry.type == .budget ? .regular : .medium)
                        )
                        .foregroundColor(Constants.ContentB)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(alignment: .center, spacing: 4) {
                        if entry.type == .expense {
                            if entry.scopeLabel == "All" {
                                Chip(variant: .neutral, text: String(localized: "All", comment: "Expense scope: shared with all trip members"))
                            } else if entry.scopeMembers.isEmpty {
                                Chip(variant: .neutral, text: entry.scopeLabel)
                            } else {
                                TripHistoryScopeMembersPill(members: entry.scopeMembers)
                            }
                        } else {
                            Chip(variant: .green, text: String(localized: "To: \(entry.participantLabel)", comment: "%@ = recipient name"))
                        }
                    }
                }

                Spacer(minLength: 10)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(entry.amount)
                        .font(
                            Font.beVietnamPro(16, weight: entry.type == .budget ? .regular : .medium)
                        )
                        .foregroundColor(entry.type == .budget ? Constants.Green500 : Constants.Warning500)
                        .lineLimit(1)

                    if let originalSubtext = entry.originalSubtext {
                        Text(originalSubtext)
                            .font(Font.custom("Be Vietnam Pro", size: 12))
                            .foregroundColor(Constants.ContentM)
                            .lineLimit(1)
                    }

                    Text(entry.time)
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .foregroundColor(Constants.ContentM)
                }
            }
            .padding()

            if showsDivider {
                Divider()
                    .overlay(Constants.Neutral100)
            }
        }
    }
}

private struct TripHistoryScopeMembersPill: View {
    let members: [TripHistoryScopeMember]

    private var displayedMembers: [TripHistoryScopeMember] {
        Array(members.prefix(3))
    }

    private var remainingCount: Int {
        max(members.count - 3, 0)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            HStack(spacing: -9) {
                ForEach(displayedMembers) { member in
                    avatar(for: member)
                }
            }

            if remainingCount > 0 {
                Text("+ \(remainingCount)")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundColor(Constants.ContentB)
                    .lineLimit(1)
            }
        }
        .padding(.trailing, members.count > 3 ? 8 : 0)
        .padding(.vertical, 1)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Constants.Neutral100, lineWidth: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func avatar(for member: TripHistoryScopeMember) -> some View {
        if let avatarUrl = member.avatarUrl, let url = URL(string: avatarUrl) {
            CachedRemoteImage(
                url: url,
                targetSize: CGSize(width: 17, height: 17)
            ) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Image(member.fallbackImageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .frame(width: 17, height: 17)
            .clipShape(Circle())
        } else {
            Image(member.fallbackImageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 17, height: 17)
                .clipShape(Circle())
        }
    }
}

private struct TripHistoryListHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 1

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct TripHistoryListSizingContent: View {
    let entries: [TripHistoryEntry]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                TripHistoryListItem(
                    entry: entry,
                    showsDivider: index < entries.count - 1
                )
            }
        }
    }
}

struct TripHistoryList: View {
    let entries: [TripHistoryEntry]
    var onBudgetTapped: ((Int) -> Void)?
    var onExpenseTapped: ((Int) -> Void)?
    @State private var contentHeight: CGFloat = 1

    var body: some View {
        List {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                if entry.type == .budget, let budgetId = entry.budgetId {
                    Button {
                        onBudgetTapped?(budgetId)
                    } label: {
                        TripHistoryListItem(
                            entry: entry,
                            showsDivider: index < entries.count - 1
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(
                        EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else if entry.type == .expense, let expenseId = entry.expenseId {
                    Button {
                        onExpenseTapped?(expenseId)
                    } label: {
                        TripHistoryListItem(
                            entry: entry,
                            showsDivider: index < entries.count - 1
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(
                        EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else {
                    TripHistoryListItem(
                        entry: entry,
                        showsDivider: index < entries.count - 1
                    )
                    .listRowInsets(
                        EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .environment(\.defaultMinListRowHeight, 1)
        .listStyle(.plain)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .overlay(alignment: .topLeading) {
            TripHistoryListSizingContent(entries: entries)
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .accessibilityHidden(true)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TripHistoryListHeightPreferenceKey.self,
                            value: proxy.size.height
                        )
                    }
                )
        }
        .onPreferenceChange(TripHistoryListHeightPreferenceKey.self) { height in
            contentHeight = max(height, 1)
        }
        .frame(height: contentHeight)
        .background(Constants.Surface)
        .cornerRadius(24)
    }
}

#Preview("ScopeMembersPill") {
    VStack(spacing: 16) {
        TripHistoryScopeMembersPill(members: [
            TripHistoryScopeMember(id: 1, avatarUrl: nil),
        ])

        TripHistoryScopeMembersPill(members: [
            TripHistoryScopeMember(id: 1, avatarUrl: nil),
            TripHistoryScopeMember(id: 2, avatarUrl: nil),
            TripHistoryScopeMember(id: 3, avatarUrl: nil),
        ])

        TripHistoryScopeMembersPill(members: [
            TripHistoryScopeMember(id: 1, avatarUrl: nil),
            TripHistoryScopeMember(id: 2, avatarUrl: nil),
            TripHistoryScopeMember(id: 3, avatarUrl: nil),
            TripHistoryScopeMember(id: 4, avatarUrl: nil),
            TripHistoryScopeMember(id: 5, avatarUrl: nil),
        ])
    }
    .padding()
    .background(Constants.Background)
}


#Preview {
    TripHistoryList(
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
                title: "Homestay lần 2",
                scopeLabel: "All",
                participantLabel: "Ví của Hyydesi",
                participantVariant: .blue,
                amount: "-5,000,000đ",
                time: "12:03",
                iconName: "darkBuildingIcon"
            )
        ]
    )
    .padding()
    .background(Constants.Background)
}
