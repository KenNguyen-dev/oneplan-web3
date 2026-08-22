import SwiftUI

struct EditBudgetView: View {
    let tripId: Int
    let members: [TripMemberDto]
    let service: TripDetailService
    let editingBudget: BudgetDto

    @Environment(\.dismiss) private var dismiss

    @State private var budgetName: String
    @State private var currentAmount: Double
    @State private var selectedDate: Date
    @State private var selectedTime: Date
    @State private var isAllSelected: Bool
    @State private var selectedContributorIds: Set<Int>
    @State private var selectedInputCurrency: Currency

    @State private var showDatePicker = false
    @State private var showTimePicker = false

    @State private var showErrorAlert = false
    @State private var errorAlertMessage = String(localized: "Something went wrong")

    @State private var isShowingDeleteAlert = false

    init(
        tripId: Int,
        members: [TripMemberDto],
        service: TripDetailService,
        editingBudget: BudgetDto
    ) {
        self.tripId = tripId
        self.members = members
        self.service = service
        self.editingBudget = editingBudget

        let budgetCreatedAt =
            Self.parseISO8601(editingBudget.createdAt) ?? Date()
        _budgetName = State(initialValue: editingBudget.name)

        // Currency-aware initial values. Prefer the row's `originalAmount` /
        // `originalCurrency` if set (non-home rows). Fall back to the
        // converted `amount` and the trip home currency for legacy rows
        // saved before the second-currency feature.
        let tripHomeCurrency =
            Currency(from: service.trip?.currency.value1) ?? .VND
        let resolvedOriginalCurrency: Currency? =
            editingBudget.originalCurrency.flatMap {
                Currency(from: $0.value1)
            }
        let initialCurrency = resolvedOriginalCurrency ?? tripHomeCurrency
        let initialAmount =
            editingBudget.originalAmount ?? editingBudget.amount

        _currentAmount = State(initialValue: initialAmount)
        _selectedInputCurrency = State(initialValue: initialCurrency)
        _selectedDate = State(initialValue: budgetCreatedAt)
        _selectedTime = State(initialValue: budgetCreatedAt)

        let accepted = members.filter { $0.inviteStatus.value1 == .ACCEPTED }
        let acceptedIds = Set(accepted.map { Int($0.userId) })
        let budgetContributorIds = Set(
            editingBudget.payments.map { Int($0.userId) }
        )

        if acceptedIds.isEmpty {
            _isAllSelected = State(initialValue: false)
            _selectedContributorIds = State(initialValue: budgetContributorIds)
        } else if budgetContributorIds == acceptedIds
            || budgetContributorIds.count >= acceptedIds.count
        {
            _isAllSelected = State(initialValue: true)
            _selectedContributorIds = State(initialValue: [])
        } else {
            _isAllSelected = State(
                initialValue: false
            )
            _selectedContributorIds = State(
                initialValue: budgetContributorIds.intersection(acceptedIds)
            )
        }
    }

    private var acceptedMembers: [TripMemberDto] {
        members.filter { $0.inviteStatus.value1 == .ACCEPTED }
    }

    private var acceptedMemberIds: [Int] {
        acceptedMembers.map { Int($0.userId) }
    }

    private var canSave: Bool {
        let hasContributorSelection: Bool =
            acceptedMemberIds.isEmpty
            ? !selectedContributorIds.isEmpty
            : (isAllSelected || !selectedContributorIds.isEmpty)

        return !budgetName.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
            && currentAmount > 0
            && hasContributorSelection
            && !service.isUpdatingBudget
            && !service.isDeletingBudget
    }

    private var formattedDate: String {
        DisplayFormatters.date(selectedDate)
    }

    private var formattedTime: String {
        DisplayFormatters.time(selectedTime)
    }

    private var createdById: Int? {
        service.trip?.createdById
    }

    private var createdByMember: TripMemberDto? {
        guard let createdById else { return nil }
        return members.first { Int($0.userId) == createdById }
    }

    private var createdByName: String {
        createdByMember?.displayName ?? String(localized: "Unknown")
    }

    private var createdByAvatarUrl: String? {
        createdByMember?.avatarUrl
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: max(56, geo.size.height * 0.18))

