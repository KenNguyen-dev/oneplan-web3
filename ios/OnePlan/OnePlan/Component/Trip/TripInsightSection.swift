//
//  TripInsightSection.swift
//  OnePlan
//
//  Created by ken on 28/4/26.
//

import SwiftUI

enum TripInsightScope: String, CaseIterable, Identifiable {
    case personal = "Personal"
    case group = "Group"

    var id: String { rawValue }

    /// Localized segment title (rawValue stays English for identity).
    var localizedTitle: String {
        switch self {
        case .personal: String(localized: "Personal", comment: "Insight scope: personal")
        case .group: String(localized: "Group", comment: "Insight scope: group")
        }
    }
}

struct TripInsightSection: View {
    let service: TripDetailService
    let currentUserId: Int?

    @State private var selectedScope: TripInsightScope = .personal

    private var currency: Currency? { service.homeCurrency }
    private var currencySymbol: String { currency?.symbol ?? "đ" }

    private var personal: PersonalInsight {
        PersonalInsight(
            service: service,
            currentUserId: currentUserId
        )
    }

    private var group: GroupInsight {
        GroupInsight(service: service)
    }

    var body: some View {
        ScrollView {
            Picker("Scope", selection: $selectedScope) {
                ForEach(TripInsightScope.allCases) { scope in
                    Text(scope.localizedTitle).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedScope) { oldValue, newValue in
                guard oldValue != newValue else { return }
                UIImpactFeedbackGenerator(style: .light)
                    .impactOccurred()
            }

            switch selectedScope {
            case .personal:
                personalView
            case .group:
                groupView
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Personal

    @ViewBuilder
    private var personalView: some View {
        let isOver = personal.remaining < 0
        let isLoading = service.breakdown == nil

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 4) {
                amountTile(
                    title: "Remaining",
                    amount: personal.remaining,
                    color: isOver ? Constants.Secondary : Constants.ContentB,
                    isLoading: isLoading
                )

                amountTile(
                    title: "Your expenses",
                    amount: personal.myExpenses,
                    color: Constants.BlueBase,
                    isLoading: isLoading
                )
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            HStack(alignment: .center, spacing: 10) {
                Text(personalNote(isOver: isOver))
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundColor(Constants.Neutral700)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 8)
            .padding(.top, 5)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .center)

            categoryChartCard(categories: personal.categories)
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(red: 0.92, green: 0.92, blue: 0.92))
        .cornerRadius(18)
    }

    private func personalNote(isOver: Bool) -> String {
        isOver
            ? String(localized: "Your current spending has exceeded your contributed budget. Please prepare to return the excess amount to the team.", comment: "Personal insight note when over budget")
            : String(localized: "The two figures above are based on the actual spending of the members, and the figures may vary among members.", comment: "Personal insight note when within budget")
    }

    // MARK: - Group

    @ViewBuilder
    private var groupView: some View {
        let isOver = group.remaining < 0
        let isLoading = service.breakdown == nil && service.expenses.isEmpty

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 4) {
                amountTile(
                    title: "Remaining",
                    amount: group.remaining,
                    color: isOver ? Constants.Secondary : Constants.ContentB,
                    isLoading: isLoading
                )

                amountTile(
                    title: "Total expenses",
                    amount: group.totalSpent,
                    color: Constants.BlueBase,
                    isLoading: isLoading
                )
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            HStack(alignment: .top, spacing: 4) {
                amountTile(
                    title: "Safe daily spend",
                    amount: group.safeDailySpend,
                    color: Constants.ContentB,
                    isLoading: isLoading
                )

                healthTile(health: group.health)
            }
            .padding(0)
            .frame(maxWidth: .infinity, alignment: .topLeading)

            HStack(alignment: .center, spacing: 10) {
                Text(groupNote(isOver: isOver))
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundColor(Constants.Neutral700)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 8)
            .padding(.top, 5)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .center)

            categoryChartCard(categories: group.categories)
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(red: 0.92, green: 0.92, blue: 0.92))
        .cornerRadius(18)

        VStack(alignment: .leading, spacing: 8) {
            Text("Member expenses")
                .font(Font.custom("Be Vietnam Pro", size: 16))
                .foregroundColor(Constants.ContentB)

            ForEach(group.members, id: \.userId) { row in
                MemberExpenseBreakdown(
                    member: row,
                    isCurrentUser: currentUserId.map { Int(row.userId) == $0 } ?? false,
                    homeCurrency: currency,
                    localCurrency: service.primaryLocalCurrency
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .padding(.bottom, 0)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func groupNote(isOver: Bool) -> String {
        isOver
            ? String(localized: "Your group spending has exceeded the shared budget. Review expenses, and add new budget.", comment: "Group insight note when over budget")
            : String(localized: "Your group is still within the shared budget. Track total spending, remaining balance, and daily safe spend to keep the trip financially on pace.", comment: "Group insight note when within budget")
    }

    // MARK: - Reusable tiles

    @ViewBuilder
    private func amountTile(
        title: LocalizedStringKey,
        amount: Double,
        color: Color,
        isLoading: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(Font.custom("Be Vietnam Pro", size: 16))
                .foregroundColor(Constants.ContentB)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            Text(formatAmount(amount))
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .foregroundColor(color)
                .redacted(reason: isLoading ? .placeholder : [])
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Constants.Surface)
        .cornerRadius(16)
    }

    @ViewBuilder
    private func healthTile(health: Health) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Health")
                .font(Font.custom("Be Vietnam Pro", size: 16))
                .foregroundColor(Constants.ContentB)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            Text(health.label)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(health.color)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(width: 100, alignment: .topLeading)
        .background(Constants.Surface)
        .cornerRadius(16)
    }


    @ViewBuilder
    private func categoryChartCard(categories: [TripSpendingCategory]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Spending categories")
                        .font(Font.custom("Be Vietnam Pro", size: 16))
                        .foregroundColor(Constants.ContentB)

                    Text("Expenses by category")
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .foregroundColor(Constants.ContentM)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .padding(0)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 0)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .center)

            TripSpendingCategoryChart(
                categories: categories,
                currency: currency,
                currencySymbol: currencySymbol
            )
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Constants.Surface)
        .cornerRadius(16)
    }

    // MARK: - Currency formatting

    private func formatAmount(_ amount: Double) -> String {
        TripInsightSection.formatAmount(
            amount,
            currency: currency,
            symbol: currencySymbol
        )
    }

    fileprivate static func formatAmount(
        _ amount: Double,
        currency: Currency?,
        symbol: String
    ) -> String {
        let isNegative = amount < 0
        let abs = Swift.abs(amount)
        let whole = CurrencyFormatter.formatWhole(abs)
        let decimal = (currency?.decimalPlaces ?? 0) > 0
            ? CurrencyFormatter.formatDecimal(abs)
            : ""
        let sign = isNegative ? "-" : ""
        return "\(sign)\(whole)\(decimal) \(symbol)"
    }
}

