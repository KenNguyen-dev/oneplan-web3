//
//  SwiftUIView.swift
//  OnePlan
//
//  Created by ken on 23/2/26.
//

import SwiftUI

struct BudgetCard: View {

    let defaultName: String
    var currency: Currency = .VND
    var isActive: Bool = false
    var onNameCommitted: ((String) -> Void)? = nil
    var onAmountChanged: ((CurrencyAmount) -> Void)? = nil
    var availableCurrencies: [Currency] = []
    var initialInputCurrency: Currency? = nil

    init(
        defaultName: String = "Budget 1",
        currency: Currency = .VND,
        isActive: Bool = false,
        onNameCommitted: ((String) -> Void)? = nil,
        onAmountChanged: ((CurrencyAmount) -> Void)? = nil,
        availableCurrencies: [Currency] = [],
        initialInputCurrency: Currency? = nil
    ) {
        self.defaultName = defaultName
        self.currency = currency
        self.isActive = isActive
        self.onNameCommitted = onNameCommitted
        self.onAmountChanged = onAmountChanged
        self.availableCurrencies = availableCurrencies
        self.initialInputCurrency = initialInputCurrency
        self._pendingInputCurrency = State(
            initialValue: initialInputCurrency ?? currency
        )
    }

    @State private var isEditingTitle: Bool = false
    @State private var titleText: String = ""
    @State private var committedTitle: String = ""
    @State private var pendingInputCurrency: Currency
    @State private var pendingAmountValue: Double = 0
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        cardContent
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(height: 290)
            .background(alignment: .top) { cardBackgroundImage }
            .cornerRadius(32)
            .overlay(blueGlowBorder)
            .overlay(dashedInnerBorder)
            .shadow(color: Color(red: 0.35, green: 0.53, blue: 1).opacity(0.13), radius: 10.35, x: 0, y: 0)
            .shadow(color: Color(red: 0, green: 0.3, blue: 1).opacity(0.2), radius: 3.05, x: 0, y: 2)
            .cornerRadius(32)
            .onAppear(perform: handleAppear)
            .onChange(of: titleText, handleTitleTextChange)
            .onChange(of: isTitleFocused, handleTitleFocusChange)
    }

    private var cardContent: some View {
        VStack(alignment: .center, spacing: 5) {
            headerRow
            Spacer()
            amountField
            Spacer()
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 8) {
            creditCardIcon
            titleEditor
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(.ultraThinMaterial)
        .clipShape(RoundedCorners(topLeft: 32, topRight: 32, bottomLeft: 10, bottomRight: 10))
    }

    private var creditCardIcon: some View {
        HStack(alignment: .center, spacing: 0) {
            Rectangle()
                .foregroundColor(.clear)
                .frame(width: 42.5, height: 63.72061)
                .background(Image(systemName: "creditcard"))
        }
        .background(.white)
        .padding(0)
        .frame(width: 42, height: 42, alignment: .center)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.15), radius: 7.8209, x: 0, y: 1.95522)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .inset(by: 0.24)
                .stroke(.black.opacity(0.15), lineWidth: 0.48881)
        )
    }

    @ViewBuilder
    private var titleEditor: some View {
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
                .onTapGesture(perform: beginTitleEdit)
        }
    }

    private var cardBackgroundImage: some View {
        Image("cardBackground")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .scaleEffect(x: -1, y: 1, anchor: .center)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
    }

    private var blueGlowBorder: some View {
        RoundedRectangle(cornerRadius: 32, style: .continuous)
            .stroke(.blue, lineWidth: 2.0)
            .blur(radius: 5)
    }

    private var dashedInnerBorder: some View {
        RoundedRectangle(cornerRadius: 32, style: .continuous)
            .inset(by: 2)
            .stroke(
                .white.opacity(0.9),
                style: StrokeStyle(lineWidth: 1.5, dash: [2, 3])
            )
    }

    private func beginTitleEdit() {
        titleText = ""
        isEditingTitle = true
        DispatchQueue.main.async { isTitleFocused = true }
    }

    private func handleAppear() {
        if committedTitle.isEmpty {
            committedTitle = defaultName
            titleText = defaultName
            onNameCommitted?(defaultName)
        }
    }

    private func handleTitleTextChange(_ oldValue: String, _ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onNameCommitted?(trimmed)
        }
    }

    private func handleTitleFocusChange(_ oldValue: Bool, _ newValue: Bool) {
        if !newValue && isEditingTitle {
            commitTitle()
        }
    }

    private var amountField: some View {
        CurrencyInputField(
            label: "Amount",
            currency: currency,
            subtitle: "Per person",
            autoFocus: isActive,
            onAmountChanged: handleAmountChanged,
            availableCurrencies: availableCurrencies.count >= 2 ? availableCurrencies : nil,
            initialInputCurrency: pendingInputCurrency,
            onInputCurrencyChanged: handleCurrencyChanged
        )
    }

    private func handleAmountChanged(_ amount: Double) {
        pendingAmountValue = amount
        fireCurrencyAmountCallback()
    }

    private func handleCurrencyChanged(_ newCurrency: Currency) {
        pendingInputCurrency = newCurrency
        fireCurrencyAmountCallback()
    }

    private func fireCurrencyAmountCallback() {
        onAmountChanged?(
            CurrencyAmount(
                amount: pendingAmountValue,
                currency: pendingInputCurrency
            )
        )
    }

    private func commitTitle() {
        let newTitle = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newTitle.isEmpty {
            committedTitle = newTitle
        }
        isEditingTitle = false
        isTitleFocused = false
        onNameCommitted?(committedTitle)
    }
}

#Preview {
    BudgetCard(defaultName: "Budget 1")
}
