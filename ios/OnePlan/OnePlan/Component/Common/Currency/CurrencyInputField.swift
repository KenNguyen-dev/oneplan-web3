//
//  CurrencyInputField.swift
//  OnePlan

import SwiftUI

/// Pairs an amount with the currency it is denominated in.
/// Parents (BudgetCard / ExpenseCard) combine the `CurrencyInputField`'s
/// `onAmountChanged` + `onInputCurrencyChanged` callbacks into this value
/// to send `originalAmount` + `originalCurrency` to the server.
struct CurrencyAmount: Equatable, Sendable {
    let amount: Double
    let currency: Currency
}

/// Editable currency amount field with auto-comma formatting.
/// Used by BudgetCard and ExpenseCard.
///
/// Two rendering modes:
/// - **Legacy**: `availableCurrencies == nil` (or <= 1 entry) renders the
///   original single-currency layout unchanged.
/// - **Dual-currency**: exactly 2 currencies render a compact converted
///   preview and swap button; 3+ currencies keep an inline picker fallback.
struct CurrencyInputField: View {
    let label: LocalizedStringKey
    var currency: Currency = .VND
    var initialAmount: Double = 0
    var showDecimals: Bool = true
    var showNegativePrefix: Bool = false
    var subtitle: LocalizedStringKey? = nil
    var autoFocus: Bool = false
    var onAmountChanged: ((Double) -> Void)? = nil

    // MARK: - Multi-currency parameters (optional, keep legacy call sites working)

    var availableCurrencies: [Currency]? = nil
    var initialInputCurrency: Currency? = nil
    var onInputCurrencyChanged: ((Currency) -> Void)? = nil

    // MARK: - State

    @State private var amountText: String = ""
    @State private var hasInitialized: Bool = false
    @State private var selectedInputCurrency: Currency
    @State private var convertedPreviewText: String? = nil  // nil ⇒ render "—"
    @State private var swapOriginValue: Double? = nil
    @State private var previewTask: Task<Void, Never>? = nil
    @State private var suppressNextOriginReset: Bool = false
    @FocusState private var isFocused: Bool

    // MARK: - Init

    init(
        label: LocalizedStringKey,
        currency: Currency = .VND,
        initialAmount: Double = 0,
        showDecimals: Bool = true,
        showNegativePrefix: Bool = false,
        subtitle: LocalizedStringKey? = nil,
        autoFocus: Bool = false,
        onAmountChanged: ((Double) -> Void)? = nil,
        availableCurrencies: [Currency]? = nil,
        initialInputCurrency: Currency? = nil,
        onInputCurrencyChanged: ((Currency) -> Void)? = nil
    ) {
        self.label = label
        self.currency = currency
        self.initialAmount = initialAmount
        self.showDecimals = showDecimals
        self.showNegativePrefix = showNegativePrefix
        self.subtitle = subtitle
        self.autoFocus = autoFocus
        self.onAmountChanged = onAmountChanged
        self.availableCurrencies = availableCurrencies
        self.initialInputCurrency = initialInputCurrency
        self.onInputCurrencyChanged = onInputCurrencyChanged

        // Clamp the initial selection to something actually present in the
        // dropdown. Legacy path (availableCurrencies == nil) is unchanged:
        // isValidInitial defaults to true, so the resolved value is kept.
        let resolved = initialInputCurrency ?? currency
        let isValidInitial = availableCurrencies?.contains(resolved) ?? true
        let clamped = isValidInitial ? resolved : (availableCurrencies?.first ?? currency)
        self._selectedInputCurrency = State(initialValue: clamped)
    }

    // MARK: - Computed helpers

    /// Currency actually driving the main input (may differ from `currency`
    /// in dual-currency mode after a dropdown pick or swap).
    private var activeCurrency: Currency {
        isDualCurrencyMode ? selectedInputCurrency : currency
    }

    private var parsedAmount: Double {
        if isDualCurrencyMode {
            return CurrencyFormatter.parse(amountText, decimalPlaces: activeCurrency.decimalPlaces)
        }
        // Legacy path — always integer parser regardless of currency.
        return CurrencyFormatter.parse(amountText)
    }

    private var formattedDecimal: String {
        CurrencyFormatter.formatDecimal(parsedAmount)
    }

    private var shouldShowDecimals: Bool {
        showDecimals && activeCurrency.decimalPlaces > 0
    }

    private var isDualCurrencyMode: Bool {
        (availableCurrencies?.count ?? 0) >= 2
    }