// MARK: - View models

@MainActor
private struct PersonalInsight {
    let myExpenses: Double
    let remaining: Double
    let categories: [TripSpendingCategory]

    init(service: TripDetailService, currentUserId: Int?) {
        guard
            let userId = currentUserId,
            let me = service.breakdown?.members.first(where: { Int($0.userId) == userId })
        else {
            self.myExpenses = 0
            self.remaining = 0
            self.categories = []
            return
        }

        // "Your expenses" is the user's split-share across all expenses
        // (what they actually owe / consumed), not the full amount they paid
        // for the group. For a $10 expense split between 2 people, this is $5.
        self.myExpenses = me.totalShare
        self.remaining = me.netBalance

        // Personal category totals: my shareAmount per expense, grouped by
        // category. BreakdownExpenseItemDto doesn't carry category, so look it
        // up against the full expense list. Sum equals myExpenses.
        let categoryByExpense: [Int: CategoryChip.Category] = service.expenses.reduce(
            into: [:]
        ) { partial, expense in
            let cat = CategoryChip.Category(apiValue: expense.category.value1.rawValue) ?? .other
            partial[Int(expense.id)] = cat
        }

        var totals: [CategoryChip.Category: Double] = [:]
        for share in me.expenses {
            let cat = categoryByExpense[Int(share.expenseId)] ?? .other
            totals[cat, default: 0] += share.shareAmount
        }

        self.categories = TripSpendingCategory.makeOrdered(totals: totals)
    }
}

@MainActor
private struct GroupInsight {
    let totalBudget: Double
    let totalSpent: Double
    let safeDailySpend: Double
    let health: Health
    let categories: [TripSpendingCategory]
    let members: [MemberBreakdownDto]