                    amountSection
                        .padding(.horizontal, 16)

                    Spacer()
                        .frame(height: max(56, geo.size.height * 0.18))

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
            ToolbarItemGroup(placement: .topBarTrailing) {
                HStack(spacing: -4) {
                    ToolbarIconButton(
                        systemName: "trash",
                        foregroundColor: Constants.Warning500,
                        horizontalPadding: 13
                    ) {
                        dismissKeyboard()
                        isShowingDeleteAlert = true
                    }

                    ToolbarIconButton(
                        systemName: "checkmark",
                        horizontalPadding: 11,
                        verticalPadding: 11
                    ) {
                        saveBudget()
                    }
                }
            }
            .sharedBackgroundHiddenCompat()
        }
        .background(Constants.Background)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay {
            if showDatePicker {
                BottomSheet(
                    isPresented: $showDatePicker,
                    sheetHeight: 300,
                    backdropOpacity: 0.15
                ) { dismiss in
                    VStack(spacing: 0) {
                        Capsule()
                            .fill(Constants.ContentL.opacity(0.55))
                            .frame(width: 35, height: 4.9)
                            .padding(.top, 12)

                        Text("Select Date")
                            .font(
                                Font.beVietnamPro(16, weight: .medium)
                            )
                            .foregroundColor(Constants.ContentB)
                            .padding(.top, 16)

                        DatePicker(
                            "",
                            selection: $selectedDate,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(height: 180)

                        Button {
                            dismiss()
                        } label: {
                            Text("Done")
                                .font(
                                    Font.beVietnamPro(16, weight: .medium)
                                )
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
                BottomSheet(
                    isPresented: $showTimePicker,
                    sheetHeight: 300,
                    backdropOpacity: 0.15
                ) { dismiss in
                    VStack(spacing: 0) {
                        Capsule()
                            .fill(Constants.ContentL.opacity(0.55))
                            .frame(width: 35, height: 4.9)
                            .padding(.top, 12)

                        Text("Select Time")
                            .font(
                                Font.beVietnamPro(16, weight: .medium)
                            )
                            .foregroundColor(Constants.ContentB)
                            .padding(.top, 16)

                        DatePicker(
                            "",
                            selection: $selectedTime,
                            displayedComponents: .hourAndMinute
                        )
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(height: 180)

                        Button {
                            dismiss()
                        } label: {
                            Text("Done")
                                .font(
                                    Font.beVietnamPro(16, weight: .medium)
                                )
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
        .alert("Delete budget?", isPresented: $isShowingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteBudget() }
        } message: {
            Text(
                "This permanently removes \"\(budgetName)\" and all its contribution records. This cannot be undone."
            )
        }
    }

    private var tripCurrency: Currency {
        Currency(from: service.trip?.currency.value1) ?? .VND
    }

    /// The currency this budget was originally authored in (if the row
    /// carries `originalCurrency`), used to ensure the dropdown always
    /// includes it even when the trip has since removed the local currency.
    private var editingOriginalCurrency: Currency? {
        editingBudget.originalCurrency.flatMap {
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
        CurrencyInputField(
            label: "Budget amount",
            currency: service.homeCurrency ?? tripCurrency,
            initialAmount: editingBudget.originalAmount
                ?? editingBudget.amount,
            showDecimals: true,
            subtitle: "Per person",
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

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            EditInfoTextFieldRow(
                title: "Budget name",
                placeholder: "Budget",
                value: $budgetName
            )

            // Button {
            //     showDatePicker = true
            // } label: {
            //     EditInfoRow(title: "Date", value: formattedDate)
            // }
            // .buttonStyle(.plain)

            // Button {
            //     showTimePicker = true
            // } label: {
            //     EditInfoRow(title: "Time", value: formattedTime)
            // }
            // .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                Text("Contributor")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundStyle(Constants.ContentM)
                    .padding(.horizontal, 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        BudgetContributorChip(
                            name: "All",
                            avatarUrl: nil,
                            isAllOption: true,
                            isSelected: isAllSelected,
                            action: {
                                guard !acceptedMemberIds.isEmpty else { return }
                                isAllSelected = true
                                selectedContributorIds.removeAll()
                            }
                        )

                        ForEach(acceptedMembers, id: \.userId) { member in
                            let memberId = Int(member.userId)
                            BudgetContributorChip(
                                name: member.displayName,
                                avatarUrl: member.avatarUrl,
                                isAllOption: false,
                                isSelected: selectedContributorIds.contains(
                                    memberId
                                ),
                                action: {
                                    if isAllSelected {
                                        isAllSelected = false
                                    }
                                    if selectedContributorIds.contains(memberId)
                                    {
                                        selectedContributorIds.remove(memberId)
                                        if selectedContributorIds.isEmpty {
                                            isAllSelected = true
                                        }
                                    } else {
                                        selectedContributorIds.insert(memberId)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.top, 4)
                    .padding(.horizontal, 2)
                }
            }
            .padding(.top, 6)

            HStack(spacing: 8) {
                Text("Created by")
                    .font(Font.custom("Be Vietnam Pro", size: 16))
                    .foregroundStyle(Constants.ContentM)

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    ContributorAvatarView(avatarUrl: createdByAvatarUrl)
                        .frame(width: 22, height: 22)
                    Text(createdByName)
                        .font(Font.custom("Be Vietnam Pro", size: 16))
                        .foregroundStyle(Constants.ContentB)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(Constants.Surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func saveBudget() {
        let trimmedName = budgetName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmedName.isEmpty else { return }

        let amount = currentAmount
        guard amount > 0 else {
            errorAlertMessage = String(localized: "Budget amount must be greater than 0.")
            showErrorAlert = true
            return
        }

        let allMemberIds = acceptedMemberIds
        let contributorIds: [Int] = {
            if isAllSelected {
                return allMemberIds.isEmpty
                    ? selectedContributorIds.sorted() : allMemberIds
            }
            if allMemberIds.isEmpty {
                return selectedContributorIds.sorted()
            }
            return allMemberIds.filter { selectedContributorIds.contains($0) }
        }()
        guard !contributorIds.isEmpty else {
            errorAlertMessage = String(localized: "Budget must have at least one contributor.")
            showErrorAlert = true
            return
        }

        let homeCurrency = service.homeCurrency ?? tripCurrency
        let isLocal = selectedInputCurrency != homeCurrency

        Task {
            let success = await service.updateBudget(
                tripId: tripId,
                budgetId: Int(editingBudget.id),
                name: trimmedName,
                amount: amount,
                contributorUserIds: contributorIds,
                originalAmount: isLocal ? amount : nil,
                originalCurrency: isLocal ? selectedInputCurrency : nil
            )

            if success {
                dismiss()
            } else {
                errorAlertMessage = service.error ?? String(localized: "Failed to update budget")
                showErrorAlert = true
            }
        }
    }

    private func deleteBudget() {
        Task {
            let success = await service.deleteBudget(
                tripId: tripId,
                budgetId: Int(editingBudget.id)
            )
            if success {
                dismiss()
            } else {
                errorAlertMessage = service.error ?? String(localized: "Failed to delete budget")
                showErrorAlert = true
            }
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private static func parseISO8601(_ raw: String) -> Date? {
        let formatterWithFraction = ISO8601DateFormatter()
        formatterWithFraction.formatOptions = [
            .withInternetDateTime, .withFractionalSeconds,
        ]
        if let date = formatterWithFraction.date(from: raw) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }
}

private struct BudgetContributorChip: View {
    let name: String
    let avatarUrl: String?
    let isAllOption: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    if isAllOption {
                        Circle()
                            .fill(Constants.Black)
                            .frame(width: 36, height: 36)

                        Image(systemName: "person.3.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Constants.White)
                    } else {
                        ContributorAvatarView(avatarUrl: avatarUrl)
                            .frame(width: 36, height: 36)
                    }
                }
                .overlay {
                    Circle()
                        .stroke(
                            isSelected ? Constants.BlueBase : Color.clear,
                            lineWidth: 2
                        )
                }

                Text(name)
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundStyle(
                        isSelected ? Constants.BlueBase : Constants.ContentM
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 58)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ContributorAvatarView: View {
    let avatarUrl: String?

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
                Image("avatarPlaceholder")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .clipShape(Circle())
        } else {
            Image("avatarPlaceholder")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(Circle())
        }
    }
}
