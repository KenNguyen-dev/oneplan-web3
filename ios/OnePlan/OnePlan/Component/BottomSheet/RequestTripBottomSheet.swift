import SwiftUI

struct RequestTripBottomSheetContent: View {
    var destinationText: String?
    @Binding var selectedTag: Components.Schemas.ListingTag
    @Binding var selectedCurrency: Currency?
    @Binding var budgetText: String
    var onLocationSelected: (CityDto?, StateDto, CountryDto) -> Void
    var isSubmitting: Bool = false
    var onSubmit: () -> Void

    @State private var isShowingLocationPicker = false
    @State private var isShowingTagPicker = false
    @State private var isShowingCurrencyPicker = false

    var body: some View {
        VStack(spacing: 12) {
            grabber

            header
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                RequestPlanPickerRow(
                    text: destinationText ?? String(localized: "Where will you go?"),
                    isPlaceholder: destinationText == nil,
                    action: { isShowingLocationPicker = true }
                )

                RequestPlanPickerRow(
                    text: selectedTag.requestPlanTitle,
                    isPlaceholder: false,
                    action: { isShowingTagPicker = true }
                )

                RequestPlanBudgetRow(
                    budgetText: $budgetText,
                    currencyText: selectedCurrency?.rawValue ?? "VND",
                    onCurrencyTap: { isShowingCurrencyPicker = true }
                )

                Text("We'll send you notification when the plan is available. Please find it on Market after you received it.")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundStyle(Constants.ContentM)
                    .tracking(-0.28)
                    .lineSpacing(0)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            Button {
                onSubmit()
            } label: {
                Group {
                    if isSubmitting {
                        ProgressView()
                            .tint(Constants.White)
                    } else {
                        Text("Submit a request")
                            .font(Font.custom("Be Vietnam Pro", size: 17))
                            .foregroundStyle(Constants.White)
                            .tracking(-0.68)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.28, green: 0.73, blue: 1),
                            Color(red: 0.2, green: 0.68, blue: 0.96)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    in: Capsule()
                )
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 1)
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Constants.Surface)
        .sheet(isPresented: $isShowingLocationPicker) {
            TripLocationPickerSheet(
                isPresented: $isShowingLocationPicker,
                onLocationSelected: onLocationSelected
            )
        }
        .sheet(isPresented: $isShowingTagPicker) {
            TagPickerBottomSheet(selectedTag: $selectedTag)
        }
        .sheet(isPresented: $isShowingCurrencyPicker) {
            CurrencyPickerBottomSheet(
                selectedCurrency: $selectedCurrency,
                showsNoneOption: false
            )
        }
    }

    private var grabber: some View {
        Capsule()
            .fill(Color(UIColor(red: 0.24, green: 0.24, blue: 0.26, alpha: 0.3)))
            .frame(width: 35, height: 5)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Request a plan")
                .font(Font.custom("Be Vietnam Pro", size: 20))
                .foregroundStyle(Constants.Neutral950)
                .tracking(-0.8)

            Text("Please fill in the form below to request new plan")
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundStyle(Constants.Neutral950)
                .tracking(-0.28)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

private struct RequestPlanPickerRow: View {
    var text: String
    var isPlaceholder: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(text)
                    .font(Font.custom("Be Vietnam Pro", size: 16))
                    .foregroundStyle(isPlaceholder ? Constants.ContentM : Constants.ContentB)
                    .tracking(-0.32)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Constants.ContentB)
            }
            .padding(.horizontal, 20)
            .frame(height: 58)
            .background(Constants.Background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct RequestPlanBudgetRow: View {
    @Binding var budgetText: String
    var currencyText: String
    var onCurrencyTap: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("", text: $budgetText, prompt: Text("Your budget").foregroundColor(Constants.ContentM))
                .font(Font.custom("Be Vietnam Pro", size: 16))
                .foregroundStyle(Constants.ContentB)
                .tracking(-0.32)
                .keyboardType(.numberPad)
                .onChange(of: budgetText) { _, newValue in
                    let formatted = Self.formatBudget(newValue)
                    if formatted != newValue {
                        budgetText = formatted
                    }
                }

            Button(action: onCurrencyTap) {
                HStack(spacing: 4) {
                    Text(currencyText)
                        .font(Font.custom("Be Vietnam Pro", size: 16))
                        .foregroundStyle(Constants.White)
                        .tracking(-0.32)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Constants.White)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    Color(red: 0.4, green: 0.4, blue: 0.4),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 20)
        .padding(.trailing, 10)
        .frame(height: 58)
        .background(Constants.Background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Locale-grouped integer formatter (no fraction digits, no sign). Drops any
    /// non-digit the user types (minus signs, letters, stray separators) and
    /// regroups the remaining digits, e.g. "2500000" -> "2,500,000".
    private static let groupingFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        return formatter
    }()

    static func formatBudget(_ raw: String) -> String {
        let digits = raw.filter { $0.isASCII && $0.isNumber }
        guard let value = UInt64(digits) else { return "" }
        return groupingFormatter.string(from: NSNumber(value: value)) ?? ""
    }
}

private extension Components.Schemas.ListingTag {
    var requestPlanTitle: String {
        switch self {
        case .COMPANY:
            return String(localized: "Company")
        case .COUPLES:
            return String(localized: "Couples")
        case .FAMILY:
            return String(localized: "Family")
        case .FRIENDS:
            return String(localized: "Friends")
        case .SOLO:
            return String(localized: "Solo")
        }
    }
}