    var remaining: Double { totalBudget - totalSpent }

    init(service: TripDetailService) {
        let totalBudget = service.totalBudget
        let totalSpent = service.totalSpent
        let remaining = totalBudget - totalSpent

        let startDate = GroupInsight.parseDate(service.trip?.startDate)
        let endDate = GroupInsight.parseDate(service.trip?.endDate)

        // Safe daily spend = remaining / days left including today. The day count
        // comes from the same schedule the day-tab strip uses (start date +
        // planned day count via `availablePlanningDays()`), so it stays correct
        // even when the trip has no explicit endDate set.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let totalDays = max(1, service.availablePlanningDays().count)
        let daysRemaining: Int = {
            guard let startDate else { return totalDays } // no calendar anchor → spread over planned days
            let startDay = calendar.startOfDay(for: startDate)
            let endDay = calendar.date(byAdding: .day, value: totalDays - 1, to: startDay) ?? startDay
            if today < startDay { return totalDays } // not started → full trip length
            if today > endDay { return 1 } // trip already ended → safe spend = remaining
            let diff = calendar.dateComponents([.day], from: today, to: endDay).day ?? 0
            return max(1, diff + 1) // +1 → inclusive of both today and the end day
        }()
        self.safeDailySpend = max(0, remaining) / Double(daysRemaining)

        // Health
        self.health = GroupInsight.computeHealth(
            totalBudget: totalBudget,
            totalSpent: totalSpent,
            remaining: remaining,
            startDate: startDate,
            endDate: endDate,
            today: today,
            calendar: calendar
        )

        self.totalBudget = totalBudget
        self.totalSpent = totalSpent

        // Group category totals: full expense.amount, grouped by category.
        var totals: [CategoryChip.Category: Double] = [:]
        for expense in service.expenses {
            let cat = CategoryChip.Category(apiValue: expense.category.value1.rawValue) ?? .other
            totals[cat, default: 0] += expense.amount
        }
        self.categories = TripSpendingCategory.makeOrdered(totals: totals)

        // Member rows
        self.members = service.breakdown?.members ?? []
    }

    private static func computeHealth(
        totalBudget: Double,
        totalSpent: Double,
        remaining: Double,
        startDate: Date?,
        endDate: Date?,
        today: Date,
        calendar: Calendar
    ) -> Health {
        if remaining < 0 { return .bad }
        if totalBudget == 0 { return .good }
        guard let startDate, let endDate else { return .good }

        let startDay = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)

        if today < startDay { return .good }       // not started
        if today >= endDay { return .good }        // ended (and remaining ≥ 0)

        let totalDays = max(1, calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 1)
        let elapsedDays = max(1, calendar.dateComponents([.day], from: startDay, to: today).day ?? 1)
        let expectedSpent = totalBudget * Double(elapsedDays) / Double(totalDays)
        return totalSpent > expectedSpent ? .warning : .good
    }

    private static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFractional.date(from: string) { return d }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: string) { return d }
        let dateOnly = DateFormatter()
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        dateOnly.dateFormat = "yyyy-MM-dd"
        return dateOnly.date(from: string)
    }
}

private enum Health {
    case good, warning, bad

    var label: String {
        switch self {
        case .good: return String(localized: "Good", comment: "Budget health status")
        case .warning: return String(localized: "Warning", comment: "Budget health status")
        case .bad: return String(localized: "Bad", comment: "Budget health status")
        }
    }

    var color: Color {
        switch self {
        case .good: return Constants.Green500
        case .warning: return Constants.Warning500
        case .bad: return Constants.Secondary
        }
    }
}

// MARK: - Spending category model

private struct TripSpendingCategory: Identifiable, Equatable {
    let category: CategoryChip.Category
    let amount: Double
    let isHighlighted: Bool

    var id: CategoryChip.Category { category }
    var title: String { category.title }

    /// Build a stable, ordered array from a category→amount dictionary.
    /// Order: food, stay, ticket, transport, other (matching the original visual layout).
    /// Highlights the largest non-zero category.
    static func makeOrdered(totals: [CategoryChip.Category: Double]) -> [TripSpendingCategory] {
        let order: [CategoryChip.Category] = [.food, .stay, .ticket, .transport, .other]
        let maxAmount = totals.values.max() ?? 0
        return order.map { cat in
            let amount = totals[cat] ?? 0
            return TripSpendingCategory(
                category: cat,
                amount: amount,
                isHighlighted: amount > 0 && amount == maxAmount
            )
        }
    }
}

