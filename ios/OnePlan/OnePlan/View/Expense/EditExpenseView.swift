import SwiftUI

struct EditExpenseView: View {
    let tripId: Int
    let members: [TripMemberDto]
    let service: TripDetailService
    let editingExpense: ExpenseDetailDto

    @Environment(\.dismiss) private var dismiss

    @State private var expenseName: String
    @State private var currentAmount: Double
    @State private var selectedCategory: CategoryChip.Category
    @State private var selectedDate: Date
    @State private var selectedTime: Date
    @State private var isAllSelected: Bool
    @State private var selectedShareUserIds: Set<Int>
    @State private var selectedInputCurrency: Currency

    @State private var showDatePicker = false
    @State private var showTimePicker = false

    @State private var showErrorAlert = false
    @State private var errorAlertMessage = String(localized: "Something went wrong")

    private let categories: [CategoryChip.Category] = [
        .food, .stay, .ticket, .transport, .other,
    ]

    init(
        tripId: Int,
        members: [TripMemberDto],
        service: TripDetailService,
        editingExpense: ExpenseDetailDto
    ) {
        self.tripId = tripId
        self.members = members
        self.service = service
        self.editingExpense = editingExpense

        _expenseName = State(initialValue: editingExpense.name)

        // Currency-aware initial values. Prefer the row's `originalAmount` /
        // `originalCurrency` if set (non-home rows). Fall back to the
        // converted `amount` and the trip home currency for legacy rows
        // saved before the second-currency feature.
        let tripHomeCurrency =
            Currency(from: service.trip?.currency.value1) ?? .VND
        let resolvedOriginalCurrency: Currency? =
            editingExpense.originalCurrency.flatMap {
                Currency(from: $0.value1)
            }
        let initialCurrency = resolvedOriginalCurrency ?? tripHomeCurrency
        let initialAmount =
            editingExpense.originalAmount ?? editingExpense.amount

        _currentAmount = State(initialValue: initialAmount)
        _selectedInputCurrency = State(initialValue: initialCurrency)
        _selectedCategory = State(
            initialValue: Self.mapCategory(editingExpense.category.value1)
        )

        let expenseDate = Self.parseISO8601(editingExpense.expenseDate) ?? Date()
        _selectedDate = State(initialValue: expenseDate)
        _selectedTime = State(initialValue: expenseDate)

        let accepted = members.filter { $0.inviteStatus.value1 == .ACCEPTED }
        let acceptedIds = Set(accepted.map { Int($0.userId) })
        let shareIds = Set(editingExpense.shares.map { Int($0.userId) })

        if acceptedIds.isEmpty {
            _isAllSelected = State(initialValue: false)
            _selectedShareUserIds = State(initialValue: shareIds)
        } else if shareIds == acceptedIds || shareIds.count >= acceptedIds.count {
            _isAllSelected = State(initialValue: true)
            _selectedShareUserIds = State(initialValue: [])
        } else {
            _isAllSelected = State(initialValue: false)
            _selectedShareUserIds = State(initialValue: shareIds.intersection(acceptedIds))
        }
    }

    private var acceptedMembers: [TripMemberDto] {
        members.filter { $0.inviteStatus.value1 == .ACCEPTED }
    }

    private var acceptedMemberIds: [Int] {
        acceptedMembers.map { Int($0.userId) }
    }

    private var canSave: Bool {
        let hasShareSelection: Bool =
            acceptedMemberIds.isEmpty
            ? !selectedShareUserIds.isEmpty
            : (isAllSelected || !selectedShareUserIds.isEmpty)

        return !expenseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && currentAmount > 0
            && hasShareSelection
            && !service.isUpdatingExpense
    }

    private var shareMemberIdsToSave: [Int] {
        if isAllSelected {
            return acceptedMemberIds.isEmpty ? selectedShareUserIds.sorted() : acceptedMemberIds
        }
        if acceptedMemberIds.isEmpty {
            return selectedShareUserIds.sorted()
        }
        return acceptedMemberIds.filter { selectedShareUserIds.contains($0) }
    }

