//
//  ExpenseDetailView.swift
//  OnePlan
//
//  Created by ken on 11/3/26.
//

import SwiftUI

struct ExpenseDetailView: View {
    let tripId: Int
    let expenseId: Int
    let allExpenseIds: [Int]
    let service: TripDetailService
    @Environment(\.dismiss) private var dismiss
    @Environment(UserProfileService.self) private var userProfileService
    @State private var currentExpenseId: Int
    @State private var showDeleteConfirm = false
    @State private var showDeleteError = false
    @State private var deleteErrorMessage = "Failed to delete expense."
    @State private var isEditing = false

    init(tripId: Int, expenseId: Int, allExpenseIds: [Int], service: TripDetailService) {
        self.tripId = tripId
        self.expenseId = expenseId
        self.allExpenseIds = allExpenseIds
        self.service = service
        self._currentExpenseId = State(initialValue: expenseId)
    }

    private var expense: ExpenseDetailDto? { service.expenseDetail }

    private var expensePercent: Int {
        guard let amount = expense?.amount, service.totalBudget > 0 else { return 0 }
        return min(Int((amount / service.totalBudget) * 100), 100)
    }

    private var formattedTime: String {
        guard let dateString = expense?.expenseDate else { return "" }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = isoFormatter.date(from: dateString)
        if date == nil {
            isoFormatter.formatOptions = [.withInternetDateTime]
            date = isoFormatter.date(from: dateString)
        }
        guard let date else { return dateString }

        return String(localized: "\(DisplayFormatters.time(date)) - \(DisplayFormatters.date(date))", comment: "%1$@ = time, %2$@ = date")
    }

    private var categoryInfo: CategoryChip.Category {
        guard let category = expense?.category.value1 else { return .other }
        return CategoryChip.Category(apiValue: category.rawValue) ?? .other
    }

    private var shareLabel: String {
        guard let shares = expense?.shares else { return "" }
        let totalMembers = service.trip?.members.count ?? 0
        if shares.count >= totalMembers && totalMembers > 0 {
            return String(localized: "All")
        }
        return String(localized: "\(shares.count) members")
    }

    private var currentUserShare: Double? {
        guard let userId = userProfileService.profile?.id,
              let shares = expense?.shares else { return nil }
        return shares.first(where: { $0.userId == userId })?.shareAmount
    }

    private var homeCurrency: Currency {
        service.homeCurrency ?? .VND
    }

