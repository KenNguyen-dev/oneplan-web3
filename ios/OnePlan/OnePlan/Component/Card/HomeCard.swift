//
//  SwiftUIView.swift
//  OnePlan
//
//  Created by ken on 23/2/26.
//

import PhotosUI
import SwiftUI
import UIKit

struct FlipEffect: ViewModifier, Animatable {
    var rotation: Double

    var animatableData: Double {
        get { rotation }
        set { rotation = newValue }
    }

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0), perspective: 0.7)
            .opacity(abs(rotation.truncatingRemainder(dividingBy: 360)) < 90 ||
                     abs(rotation.truncatingRemainder(dividingBy: 360)) > 270 ? 1 : 0)
    }
}

// A Shape that supports per-corner radii
struct RoundedCorners: Shape {
    var topLeft: CGFloat = 0
    var topRight: CGFloat = 0
    var bottomLeft: CGFloat = 0
    var bottomRight: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let tl = min(min(topLeft, rect.width / 2), rect.height / 2)
        let tr = min(min(topRight, rect.width / 2), rect.height / 2)
        let bl = min(min(bottomLeft, rect.width / 2), rect.height / 2)
        let br = min(min(bottomRight, rect.width / 2), rect.height / 2)

        var path = Path()

        // Start at top-left
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        // Top edge to top-right corner
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        // Top-right corner
        path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
                    radius: tr,
                    startAngle: Angle(degrees: -90),
                    endAngle: Angle(degrees: 0),
                    clockwise: false)
        // Right edge to bottom-right corner
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        // Bottom-right corner
        path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
                    radius: br,
                    startAngle: Angle(degrees: 0),
                    endAngle: Angle(degrees: 90),
                    clockwise: false)
        // Bottom edge to bottom-left corner
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        // Bottom-left corner
        path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
                    radius: bl,
                    startAngle: Angle(degrees: 90),
                    endAngle: Angle(degrees: 180),
                    clockwise: false)
        // Left edge to top-left corner
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        // Top-left corner
        path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
                    radius: tl,
                    startAngle: Angle(degrees: 180),
                    endAngle: Angle(degrees: 270),
                    clockwise: false)

        path.closeSubpath()
        return path
    }
}

struct HomeCard: View {

    let tripName: String
    let balance: Double
    let usagePercent: Int
    let tripId: Int?
    let coverImageUrl: String?
    var currency: Currency = .VND
    let localCurrency: Currency?
    @Binding var isAddingBudget: Bool
    @Binding var isAddingExpense: Bool
    let expenseResetToken: Int
    let budgetCount: Int
    var onTitleSaved: ((String) -> Void)?
    var onBudgetSave: ((String, CurrencyAmount) -> Void)?
    var onExpenseNameCommitted: ((String) -> Void)?
    var onExpenseAmountChanged: ((CurrencyAmount) -> Void)?
    var onNewExpenseTapped: (() -> Void)?
    var onCoverImageUploaded: (() -> Void)?
    var showsFinancialActions: Bool
    var availableCurrencies: [Currency] = []

    init(
        tripName: String = "Dubai 2025",
        balance: Double = 24_500_000.15,
        usagePercent: Int = 79,
        tripId: Int? = nil,
        coverImageUrl: String? = nil,
        currency: Currency = .VND,
        localCurrency: Currency? = nil,
        isAddingBudget: Binding<Bool> = .constant(false),
        isAddingExpense: Binding<Bool> = .constant(false),
        expenseResetToken: Int = 0,
        budgetCount: Int = 0,
        onTitleSaved: ((String) -> Void)? = nil,
        onBudgetSave: ((String, CurrencyAmount) -> Void)? = nil,
        onExpenseNameCommitted: ((String) -> Void)? = nil,
        onExpenseAmountChanged: ((CurrencyAmount) -> Void)? = nil,
        onNewExpenseTapped: (() -> Void)? = nil,
        onCoverImageUploaded: (() -> Void)? = nil,
        showsFinancialActions: Bool = true,
        availableCurrencies: [Currency] = []
    ) {
        self.tripName = tripName
        self.balance = balance
        self.usagePercent = usagePercent
        self.tripId = tripId
        self.coverImageUrl = coverImageUrl
        self.currency = currency
        self.localCurrency = localCurrency
        self._isAddingBudget = isAddingBudget
        self._isAddingExpense = isAddingExpense
        self.expenseResetToken = expenseResetToken
        self.budgetCount = budgetCount
        self.onTitleSaved = onTitleSaved
        self.onBudgetSave = onBudgetSave
        self.onExpenseNameCommitted = onExpenseNameCommitted
        self.onExpenseAmountChanged = onExpenseAmountChanged
        self.onNewExpenseTapped = onNewExpenseTapped
        self.onCoverImageUploaded = onCoverImageUploaded
        self.showsFinancialActions = showsFinancialActions
        self.availableCurrencies = availableCurrencies
        self._pendingBudgetCurrency = State(initialValue: currency)
        self._pendingExpenseCurrency = State(initialValue: currency)
    }