// MARK: - Chart

private struct TripSpendingCategoryChart: View {
    let categories: [TripSpendingCategory]
    let currency: Currency?
    let currencySymbol: String

    @State private var selectedID: TripSpendingCategory.ID?

    private var grandTotal: Double {
        categories.reduce(0) { $0 + $1.amount }
    }

    private var displayedAmount: Double {
        if let id = selectedID, let cat = categories.first(where: { $0.id == id }) {
            return cat.amount
        }
        return grandTotal
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                let spacing: CGFloat = 1
                let topInset: CGFloat = 58
                let plotHeight = max(proxy.size.height - topInset, 1)
                let count = max(categories.count, 1)
                let barWidth = max(
                    (proxy.size.width - spacing * CGFloat(count - 1)) / CGFloat(count),
                    1
                )

                ZStack(alignment: .top) {
                    Text(formattedDisplayedAmount)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Constants.BlueBase,
                                    Constants.BlueBase.opacity(0.38),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .contentTransition(.numericText(value: displayedAmount))
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: displayedAmount)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)

                    HStack(alignment: .bottom, spacing: spacing) {
                        ForEach(categories) { _ in
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Constants.Neutral100)
                                .frame(width: barWidth, height: plotHeight)
                        }
                    }
                    .padding(.top, topInset)

                    HStack(alignment: .bottom, spacing: spacing) {
                        ForEach(categories) { category in
                            ZStack(alignment: .bottom) {
                                Color.clear
                                    .frame(width: barWidth, height: plotHeight)

                                TripSpendingCategoryBar(
                                    category: category,
                                    width: barWidth,
                                    height: barHeight(for: category, plotHeight: plotHeight),
                                    isSelected: selectedID == category.id,
                                    hasSelection: selectedID != nil
                                )
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                UIImpactFeedbackGenerator(style: .light)
                                    .impactOccurred()

                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    selectedID = (selectedID == category.id) ? nil : category.id
                                }
                            }
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .frame(height: 321)
            .frame(maxWidth: .infinity)
            .background(Constants.Neutral50)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(alignment: .top, spacing: 2) {
                ForEach(categories) { category in
                    Text(category.title)
                        .font(Font.custom("Be Vietnam Pro", size: 16))
                        .foregroundColor(Constants.textSoft400)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spending categories")
        .accessibilityValue(formattedDisplayedAmount)
    }

    private var formattedDisplayedAmount: String {
        TripInsightSection.formatAmount(
            displayedAmount,
            currency: currency,
            symbol: currencySymbol
        )
    }

    private func barHeight(
        for category: TripSpendingCategory,
        plotHeight: CGFloat
    ) -> CGFloat {
        guard let maxAmount = categories.map(\.amount).max(), maxAmount > 0 else {
            return 12
        }
        return max(12, plotHeight * CGFloat(category.amount / maxAmount))
    }
}

private struct TripSpendingCategoryBar: View {
    let category: TripSpendingCategory
    let width: CGFloat
    let height: CGFloat
    let isSelected: Bool
    let hasSelection: Bool

    /// Apply highlighted gradient when:
    /// - explicitly selected, OR
    /// - nothing is selected AND this is the natural-highlight category.
    private var useHighlightFill: Bool {
        isSelected || (!hasSelection && category.isHighlighted)
    }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(fillStyle)

            icon
                .frame(width: 24, height: 24)
                .padding(.top, 8)
        }
        .frame(width: width, height: height)
        .accessibilityLabel(category.title)
        .accessibilityValue("\(Int(category.amount))")
    }

    @ViewBuilder
    private var icon: some View {
        if category.category == .other {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
        } else {
            Image(category.category.lightIconName)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
        }
    }

    private var fillStyle: LinearGradient {
        if useHighlightFill {
            return LinearGradient(
                colors: [
                    Constants.BlueBase,
                    Constants.BlueBase.opacity(0.68),
                    Constants.Neutral50,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        return LinearGradient(
            colors: [
                Constants.ContentL,
                Constants.ContentL,
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