    /// The "other" currency the preview is denominated in. Only defined in
    /// exactly-2-currency mode — spec explicitly excludes 3+ from a preview
    /// (the target would silently flip on every dropdown change, producing
    /// confusing UI).
    private var inlinePreviewCounterpart: Currency? {
        guard isDualCurrencyMode,
              let options = availableCurrencies,
              options.count == 2 else {
            return nil
        }
        return options.first { $0 != selectedInputCurrency }
    }

    private var keyboardType: UIKeyboardType {
        // Legacy mode keeps `.numberPad` unconditionally (original behavior).
        // Dual-currency mode switches to `.decimalPad` for decimal-bearing
        // currencies so the user can type '.'.
        guard isDualCurrencyMode else { return .numberPad }
        return activeCurrency.decimalPlaces > 0 ? .decimalPad : .numberPad
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Text(label)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .tracking(-0.28)
                .multilineTextAlignment(.center)
                .foregroundStyle(Constants.ContentB)
                .frame(maxWidth: .infinity, alignment: .top)

            amountRow

            if isDualCurrencyMode {
                dualCurrencyControlRow
            }

            if let subtitle {
                Text(subtitle)
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .tracking(-0.28)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Constants.ContentM)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .onChange(of: autoFocus) { _, newValue in
            if newValue {
                isFocused = true
            }
        }
        .onChange(of: amountText) { _, newValue in
            // Legacy mode: always integer-only formatting (original behavior).
            // Dual-currency mode: respect the active currency's decimal places.
            let decimals = isDualCurrencyMode ? activeCurrency.decimalPlaces : 0
            let formatted = CurrencyFormatter.applyLiveFormatting(
                to: newValue,
                decimalPlaces: decimals
            )
            if formatted != newValue {
                amountText = formatted
                return
            }
            // Genuine user edit — invalidate any swap round-trip breadcrumb
            // unless this onChange came from the swap handler itself. The
            // swap sets `suppressNextOriginReset` right before its definitive
            // `amountText = formattedSeed` write; the flag is consumed on the
            // very next `onChange(of: amountText)` invocation regardless of
            // any intermediate (no-op) side-effects from the
            // `selectedInputCurrency` reformat.
            if suppressNextOriginReset {
                suppressNextOriginReset = false
            } else {
                swapOriginValue = nil
            }
            onAmountChanged?(parsedAmount)
            scheduleConvertedPreviewUpdate()
        }
        .onChange(of: selectedInputCurrency) { _, newValue in
            onInputCurrencyChanged?(newValue)
            // Re-format current text for the new currency's decimal rules
            // (e.g. switching VND → USD must preserve the input as-is but
            // subsequent typing uses decimalPad).
            let reformatted = CurrencyFormatter.applyLiveFormatting(
                to: amountText,
                decimalPlaces: newValue.decimalPlaces
            )
            if reformatted != amountText {
                amountText = reformatted
            }
            scheduleConvertedPreviewUpdate()
        }
        .onChange(of: availableCurrencies ?? []) { _, newAvailable in
            // Re-clamp if the set of currencies changed and the current
            // selection is no longer valid. Happens when the field is
            // constructed before the trip loads (availableCurrencies empty,
            // selectedInputCurrency defaulted to .VND) and then the trip
            // activates dual-currency mode with a set that excludes VND.
            guard !newAvailable.isEmpty,
                  !newAvailable.contains(selectedInputCurrency) else { return }
            selectedInputCurrency = newAvailable.contains(currency)
                ? currency
                : (newAvailable.first ?? currency)
        }
        .onAppear {
            guard !hasInitialized else { return }
            hasInitialized = true
            if initialAmount > 0 {
                if isDualCurrencyMode {
                    let decimals = activeCurrency.decimalPlaces
                    let seed: String
                    if decimals > 0 {
                        seed = String(format: "%.\(decimals)f", initialAmount)
                    } else {
                        seed = CurrencyFormatter.formatWhole(initialAmount)
                    }
                    amountText = CurrencyFormatter.applyLiveFormatting(
                        to: seed,
                        decimalPlaces: decimals
                    )
                } else {
                    // Legacy path — integer-only seed (matches original).
                    amountText = CurrencyFormatter.applyLiveFormatting(
                        to: CurrencyFormatter.formatWhole(initialAmount)
                    )
                }
            }
            if isDualCurrencyMode {
                scheduleConvertedPreviewUpdate()
            }
        }
        .onDisappear {
            previewTask?.cancel()
            previewTask = nil
        }
    }

