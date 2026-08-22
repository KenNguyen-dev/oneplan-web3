//
//  ExpenseCard.swift
//  OnePlan
//
//  Created by Codex on 20/3/26.
//

import SwiftUI

struct ExpenseCard: View {
    let defaultName: String
    var currency: Currency = .VND
    var isActive: Bool = false
    var onNameCommitted: ((String) -> Void)? = nil
    var onAmountChanged: ((CurrencyAmount) -> Void)? = nil
    var availableCurrencies: [Currency] = []
    var initialInputCurrency: Currency? = nil

    init(
        defaultName: String = "Expense 01",
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
        VStack(alignment: .center, spacing: 5) {
            header
            amountSection
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: 290)
        .background(alignment: .top) {
            Image("cardBackground")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .scaleEffect(x: -1, y: 1, anchor: .center)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .inset(by: 2)
                .stroke(
                    .white.opacity(0.9),
                    style: StrokeStyle(lineWidth: 1.5, dash: [2, 3])
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(.blue, lineWidth: 2.0)
                .blur(radius: 5)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color(red: 0.45, green: 0.78, blue: 1, opacity: 0.28), lineWidth: 1)
                .blur(radius: 6)
                .offset(y: 2)
                .mask(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.clear, .white],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
        }
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
        .onAppear {
            if committedTitle.isEmpty {
                committedTitle = defaultName
                titleText = defaultName
                onNameCommitted?(defaultName)
            }
        }
        .onChange(of: titleText) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                onNameCommitted?(trimmed)
            }
        }
        .onChange(of: isTitleFocused) { _, focused in
            if !focused && isEditingTitle {
                commitTitle()
            }
        }
    }

    private func commitTitle() {
        let newTitle = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newTitle.isEmpty {
            committedTitle = newTitle
            onNameCommitted?(newTitle)
        }
        isEditingTitle = false
        isTitleFocused = false
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            ZStack {
                Rectangle()
                    .foregroundColor(.clear)
                    .frame(width: 42.5, height: 63.72061)
                    .background(
                        Image(systemName: "creditcard.and.123")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(Constants.ContentB)
                    )
            }
            .background(.white)
            .frame(width: 42, height: 42, alignment: .center)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(
                color: .black.opacity(0.15),
                radius: 7.8209,
                x: 0,
                y: 1.95522
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .inset(by: 0.24)
                    .stroke(.black.opacity(0.15), lineWidth: 0.48881)
            }

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
                        .lineLimit(1)
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
        .clipShape(RoundedCorners(topLeft: 28, topRight: 28, bottomLeft: 6, bottomRight: 6))
    }

    private var amountSection: some View {
        VStack(alignment: .center, spacing: 8) {
            Spacer()
            

            CurrencyInputField(
                label: "Amount",
                currency: currency,
                autoFocus: isActive,
                onAmountChanged: handleAmountChanged,
                availableCurrencies: availableCurrencies.count >= 2 ? availableCurrencies : nil,
                initialInputCurrency: pendingInputCurrency,
                onInputCurrencyChanged: handleCurrencyChanged
            )

            Spacer()
        }
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .top)
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
}

#Preview {
    ExpenseCard()
}
