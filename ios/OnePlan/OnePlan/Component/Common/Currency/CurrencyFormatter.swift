//
//  CurrencyFormatter.swift
//  OnePlan

import Foundation

/// Currency display metadata resolved from the server currency catalog.
struct Currency: Hashable, Codable, Sendable, Identifiable {
    let code: String
    let name: String
    let symbol: String
    let decimalPlaces: Int

    var id: String { code }
    var rawValue: String { code }
    var displayName: String { name }

    static func == (lhs: Currency, rhs: Currency) -> Bool {
        lhs.code == rhs.code
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(code)
    }

    init(code: String, name: String, symbol: String, decimalPlaces: Int) {
        self.code = code
        self.name = name
        self.symbol = symbol
        self.decimalPlaces = decimalPlaces
    }

    /// Convert from OpenAPI generated Currency type.
    @MainActor
    init?(from apiCurrency: Components.Schemas.Currency?) {
        guard let apiCurrency else { return nil }
        self = CurrencyCatalogService.shared.currency(from: apiCurrency)
    }

    /// Convert from a raw currency code, using server metadata when available.
    @MainActor
    init?(rawValue: String) {
        self = CurrencyCatalogService.shared.currency(forCode: rawValue)
    }

    /// Convert to OpenAPI generated Currency type.
    var toAPICurrency: Components.Schemas.Currency? {
        Components.Schemas.Currency(rawValue: code)
    }

    var apiCurrencyOrFallback: Components.Schemas.Currency {
        toAPICurrency ?? .VND
    }

    static let USD = Currency(code: "USD", name: "US Dollar", symbol: "$", decimalPlaces: 2)
    static let EUR = Currency(code: "EUR", name: "Euro", symbol: "€", decimalPlaces: 2)
    static let VND = Currency(code: "VND", name: "Vietnamese Dong", symbol: "đ", decimalPlaces: 0)
    static let THB = Currency(code: "THB", name: "Thai Baht", symbol: "฿", decimalPlaces: 2)
    static let KRW = Currency(code: "KRW", name: "South Korean Won", symbol: "₩", decimalPlaces: 0)
    static let JPY = Currency(code: "JPY", name: "Japanese Yen", symbol: "¥", decimalPlaces: 0)
    static let CNY = Currency(code: "CNY", name: "Chinese Yuan", symbol: "¥", decimalPlaces: 2)
    static let TWD = Currency(code: "TWD", name: "New Taiwan Dollar", symbol: "NT$", decimalPlaces: 0)
    static let SGD = Currency(code: "SGD", name: "Singapore Dollar", symbol: "S$", decimalPlaces: 2)
    static let MYR = Currency(code: "MYR", name: "Malaysian Ringgit", symbol: "RM", decimalPlaces: 2)

    static let fallbackCurrencies: [Currency] = [
        .VND, .USD, .EUR, .THB, .KRW, .JPY, .CNY, .TWD, .SGD, .MYR,
    ]

    static func fallback(forCode code: String) -> Currency {
        fallbackCurrencies.first { $0.code == code }
            ?? Currency(code: code, name: code, symbol: code, decimalPlaces: 2)
    }
}

/// Centralized currency formatting and parsing.
/// Uses hardcoded `,` grouping separator (not locale-dependent).
enum CurrencyFormatter {
    /// Legacy symbol for views not yet updated to multi-currency.
    @available(*, deprecated, message: "Use currency.symbol instead")
    static let symbol = Currency.VND.symbol