    private enum CardFace: Equatable {
        case home
        case budget
        case expense
    }

    @State private var isEditingTitle: Bool = false
    @State private var titleText: String = ""
    @State private var committedTitle: String = ""
    @State private var pendingBudgetName: String = ""
    @State private var pendingBudgetAmount: Double = 0
    @State private var pendingBudgetCurrency: Currency
    @State private var pendingExpenseName: String = ""
    @State private var pendingExpenseAmount: Double = 0
    @State private var pendingExpenseCurrency: Currency
    @State private var selectedCoverPhotoItem: PhotosPickerItem?
    @State private var selectedCoverImage: UIImage?
    @State private var storageService = StorageUploadService()
    @State private var convertedBalanceText: String?
    @State private var previewTask: Task<Void, Never>?
    @FocusState private var isTitleFocused: Bool

    private var activeFace: CardFace {
        if isAddingBudget { return .budget }
        if isAddingExpense { return .expense }
        return .home
    }

    var body: some View {
        ZStack {
            homeCardContent
                .modifier(FlipEffect(rotation: activeFace == .home ? 0 : 180))
                .allowsHitTesting(activeFace == .home)

            BudgetCard(
                defaultName: String(localized: "Budget \(budgetCount + 1)", comment: "Default budget name; %lld = next budget number"),
                currency: currency,
                isActive: activeFace == .budget,
                onNameCommitted: { name in
                    pendingBudgetName = name
                    onBudgetSave?(
                        pendingBudgetName,
                        CurrencyAmount(
                            amount: pendingBudgetAmount,
                            currency: pendingBudgetCurrency
                        )
                    )
                },
                onAmountChanged: { currencyAmount in
                    pendingBudgetAmount = currencyAmount.amount
                    pendingBudgetCurrency = currencyAmount.currency
                    onBudgetSave?(pendingBudgetName, currencyAmount)
                },
                availableCurrencies: availableCurrencies,
                initialInputCurrency: pendingBudgetCurrency
            )
                .id(budgetCount)
                .modifier(FlipEffect(rotation: activeFace == .budget ? 0 : -180))
                .allowsHitTesting(activeFace == .budget)

            ExpenseCard(
                defaultName: pendingExpenseName.isEmpty ? "Expense 01" : pendingExpenseName,
                currency: currency,
                isActive: activeFace == .expense,
                onNameCommitted: { name in
                    pendingExpenseName = name
                    onExpenseNameCommitted?(name)
                },
                onAmountChanged: { currencyAmount in
                    pendingExpenseAmount = currencyAmount.amount
                    pendingExpenseCurrency = currencyAmount.currency
                    onExpenseAmountChanged?(currencyAmount)
                },
                availableCurrencies: availableCurrencies,
                initialInputCurrency: pendingExpenseCurrency
            )
                .id(expenseResetToken)
                .modifier(FlipEffect(rotation: activeFace == .expense ? 0 : -180))
                .allowsHitTesting(activeFace == .expense)
        }
        .animation(
            .spring(response: 0.45, dampingFraction: 0.8),
            value: activeFace
        )
        .onChange(of: selectedCoverPhotoItem) { _, newItem in
            Task {
                await updateCoverImage(from: newItem)
            }
        }
        .onChange(of: expenseResetToken) { _, _ in
            pendingExpenseName = ""
            pendingExpenseAmount = 0
            pendingExpenseCurrency = currency
        }
    }