    // MARK: - Subviews

    private var amountRow: some View {
        HStack(alignment: .center, spacing: showNegativePrefix ? 1 : 3) {
            Text(activeCurrency.symbol)
                .font(.system(size: 36, weight: .regular, design: .rounded))
                .tracking(-0.72)
                .multilineTextAlignment(.center)
                .foregroundStyle(Constants.ContentB.opacity(0.3))

            if showNegativePrefix {
                Text("-")
                    .font(Font.custom("Be Vietnam Pro", size: 36))
                    .tracking(-0.72)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Constants.ContentB)
            }

            TextField("0", text: $amountText)
                .font(Font.custom("Be Vietnam Pro", size: 36))
                .tracking(-0.72)
                .foregroundStyle(Constants.ContentB)
                .keyboardType(keyboardType)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: true, vertical: false)
                .focused($isFocused)

            if shouldShowDecimals {
                // Legacy mode (numberPad) never has a '.' in the text, so the
                // ".00" decorator renders unconditionally — matches original.
                // Dual-currency mode hides the decorator once the user has
                // started typing the fractional portion (e.g. "1.2").
                let textHasDot = amountText.contains(".")
                if !textHasDot {
                    Text(formattedDecimal)
                        .font(Font.custom("Be Vietnam Pro", size: 36))
                        .tracking(-0.72)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Constants.ContentB.opacity(0.3))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var dualCurrencyControlRow: some View {
        if availableCurrencies?.count == 2 {
            figmaConversionRow
        } else {
            legacyCurrencyControlRow
        }
    }

    private var figmaConversionRow: some View {
        HStack(spacing: 8) {
            figmaConvertedPreview

            swapButton
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var legacyCurrencyControlRow: some View {
        HStack(spacing: 8) {
            currencyDropdown

            convertedPreview

            Spacer(minLength: 0)

            if availableCurrencies?.count == 2 {
                swapButton
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var currencyDropdown: some View {
        Menu {
            ForEach(availableCurrencies ?? [], id: \.self) { cur in
                Button {
                    handleDropdownPick(cur)
                } label: {
                    Text("\(cur.displayName) (\(cur.rawValue))")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedInputCurrency.rawValue)
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .tracking(-0.28)
                    .foregroundStyle(Constants.ContentB)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Constants.ContentM)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Constants.OnSurface)
            .clipShape(Capsule())
        }
    }

    private var convertedPreview: some View {
        Group {
            if let counterpart = inlinePreviewCounterpart,
               let preview = convertedPreviewText {
                Text("~\(preview) \(counterpart.rawValue)")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .tracking(-0.28)
                    .foregroundStyle(Constants.ContentM)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text("—")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .tracking(-0.28)
                    .foregroundStyle(Constants.ContentM)
            }
        }
    }

    private var figmaConvertedPreview: some View {
        Group {
            if let counterpart = inlinePreviewCounterpart,
               let preview = convertedPreviewText {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("~\(preview)")
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .tracking(-0.28)

                    Text(counterpart.symbol)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .tracking(-0.28)
                }
                .foregroundStyle(Constants.ContentM)
                .lineLimit(1)
                .truncationMode(.tail)
            } else {
                Text("—")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .tracking(-0.28)
                    .foregroundStyle(Constants.ContentM)
            }
        }
    }

    private var swapButton: some View {
        Button(action: handleSwap) {
            Image("roundTransferVertical")
                .resizable()
                .renderingMode(.original)
                .frame(width: 16.667, height: 16.667)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .disabled(inlinePreviewCounterpart == nil)
    }

    // MARK: - Actions

    private func handleDropdownPick(_ picked: Currency) {
        guard picked != selectedInputCurrency else { return }
        swapOriginValue = nil  // Dropdown pick is an explicit change — drop breadcrumb.
        selectedInputCurrency = picked
    }

    private func handleSwap() {
        guard let counterpart = inlinePreviewCounterpart else { return }

        let currentParsed = parsedAmount
        let previousOrigin = swapOriginValue

        // Empty/zero input has no converted value to seed. Still allow the
        // user to flip the input currency and keep the amount field unchanged.
        guard currentParsed != 0 else {
            swapOriginValue = nil
            selectedInputCurrency = counterpart
            convertedPreviewText = nil
            return
        }

        // Compute the value we will assign to `amountText` after the swap.
        let restoredAmount: Double
        if let previousOrigin {
            // Second (or subsequent) swap — restore the original typed value
            // exactly so A→B→A is a perfect round-trip.
            restoredAmount = previousOrigin
        } else {
            // First swap — use the currently displayed converted preview
            // value. If we don't have a cached rate, bail out.
            guard let rate = ExchangeRateService.shared.cachedRate(
                from: selectedInputCurrency,
                to: counterpart
            ) else { return }
            restoredAmount = currentParsed * rate
        }

        // Record the pre-swap value so the next swap can restore it exactly.
        swapOriginValue = currentParsed

        let decimals = counterpart.decimalPlaces
        let seed: String
        if decimals > 0 {
            seed = String(format: "%.\(decimals)f", restoredAmount)
        } else {
            seed = CurrencyFormatter.formatWhole(restoredAmount)
        }
        let formattedSeed = CurrencyFormatter.applyLiveFormatting(
            to: seed,
            decimalPlaces: decimals
        )

        // Flip the selected currency first; its onChange handler may reformat
        // `amountText`, but that's a transient side-effect — the definitive
        // write is our explicit seed assignment below. Set the suppression
        // flag immediately before that write so the very next amountText
        // onChange (triggered by the seed assignment) consumes the flag.
        selectedInputCurrency = counterpart
        suppressNextOriginReset = true
        amountText = formattedSeed
    }

    // MARK: - Preview fetch

    /// Debounced (200ms) preview refresh. Cancels any in-flight task.
    private func scheduleConvertedPreviewUpdate() {
        previewTask?.cancel()

        guard isDualCurrencyMode,
              let counterpart = inlinePreviewCounterpart else {
            convertedPreviewText = nil
            return
        }

        // Zero input → no preview.
        if parsedAmount == 0 {
            convertedPreviewText = nil
            return
        }

        // If we already have a fresh cached rate, render immediately so the
        // user gets instant feedback — and still run the debounce fetch to
        // refresh on staleness.
        if let cached = ExchangeRateService.shared.cachedRate(
            from: selectedInputCurrency,
            to: counterpart
        ) {
            convertedPreviewText = formatConverted(parsedAmount * cached, in: counterpart)
        }

        let from = selectedInputCurrency
        let amount = parsedAmount
        previewTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            if Task.isCancelled { return }

            do {
                let rate = try await ExchangeRateService.shared.rate(from: from, to: counterpart)
                if Task.isCancelled { return }
                // Guard against state changes during the await. Only abort if
                // the CURRENCY pair changed — the amount may have changed
                // while we awaited (user kept typing), and the next scheduled
                // task will refresh the preview for the new amount.
                guard from == selectedInputCurrency,
                      counterpart == inlinePreviewCounterpart else { return }
                convertedPreviewText = formatConverted(parsedAmount * rate, in: counterpart)
            } catch {
                if Task.isCancelled { return }
                #if DEBUG
                print("[CurrencyInputField] preview fetch \(from.rawValue)→\(counterpart.rawValue) failed: \(error)")
                #endif
                // Only clobber the preview if we didn't already have a
                // cached value shown.
                if ExchangeRateService.shared.cachedRate(from: from, to: counterpart) == nil {
                    convertedPreviewText = nil
                }
            }
        }
    }

    private func formatConverted(_ amount: Double, in currency: Currency) -> String {
        let whole = CurrencyFormatter.formatWhole(amount)
        if currency.decimalPlaces > 0 {
            return "\(whole)\(CurrencyFormatter.formatDecimal(amount))"
        }
        return whole
    }
}

#Preview {
    VStack(spacing: 32) {
        // 1. Legacy single-currency VND — existing behavior.
        CurrencyInputField(
            label: "Amount (VND)",
            currency: .VND,
            showDecimals: true,
            subtitle: "Per person"
        )

        // 2. Dual-currency VND ↔ THB with swap button.
        CurrencyInputField(
            label: "Amount",
            currency: .VND,
            initialAmount: 100_000,
            showDecimals: true,
            subtitle: "Trip currency: VND",
            availableCurrencies: [.VND, .THB],
            initialInputCurrency: .VND
        )

        // 3. Dual-currency with 3 options — no swap button.
        CurrencyInputField(
            label: "Amount",
            currency: .USD,
            initialAmount: 120,
            showDecimals: true,
            subtitle: "Trip currency: USD",
            availableCurrencies: [.USD, .EUR, .JPY],
            initialInputCurrency: .USD
        )
    }
    .padding()
}
