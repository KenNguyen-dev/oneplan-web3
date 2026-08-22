import SwiftUI

struct CurrencyPickerBottomSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedCurrency: Currency?
    var showsNoneOption: Bool = false

    @State private var currencyCatalog = CurrencyCatalogService.shared
    @State private var pendingCurrency: Currency?

    var body: some View {
        VStack(spacing: 12) {
            CurrencyPickerToolbar(
                onDismiss: { dismiss() },
                onConfirm: {
                    selectedCurrency = pendingCurrency
                    dismiss()
                }
            )

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    if showsNoneOption {
                        NoneRow(
                            isSelected: pendingCurrency == nil,
                            onTap: { pendingCurrency = nil }
                        )
                    }

                    ForEach(currencyCatalog.currencies, id: \.rawValue) { currency in
                        CurrencyRow(
                            currency: currency,
                            isSelected: pendingCurrency == currency,
                            onTap: { pendingCurrency = currency }
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Constants.Background)
        .presentationDetents([.height(560)])
        .presentationDragIndicator(.visible)
        .onAppear {
            pendingCurrency = selectedCurrency
        }
        .task {
            await currencyCatalog.loadCurrencies()
        }
    }
}

private struct CurrencyPickerToolbar: View {
    let onDismiss: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 9.8) {
            Color.clear
                .frame(width: 35.2, height: 15.6)

            HStack(alignment: .center) {
                Button(action: onDismiss) {
                    ZStack {
                        Circle()
                            .fill(Constants.OnSurface)
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Constants.ContentM)
                    }
                    .frame(width: 43, height: 43)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Currency")
                    .font(Font.custom("Be Vietnam Pro", size: 18))
                    .tracking(-0.72)
                    .foregroundStyle(Constants.ContentB)

                Spacer()

                Button(action: onConfirm) {
                    ZStack {
                        Circle()
                            .fill(Constants.BlueBase)
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 43, height: 43)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct CurrencyRow: View {
    let currency: Currency
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                SelectionIndicator(isSelected: isSelected)

                VStack(alignment: .leading, spacing: 2) {
                    Text(currency.displayName)
                        .font(Font.custom("Be Vietnam Pro", size: 16))
                        .tracking(-0.32)
                        .foregroundStyle(Constants.ContentB)
                        .lineLimit(1)

                    Text("\(currency.rawValue) (\(currency.symbol))")
                        .font(Font.custom("Be Vietnam Pro", size: 13))
                        .tracking(-0.26)
                        .foregroundStyle(Constants.ContentM)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Constants.Background)
            .clipShape(.rect(cornerRadius: 19))
        }
        .buttonStyle(.plain)
    }
}

private struct NoneRow: View {
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                SelectionIndicator(isSelected: isSelected)

                VStack(alignment: .leading, spacing: 2) {
                    Text("None")
                        .font(Font.beVietnamPro(16, weight: .bold))
                        .tracking(-0.32)
                        .foregroundStyle(Constants.ContentB)
                        .lineLimit(1)

                    Text("No local currency")
                        .font(Font.custom("Be Vietnam Pro", size: 13))
                        .tracking(-0.26)
                        .foregroundStyle(Constants.ContentM)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Constants.Background)
            .clipShape(.rect(cornerRadius: 19))
        }
        .buttonStyle(.plain)
    }
}

private struct SelectionIndicator: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Constants.BlueBase : .clear)
                .overlay(
                    Circle()
                        .stroke(
                            isSelected ? Color.clear : Constants.ContentL,
                            lineWidth: 1.5
                        )
                )

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 22, height: 22)
    }
}

#Preview("Group currency (required)") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            CurrencyPickerBottomSheet(
                selectedCurrency: .constant(.USD),
                showsNoneOption: false
            )
        }
}

#Preview("Local currency (optional)") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            CurrencyPickerBottomSheet(
                selectedCurrency: .constant(.THB),
                showsNoneOption: true
            )
        }
}