    private var homeCardContent: some View {
        VStack(alignment: .center, spacing: 5) {
            HStack(alignment: .center, spacing: 8) {
                PhotosPicker(selection: $selectedCoverPhotoItem, matching: .images) {
                    tripAvatar
                }
                .buttonStyle(.plain)
                .disabled(storageService.isUploading)
                .accessibilityLabel("Change trip avatar")

                Group {
                    if isEditingTitle {
                        TextField(committedTitle, text: $titleText)
                            .font(Font.custom("Be Vietnam Pro", size: 16))
                            .foregroundColor(Constants.ContentB)
                            .textFieldStyle(.plain)
                            .focused($isTitleFocused)
                            .onSubmit { commitTitle() }
                    } else {
                        Text(committedTitle)
                            .font(Font.custom("Be Vietnam Pro", size: 16))
                            .foregroundColor(Constants.ContentB)
                            .onTapGesture {
                                titleText = ""
                                isEditingTitle = true
                                DispatchQueue.main.async {
                                    isTitleFocused = true
                                }
                            }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(.ultraThinMaterial)
            .clipShape(RoundedCorners(topLeft: 32, topRight: 32, bottomLeft: 10, bottomRight: 10))
            
            Spacer()

            VStack(spacing: 4) {
                CurrencyDisplayField(
                    label: "Balance",
                    amount: balance,
                    currency: currency
                )
                convertedBalanceLine
            }
            .accessibilityElement(children: .combine)

            HStack(alignment: .center, spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Constants.ContentB)
                            .frame(width: geo.size.width, height: geo.size.height)
                        Capsule()
                            .fill(Constants.BlueBase)
                            .frame(width: geo.size.width * CGFloat(usagePercent) / 100, height: geo.size.height)
                    }
                }
                .frame(width: 100, height: 8)

                Text("\(usagePercent)%")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundColor(Constants.ContentB)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Constants.OnSurface)
            .cornerRadius(22)
            
            Spacer()

            if showsFinancialActions {
                HStack(alignment: .top, spacing: 6) {
                    AddBudgetButton {
                        triggerSelectionHaptic()
                        isAddingExpense = false
                        isAddingBudget = true
                    }
                    NewExpenseButton {
                        triggerSelectionHaptic()
                        isAddingBudget = false
                        isAddingExpense = true
                        onNewExpenseTapped?()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: 290)
        .background(alignment: .top) {
            Image("cardBackground")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
        }
        .cornerRadius(32)
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .inset(by: 2)
                .stroke(
                    .white.opacity(0.9),
                    style: StrokeStyle(lineWidth: 1.5, dash: [2, 3])
                )
        )
        .overlay(
             RoundedRectangle(cornerRadius: 32, style: .continuous)
                 .stroke(
                     .blue,
                     lineWidth: 2.0
                 )
                 .blur(radius: 5)
         )
        .shadow(
            color: Color(red: 0.35, green: 0.53, blue: 1).opacity(0.13),
            radius: 10.35,
            x: 0,
            y: 0
        )
        .shadow(
            color: Color(red: 0, green: 0.3, blue: 1).opacity(0.2),
            radius: 3.05,
            x: 0,
            y: 2
        )
        .cornerRadius(32)
        .onAppear {
            if committedTitle.isEmpty {
                committedTitle = tripName
                titleText = tripName
            }
        }
        .onChange(of: tripName) { _, newName in
            if !newName.isEmpty && !isEditingTitle {
                committedTitle = newName
                titleText = newName
            }
        }
        .onChange(of: isTitleFocused) { _, focused in
            if !focused && isEditingTitle {
                commitTitle()
            }
        }
        .onAppear { refreshConvertedBalance() }
        .onChange(of: balance) { _, _ in refreshConvertedBalance() }
        .onChange(of: currency) { _, _ in refreshConvertedBalance() }
        .onChange(of: localCurrency) { _, _ in refreshConvertedBalance() }
        .onDisappear { previewTask?.cancel() }
    }

    private var tripAvatar: some View {
        HStack(alignment: .center, spacing: 0) {
            Rectangle()
                .foregroundColor(.clear)
                .frame(width: 42, height: 42)
                .background(
                    ZStack {
                        tripAvatarImage
                            .frame(width: 42, height: 42)
                            .clipped()

                        if storageService.isUploading {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.white)
                                .frame(width: 42, height: 42)
                                .background(.black.opacity(0.25))
                        }
                    }
                )
        }
        .padding(0)
        .frame(width: 42, height: 42, alignment: .center)
        .cornerRadius(14)
        .shadow(
            color: .black.opacity(0.15),
            radius: 7.8209,
            x: 0,
            y: 1.95522
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .inset(by: 0.24)
                .stroke(.black.opacity(0.15), lineWidth: 0.48881)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var tripAvatarImage: some View {
        if let selectedCoverImage {
            Image(uiImage: selectedCoverImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if let urlString = coverImageUrl, let url = URL(string: urlString) {
            CachedRemoteImage(url: url, targetSize: CGSize(width: 42, height: 42)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Image("defaultTripPlaceholder")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        } else {
            Image("defaultTripPlaceholder")
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
    }

    private func updateCoverImage(from item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data)
        else {
            selectedCoverPhotoItem = nil
            return
        }

        selectedCoverImage = uiImage
        selectedCoverPhotoItem = nil

        guard let tripId else { return }

        do {
            _ = try await storageService.uploadImage(
                uiImage,
                target: .trip_hyphen_cover,
                entityId: tripId
            )
            onCoverImageUploaded?()
        } catch {
            selectedCoverImage = nil
        }
    }

    // TODO: revisit when multi-leg trips are supported — for now we only show the first
    // local currency. A future iteration may cycle through all `localCurrencies` or pick
    // by trip date. The call site passes `service.primaryLocalCurrency` (== localCurrencies.first).
    private var effectiveLocalCurrency: Currency? {
        guard let local = localCurrency, local != currency else { return nil }
        return local
    }

    @ViewBuilder
    private var convertedBalanceLine: some View {
        if let local = effectiveLocalCurrency {
            Group {
                if let preview = convertedBalanceText {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("~\(preview)")
                            .font(Font.custom("Be Vietnam Pro", size: 14))
                            .tracking(-0.28)
                        Text(local.symbol)
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .tracking(-0.28)
                    }
                    .foregroundStyle(Constants.ContentM)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .transition(.opacity)
                } else {
                    Color.clear
                }
            }
            .frame(height: 18)
        }
    }

    private func refreshConvertedBalance() {
        previewTask?.cancel()
        guard let local = effectiveLocalCurrency else {
            convertedBalanceText = nil
            return
        }

        if let cached = ExchangeRateService.shared.cachedRate(from: currency, to: local) {
            convertedBalanceText = formatConvertedBalance(balance * cached, in: local)
            return
        }

        let from = currency
        let to = local
        let amount = balance
        previewTask = Task { @MainActor in
            do {
                let rate = try await ExchangeRateService.shared.rate(from: from, to: to)
                guard !Task.isCancelled,
                      from == currency,
                      to == effectiveLocalCurrency else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    convertedBalanceText = formatConvertedBalance(amount * rate, in: to)
                }
            } catch {
                // Silent failure — reserved space stays empty.
            }
        }
    }

    private func formatConvertedBalance(_ value: Double, in cur: Currency) -> String {
        let whole = CurrencyFormatter.formatWhole(value)
        guard cur.decimalPlaces > 0 else { return whole }
        return whole + CurrencyFormatter.formatDecimal(value)
    }

    private func commitTitle() {
        let newTitle = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newTitle.isEmpty {
            committedTitle = newTitle
            onTitleSaved?(newTitle)
        }
        isEditingTitle = false
        isTitleFocused = false
    }

    private func triggerSelectionHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

#Preview {
    HomeCard()
}