    private var formattedDate: String {
        DisplayFormatters.date(selectedDate)
    }

    private var formattedTime: String {
        DisplayFormatters.time(selectedTime)
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: max(56, geo.size.height * 0.16))

                    amountSection
                        .padding(.horizontal, 16)

                    Spacer()
                        .frame(height: max(44, geo.size.height * 0.12))

                    detailsSection
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                }
                .frame(minHeight: geo.size.height, alignment: .top)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .toolbar {
            // ToolbarItem(placement: .topBarLeading) {
            //     Button {
            //         dismiss()
            //     } label: {
            //         HStack(spacing: 8) {
            //             Image(systemName: "arrow.left")
            //                 .font(.system(size: 17, weight: .regular))
            //                 .foregroundStyle(Constants.ContentB)
            //                 .frame(width: 36, height: 36)
            //                 .background(Constants.Surface)
            //                 .clipShape(Circle())

            //             Text("Back")
            //                 .font(Font.beVietnamPro(34 / 2, weight: .regular))
            //                 .tracking(-0.85)
            //                 .foregroundStyle(Constants.ContentB)
            //                 .padding(.horizontal, 12)
            //                 .frame(height: 36)
            //                 .background(Constants.Surface)
            //                 .clipShape(Capsule())
            //         }
            //     }
            //     .buttonStyle(.plain)
            // }
            // .sharedBackgroundHiddenCompat()

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    saveExpense()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Constants.ContentB)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 11)
                        .glassEffectCompat()
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
            }
            .sharedBackgroundHiddenCompat()
        }
        .background(Constants.Background)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay {
            if showDatePicker {
                BottomSheet(isPresented: $showDatePicker, sheetHeight: 300, backdropOpacity: 0.15) { dismiss in
                    VStack(spacing: 0) {
                        Capsule()
                            .fill(Constants.ContentL.opacity(0.55))
                            .frame(width: 35, height: 4.9)
                            .padding(.top, 12)

                        Text("Select Date")
                            .font(Font.beVietnamPro(16, weight: .medium))
                            .foregroundColor(Constants.ContentB)
                            .padding(.top, 16)

                        DatePicker("", selection: $selectedDate, displayedComponents: .date)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(height: 180)

                        Button {
                            dismiss()
                        } label: {
                            Text("Done")
                                .font(Font.beVietnamPro(16, weight: .medium))
                                .foregroundColor(Constants.White)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Constants.BlueBase)
                                .cornerRadius(22)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
            } else if showTimePicker {
                BottomSheet(isPresented: $showTimePicker, sheetHeight: 300, backdropOpacity: 0.15) { dismiss in
                    VStack(spacing: 0) {
                        Capsule()
                            .fill(Constants.ContentL.opacity(0.55))
                            .frame(width: 35, height: 4.9)
                            .padding(.top, 12)

                        Text("Select Time")
                            .font(Font.beVietnamPro(16, weight: .medium))
                            .foregroundColor(Constants.ContentB)
                            .padding(.top, 16)

                        DatePicker("", selection: $selectedTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(height: 180)

                        Button {
                            dismiss()
                        } label: {
                            Text("Done")
                                .font(Font.beVietnamPro(16, weight: .medium))
                                .foregroundColor(Constants.White)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Constants.BlueBase)
                                .cornerRadius(22)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
            }
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorAlertMessage)
        }
    }

    private var tripCurrency: Currency {
        Currency(from: service.trip?.currency.value1) ?? .VND
    }

    /// The currency this expense was originally authored in (if the row
    /// carries `originalCurrency`), used to ensure the dropdown always
    /// includes it even when the trip has since removed the local currency.
    private var editingOriginalCurrency: Currency? {
        editingExpense.originalCurrency.flatMap {
            Currency(from: $0.value1)
        }
    }

    /// Display list for the input dropdown: home + locals (from service)
    /// plus the editing row's original currency if it would otherwise be
    /// missing (orphan). Home is always first (by service contract).
    private var availableCurrencies: [Currency] {
        var result = service.displayCurrencies
        if let orig = editingOriginalCurrency, !result.contains(orig) {
            result.append(orig)
        }
        return result
    }

    private var amountSection: some View {
        VStack(alignment: .center, spacing: 8) {
            TextField("Expense", text: $expenseName)
                .font(Font.custom("Be Vietnam Pro", size: 36 / 2))
                .tracking(-0.7)
                .multilineTextAlignment(.center)
                .foregroundStyle(Constants.ContentB)

            CurrencyInputField(
                label: "",
                currency: service.homeCurrency ?? tripCurrency,
                initialAmount: editingExpense.originalAmount
                    ?? editingExpense.amount,
                showDecimals: true,
                showNegativePrefix: true,
                onAmountChanged: { amount in
                    currentAmount = amount
                },
                availableCurrencies: availableCurrencies.count >= 2
                    ? availableCurrencies : nil,
                initialInputCurrency: selectedInputCurrency,
                onInputCurrencyChanged: { newCurrency in
                    selectedInputCurrency = newCurrency
                }
            )
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                presentDatePicker()
            } label: {
                EditInfoRow(title: "Date", value: formattedDate)
            }
            .buttonStyle(.plain)

            Button {
                presentTimePicker()
            } label: {
                EditInfoRow(title: "Time", value: formattedTime)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                Text("Category")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .tracking(-0.42)
                    .foregroundStyle(Constants.ContentM)
                    .lineLimit(1)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(categories, id: \.title) { category in
                            Button {
                                selectedCategory = category
                            } label: {
                                CategoryChip(
                                    category: category,
                                    isSelected: selectedCategory == category
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 14)
            .background(Constants.Surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("Share with")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .tracking(-0.42)
                    .foregroundStyle(Constants.ContentM)
                    .lineLimit(1)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        EditExpenseShareAllChip(isSelected: isAllSelected) {
                            isAllSelected = true
                            selectedShareUserIds.removeAll()
                        }

                        ForEach(acceptedMembers, id: \.userId) { member in
                            let memberId = Int(member.userId)
                            EditExpenseShareMemberChip(
                                name: member.displayName,
                                avatarUrl: member.avatarUrl,
                                isSelected: selectedShareUserIds.contains(memberId)
                            ) {
                                if isAllSelected {
                                    isAllSelected = false
                                }
                                if selectedShareUserIds.contains(memberId) {
                                    selectedShareUserIds.remove(memberId)
                                    if selectedShareUserIds.isEmpty {
                                        isAllSelected = true
                                    }
                                } else {
                                    selectedShareUserIds.insert(memberId)
                                }
                            }
                        }
                    }
                    .padding(.top, 1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 14)

            HStack(spacing: 8) {
                Text("Created by")
                    .font(Font.custom("Be Vietnam Pro", size: 16))
                    .tracking(-0.64)
                    .foregroundStyle(Constants.ContentM)

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    EditExpenseAvatar(
                        avatarUrl: editingExpense.paidBy?.value1.avatarUrl,
                        fallbackImageName: "avatarPlaceholder"
                    )
                    .frame(width: 18, height: 18)

                    Text(editingExpense.paidBy?.value1.displayName ?? String(localized: "Deleted User"))
                        .font(Font.custom("Be Vietnam Pro", size: 16))
                        .tracking(-0.64)
                        .foregroundStyle(Constants.ContentB)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 14)
            .background(Constants.Surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func saveExpense() {
        let trimmedName = expenseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorAlertMessage = String(localized: "Expense name is required.")
            showErrorAlert = true
            return
        }

        let amount = currentAmount
        guard amount > 0 else {
            errorAlertMessage = String(localized: "Expense amount must be greater than 0.")
            showErrorAlert = true
            return
        }

        let memberIds = shareMemberIdsToSave
        guard !memberIds.isEmpty else {
            errorAlertMessage = String(localized: "Expense must be shared with at least one member.")
            showErrorAlert = true
            return
        }

        let homeCurrency = service.homeCurrency ?? tripCurrency
        let isLocal = selectedInputCurrency != homeCurrency

        Task {
            let success = await service.updateExpense(
                tripId: tripId,
                expenseId: Int(editingExpense.id),
                name: trimmedName,
                amount: amount,
                category: selectedCategory.apiValue,
                note: editingExpense.note,
                expenseDate: combinedExpenseDateISO8601,
                memberIds: memberIds,
                originalAmount: isLocal ? amount : nil,
                originalCurrency: isLocal ? selectedInputCurrency : nil
            )

            if success {
                dismiss()
            } else {
                errorAlertMessage = service.error ?? String(localized: "Failed to update expense")
                showErrorAlert = true
            }
        }
    }

    private func presentDatePicker() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        DispatchQueue.main.async {
            showDatePicker = true
            showTimePicker = false
        }
    }

    private func presentTimePicker() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        DispatchQueue.main.async {
            showTimePicker = true
            showDatePicker = false
        }
    }

    private var combinedExpenseDateISO8601: String {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: "en_US_POSIX")

        var dateComponents = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: selectedTime)

        dateComponents.hour = timeComponents.hour
        dateComponents.minute = timeComponents.minute
        dateComponents.second = timeComponents.second ?? 0

        let combined = calendar.date(from: dateComponents) ?? selectedDate

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: combined)
    }

    /// Exhaustive on purpose: no `default`. When the server adds a category the
    /// build breaks here, which is the point — the previous fallback silently
    /// rendered every unknown category as "Other".
    static func mapCategory(
        _ category: Components.Schemas.ExpenseCategory
    ) -> CategoryChip.Category {
        switch category {
        case .FOOD: return .food
        case .STAY: return .stay
        case .TICKET: return .ticket
        case .TRANSPORT: return .transport
        case .OTHER: return .other
        case .COFFEE: return .coffee
        case .SPA: return .spa
        case .GYM: return .gym
        case .NIGHT_CLUB: return .nightClub
        case .GROCERY: return .grocery
        case .SHOPPING: return .shopping
        case .CINEMA: return .cinema
        case .PHARMACY: return .pharmacy
        case .PARK: return .park
        }
    }

    private static func parseISO8601(_ raw: String) -> Date? {
        let formatterWithFraction = ISO8601DateFormatter()
        formatterWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFraction.date(from: raw) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }
}

private struct EditExpenseShareAllChip: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(Constants.Black)
                        .frame(width: 32, height: 32)

                    Image(systemName: "person.3.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Constants.White)
                }
                .frame(width: 36, height: 36)
                .overlay {
                    Circle()
                        .stroke(
                            isSelected ? Constants.BlueBase : Color.clear,
                            lineWidth: 2
                        )
                }

                Text("All")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .tracking(-0.42)
                    .foregroundStyle(isSelected ? Constants.BlueBase : Constants.ContentM)
                    .lineLimit(1)
                    .frame(width: 52)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct EditExpenseShareMemberChip: View {
    let name: String
    let avatarUrl: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                EditExpenseAvatar(
                    avatarUrl: avatarUrl,
                    fallbackImageName: "avatarPlaceholder"
                )
                .frame(width: 36, height: 36)
                .overlay {
                    Circle()
                        .stroke(
                            isSelected ? Constants.BlueBase : Color.clear,
                            lineWidth: 2
                        )
                }

                Text(name)
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .tracking(-0.42)
                    .foregroundStyle(isSelected ? Constants.BlueBase : Constants.ContentM)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 52)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct EditExpenseAvatar: View {
    let avatarUrl: String?
    let fallbackImageName: String

    var body: some View {
        if let avatarUrl, let url = URL(string: avatarUrl) {
            CachedRemoteImage(
                url: url,
                targetSize: CGSize(width: 44, height: 44)
            ) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Image(fallbackImageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .clipShape(Circle())
        } else {
            Image(fallbackImageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(Circle())
        }
    }
}