    var body: some View {
        contentRoot
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Constants.Background.ignoresSafeArea())
            .overlay { deleteConfirmOverlay }
            .overlay { deleteErrorOverlay }
            .navigationDestination(isPresented: $isEditing) { editDestination }
            .task(id: currentExpenseId) { await loadExpenseDetail() }
    }

    @ViewBuilder
    private var contentRoot: some View {
        if service.isLoadingExpenseDetail && expense == nil {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let expense {
            expenseContent(expense)
        }
    }

    private var deleteConfirmOverlay: some View {
        Color.clear
            .allowsHitTesting(false)
            .alert("Delete expense?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive, action: handleDeleteConfirmed)
            } message: {
                Text("This expense will be permanently removed from the trip.")
            }
    }

    private var deleteErrorOverlay: some View {
        Color.clear
            .allowsHitTesting(false)
            .alert("Delete failed", isPresented: $showDeleteError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(deleteErrorMessage)
            }
    }

    @ViewBuilder
    private var editDestination: some View {
        if let expense {
            EditExpenseView(
                tripId: tripId,
                members: service.trip?.members ?? [],
                service: service,
                editingExpense: expense
            )
        }
    }

    private func handleDeleteConfirmed() {
        guard !service.isDeletingExpense else { return }
        let deletingExpenseId = currentExpenseId
        Task {
            let success = await service.deleteExpense(
                tripId: tripId,
                expenseId: deletingExpenseId
            )
            if success {
                dismiss()
            } else {
                deleteErrorMessage = service.error ?? String(localized: "Failed to delete expense.")
                showDeleteError = true
            }
        }
    }

    private func loadExpenseDetail() async {
        await service.fetchExpenseDetail(
            tripId: tripId, expenseId: currentExpenseId
        )
    }

    private func heroSection(for expense: ExpenseDetailDto) -> some View {
        VStack(alignment: .center, spacing: 8) {
            Text(expense.name)
                .font(Font.beVietnamPro(20, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundColor(Constants.ContentB)
                .frame(maxWidth: .infinity)

            heroAmountRow(for: expense)

            originalAmountSubtext(for: expense)

            progressPill
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var progressPill: some View {
        HStack(alignment: .center, spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Constants.BlueBase)
                        .frame(width: geo.size.width, height: geo.size.height)
                    Capsule()
                        .fill(Color(red: 1, green: 0.35, blue: 0.35))
                        .frame(width: geo.size.width * CGFloat(expensePercent) / 100, height: geo.size.height)
                }
            }
            .frame(width: 100, height: 8)

            Text("\(expensePercent)%")
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundColor(Constants.ContentB)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Constants.OnSurface)
        .cornerRadius(22)
        .padding(.bottom, 32)
    }

    private func heroAmountRow(for expense: ExpenseDetailDto) -> some View {
        HStack(alignment: .center, spacing: 3) {
            Text(homeCurrency.symbol)
                .font(Font.custom("Be Vietnam Pro", size: 36))
                .multilineTextAlignment(.center)
                .foregroundStyle(Constants.ContentL)

            Text("-\(CurrencyFormatter.formatWhole(expense.amount))")
                .font(Font.custom("Be Vietnam Pro", size: 36))
                .multilineTextAlignment(.center)
                .foregroundColor(Constants.ContentB)

            if homeCurrency.decimalPlaces > 0 {
                Text(CurrencyFormatter.formatDecimal(expense.amount))
                    .font(Font.custom("Be Vietnam Pro", size: 36))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Constants.ContentL)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func originalAmountSubtext(for expense: ExpenseDetailDto) -> some View {
        if let origCur = expense.originalCurrency.flatMap({ Currency(from: $0.value1) }),
           let origAmt = expense.originalAmount,
           let home = service.homeCurrency,
           origCur != home {
            let decimalPart = origCur.decimalPlaces > 0 ? CurrencyFormatter.formatDecimal(origAmt) : ""
            let formatted = "~\(CurrencyFormatter.formatWhole(origAmt))\(decimalPart) \(origCur.rawValue)"
            Text(formatted)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundColor(Constants.ContentM)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func expenseContent(_ expense: ExpenseDetailDto) -> some View {
        VStack {
            Spacer()

            heroSection(for: expense)

            Spacer()

            VStack(spacing: 10) {
                HStack(spacing: 16) {
                    ExpenseDetailActionItem(
                        label: "Edit",
                        icon: "pencil",
                        iconColor: Constants.ContentB,
                        backgroundColor: Constants.OnSurface
                    ) {
                        isEditing = true
                    }

//                    ExpenseDetailActionItem(
//                        label: "Send",
//                        icon: "square.and.arrow.up",
//                        iconColor: Constants.ContentB,
//                        backgroundColor: Constants.OnSurface
//                    ) { }

                    ExpenseDetailActionItem(
                        label: "Delete",
                        icon: "trash",
                        iconColor: Color(red: 1, green: 0.35, blue: 0.35),
                        backgroundColor: Color(red: 0.99, green: 0.91, blue: 0.91)
                    ) {
                        showDeleteConfirm = true
                    }
                    .disabled(service.isDeletingExpense)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                ExpenseDetailHistoryCard(
                    time: formattedTime,
                    category: categoryInfo,
                    yourExpense: currentUserShare,
                    yourExpenseCurrency: homeCurrency,
                    shareLabel: shareLabel,
                    createdBy: expense.paidBy?.value1.displayName ?? String(localized: "Deleted User")
                )
                .padding(.horizontal)

                PlanDetailPrevNextStrip(
                    onPrev: {
                        guard let idx = allExpenseIds.firstIndex(of: currentExpenseId),
                              idx > 0 else { return }
                        currentExpenseId = allExpenseIds[idx - 1]
                    },
                    onNext: {
                        guard let idx = allExpenseIds.firstIndex(of: currentExpenseId),
                              idx < allExpenseIds.count - 1 else { return }
                        currentExpenseId = allExpenseIds[idx + 1]
                    }
                )
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Action Item

private struct ExpenseDetailActionItem: View {
    let label: LocalizedStringKey
    let icon: String
    let iconColor: Color
    let backgroundColor: Color
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(iconColor)
                    }

                Text(label)
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .kerning(-0.6)
                    .foregroundStyle(Constants.ContentB)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - History Card

private struct ExpenseDetailHistoryCard: View {
    let time: String
    let category: CategoryChip.Category
    var yourExpense: Double? = nil
    var yourExpenseCurrency: Currency = .VND
    let shareLabel: String
    let createdBy: String

    var body: some View {
        VStack(spacing: 0) {
            ExpenseDetailHistoryRow(title: "Time") {
                Text(time)
                    .font(Font.custom("Be Vietnam Pro", size: 16))
                    .foregroundStyle(Constants.ContentB)
            }

            ExpenseDetailDivider()

            ExpenseDetailHistoryRow(title: "Category") {
                HStack(spacing: 4) {
                    if category == .other {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Constants.ContentB)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(category.darkIconName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                    }

                    Text(category.title)
                        .font(Font.custom("Be Vietnam Pro", size: 16))
                        .foregroundStyle(Constants.ContentB)
                }
            }

            if let yourExpense {
                ExpenseDetailDivider()

                ExpenseDetailHistoryRow(title: "Your expense") {
                    Text("-\(CurrencyFormatter.formatWhole(yourExpense))\(yourExpenseCurrency.symbol)")
                        .font(Font.custom("Be Vietnam Pro", size: 16))
                        .foregroundStyle(Color(red: 1, green: 0.35, blue: 0.35))
                }
            }

            ExpenseDetailDivider()

            ExpenseDetailHistoryRow(title: "Share with") {
                HStack(spacing: 4) {
                    Image(systemName: "person.3")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Constants.ContentB)

                    Text(shareLabel)
                        .font(Font.custom("Be Vietnam Pro", size: 16))
                        .foregroundStyle(Constants.ContentB)
                }
            }

            ExpenseDetailDivider()

            ExpenseDetailHistoryRow(title: "Created by") {
                HStack(spacing: 4) {
                    Image(systemName: "person")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Constants.ContentB)

                    Text(createdBy)
                        .font(Font.custom("Be Vietnam Pro", size: 16))
                        .foregroundStyle(Constants.ContentB)
                }
            }
        }
        .background(Constants.Surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

// MARK: - History Row

private struct ExpenseDetailHistoryRow<Content: View>: View {
    let title: LocalizedStringKey
    let trailingContent: Content

    init(title: LocalizedStringKey, @ViewBuilder trailingContent: () -> Content) {
        self.title = title
        self.trailingContent = trailingContent()
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .kerning(-0.7)
                .foregroundStyle(Constants.ContentM)
                .lineLimit(1)

            Spacer(minLength: 8)

            trailingContent
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
    }
}

// MARK: - Divider

private struct ExpenseDetailDivider: View {
    var body: some View {
        Rectangle()
            .fill(Constants.DividerStroke)
            .frame(height: 1)
    }
}

#Preview {
    NavigationStack {
        ExpenseDetailView(
            tripId: 1,
            expenseId: 1,
            allExpenseIds: [1],
            service: TripDetailService()
        )
    }
    .environment(UserProfileService())
}