    private static let wholeNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    /// USDC amounts from the vault (micro-USDC / 1e6). Two fraction digits for
    /// display (e.g. `9.61`); whole dollars still show `.00`.
    private static let usdcFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        return formatter
    }()

    /// Formats an on-chain USDC amount without the VND whole/decimal split.
    ///
    /// `formatWhole` + `formatDecimal` are for fiat with exactly 2 places:
    /// `0.999` becomes `"0"` + `".100"` because the fractional cents round to
    /// 100 and `%02d` prints three digits. Vault balances must not use that.
    static func formatUsdc(_ amount: Double) -> String {
        guard amount.isFinite else { return "0.00" }
        return usdcFormatter.string(from: NSNumber(value: amount))
            ?? String(format: "%.2f", amount)
    }

    /// Maximum number of whole-number digits the live formatter will accept.
    /// Caps input so a pathologically large amount can't overflow `Int` in
    /// `formatWhole`/`formatDecimal` (Swift's `Int(Double)` traps when the
    /// value is outside `Int`'s range). 12 digits ⇒ max 999,999,999,999.
    static let maxWholeDigits = 12

    /// Strips non-digit characters, caps at `maxWholeDigits`, re-inserts
    /// commas every 3 digits. `"1234567"` → `"1,234,567"`, `""` → `""`
    static func applyLiveFormatting(to text: String) -> String {
        let digits = String(text.filter(\.isNumber).prefix(maxWholeDigits))
        guard !digits.isEmpty else { return "" }

        var result = ""
        for (index, char) in digits.reversed().enumerated() {
            if index > 0, index % 3 == 0 {
                result.append(",")
            }
            result.append(char)
        }
        return String(result.reversed())
    }

    /// Strips commas and converts to `Double`.
    /// `"1,234,567"` → `1234567.0`
    static func parse(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    /// Decimal-aware live formatting for currencies like USD, THB, EUR.
    /// - Preserves a single `.` separator.
    /// - Strips non-digits (except the single dot).
    /// - Truncates the fractional part to `decimalPlaces` digits.
    /// - Applies comma grouping to the whole portion.
    ///
    /// Examples (decimalPlaces=2):
    ///   `"121"` → `"121"`
    ///   `"121."` → `"121."`
    ///   `"121.87"` → `"121.87"`
    ///   `"1234.567"` → `"1,234.56"` (truncated, not rounded)
    ///   `"1.2.3"` → `"1.23"` (second dot stripped)
    ///   `"0.0"` → `"0.0"`
    ///   `""` → `""`
    ///   `"."` → `"0."` (alone → leading zero)
    static func applyLiveFormatting(to text: String, decimalPlaces: Int) -> String {
        // Zero-decimal currencies (VND, JPY, KRW, TWD) use the integer-only path.
        if decimalPlaces <= 0 {
            return applyLiveFormatting(to: text)
        }

        guard !text.isEmpty else { return "" }

        // 1. Strip everything except digits and dots.
        let sanitized = text.filter { $0.isNumber || $0 == "." }
        guard !sanitized.isEmpty else { return "" }

        // 2. Keep only the first dot; drop subsequent ones.
        var sawDot = false
        var whole = ""
        var fraction = ""
        for char in sanitized {
            if char == "." {
                if sawDot { continue }
                sawDot = true
            } else if sawDot {
                fraction.append(char)
            } else {
                whole.append(char)
            }
        }

        // 3. Truncate fraction to the allowed number of decimal places.
        if fraction.count > decimalPlaces {
            fraction = String(fraction.prefix(decimalPlaces))
        }

        // 4. If user typed just ".", produce "0." so the dot is preserved
        //    and the field remains a valid decimal-entry state.
        if sawDot && whole.isEmpty {
            whole = "0"
        }

        // 5. Group the whole portion with commas.
        let groupedWhole = applyLiveFormatting(to: whole)

        // 6. Re-attach the dot and fraction exactly as typed (so "121." and
        //    "0.0" both round-trip without dropping trailing characters).
        if sawDot {
            return "\(groupedWhole).\(fraction)"
        }
        return groupedWhole
    }

    /// Decimal-aware parser. Strips commas and parses as `Double`.
    /// Works for integer-only currencies too (decimalPlaces=0).
    /// `"1,234.56"` → `1234.56`, `"1,234,567"` → `1234567.0`
    static func parse(_ text: String, decimalPlaces: Int) -> Double {
        _ = decimalPlaces  // Currently unused; kept for API symmetry with applyLiveFormatting.
        let stripped = text.replacingOccurrences(of: ",", with: "")
        return Double(stripped) ?? 0
    }

    /// Formats the whole part with comma separators.
    /// `24500000.15` → `"24,500,000"`
    static func formatWhole(_ amount: Double) -> String {
        // Truncate via Double (no `Int(Double)` trap on out-of-range values).
        guard amount.isFinite else { return "0" }
        let truncated = amount.rounded(.towardZero)
        return wholeNumberFormatter.string(from: NSNumber(value: truncated))
            ?? String(format: "%.0f", truncated)
    }

    /// Formats the decimal part. Uses rounding to avoid IEEE 754 precision issues.
    /// `24500000.15` → `".15"`, `24500000.0` → `".00"`
    ///
    /// NOTE: Hardcoded 2-decimal assumption (×100, `%02d`). All currently
    /// supported non-zero-decimal currencies (USD, EUR, THB, CNY, SGD, MYR)
    /// use 2 places, so this is correct today. TODO: generalize to accept a
    /// `decimalPlaces: Int` parameter if/when a 3-decimal currency (e.g. KWD,
    /// BHD) is added to the `Currency` enum — also update all call sites
    /// (CurrencyDisplayField, CurrencyInputField, TripEndConfirmBottomSheet,
    /// TripEndLeaveSettlementItem, TripEndBreakdownItem, TripEndHeroHeader,
    /// ExpenseDetailView, and the `format(_:currency:showDecimals:)` caller
    /// below) to pass `currency.decimalPlaces`.
    static func formatDecimal(_ amount: Double) -> String {
        guard amount.isFinite else { return ".00" }
        // Truncate via Double; `Int(...)` now only ever sees the bounded
        // fractional part (-100, 100), which never traps.
        let truncated = amount.rounded(.towardZero)
        let decimalPart = Int(round((amount - truncated) * 100))
        return String(format: ".%02d", abs(decimalPart))
    }

    /// Formats an amount with the currency symbol.
    /// `format(1234567, currency: .VND)` → `"đ1,234,567"`
    static func format(_ amount: Double, currency: Currency, showDecimals: Bool = true) -> String {
        let whole = formatWhole(amount)
        if showDecimals && currency.decimalPlaces > 0 {
            return "\(currency.symbol)\(whole)\(formatDecimal(amount))"
        }
        return "\(currency.symbol)\(whole)"
    }
}
