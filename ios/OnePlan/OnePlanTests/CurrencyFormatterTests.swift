//
//  CurrencyFormatterTests.swift
//  OnePlanTests
//
//  Covers both the legacy integer-only `applyLiveFormatting(to:)` path
//  (used by VND/JPY/KRW/TWD) and the new decimal-aware overload
//  `applyLiveFormatting(to:decimalPlaces:)` used by USD/EUR/THB/etc.
//

import Testing
@testable import OnePlan

@Suite("CurrencyFormatter — decimal-aware live formatting")
struct CurrencyFormatterDecimalTests {

    // MARK: - Docstring examples (decimalPlaces = 2)

    @Test("'121' → '121' (whole-only)")
    func wholeOnly() {
        #expect(CurrencyFormatter.applyLiveFormatting(to: "121", decimalPlaces: 2) == "121")
    }

    @Test("'121.' → '121.' (trailing dot preserved)")
    func trailingDotPreserved() {
        #expect(CurrencyFormatter.applyLiveFormatting(to: "121.", decimalPlaces: 2) == "121.")
    }

    @Test("'121.87' → '121.87' (normal decimal)")
    func normalDecimal() {
        #expect(CurrencyFormatter.applyLiveFormatting(to: "121.87", decimalPlaces: 2) == "121.87")
    }

    @Test("'1234.567' → '1,234.56' (fraction truncated, whole grouped)")
    func fractionTruncated() {
        #expect(CurrencyFormatter.applyLiveFormatting(to: "1234.567", decimalPlaces: 2) == "1,234.56")
    }

    @Test("'1.2.3' → '1.23' (second dot stripped)")
    func secondDotStripped() {
        #expect(CurrencyFormatter.applyLiveFormatting(to: "1.2.3", decimalPlaces: 2) == "1.23")
    }

    @Test("'0.0' → '0.0' (leading zero and short fraction preserved)")
    func zeroDotZero() {
        #expect(CurrencyFormatter.applyLiveFormatting(to: "0.0", decimalPlaces: 2) == "0.0")
    }

    @Test("'' → ''")
    func emptyString() {
        #expect(CurrencyFormatter.applyLiveFormatting(to: "", decimalPlaces: 2) == "")
    }

    @Test("'.' alone → '0.'")
    func dotAloneBecomesZeroDot() {
        #expect(CurrencyFormatter.applyLiveFormatting(to: ".", decimalPlaces: 2) == "0.")
    }

    // MARK: - Extra coverage

    @Test("'1234' (whole-only, larger) → '1,234'")
    func wholeOnlyLarger() {
        #expect(CurrencyFormatter.applyLiveFormatting(to: "1234", decimalPlaces: 2) == "1,234")
    }

    @Test("'1234567.89' → '1,234,567.89'")
    func millionsWithDecimals() {
        #expect(CurrencyFormatter.applyLiveFormatting(to: "1234567.89", decimalPlaces: 2) == "1,234,567.89")
    }

    @Test("'abc' → '' (pure non-digits stripped)")
    func pureNonDigits() {
        #expect(CurrencyFormatter.applyLiveFormatting(to: "abc", decimalPlaces: 2) == "")
    }

    @Test("Non-digits around digits are stripped")
    func mixedNonDigits() {
        #expect(CurrencyFormatter.applyLiveFormatting(to: "a1b2c3.4d5", decimalPlaces: 2) == "123.45")
    }

    @Test("Zero decimal places delegates to integer path")
    func zeroDecimalPlacesDelegatesToInteger() {
        // Dot is stripped when decimalPlaces == 0, then the remaining 6 digits
        // are grouped with commas by the integer-only overload.
        #expect(CurrencyFormatter.applyLiveFormatting(to: "1234.56", decimalPlaces: 0) == "123,456")
        #expect(CurrencyFormatter.applyLiveFormatting(to: "1234567", decimalPlaces: 0) == "1,234,567")
    }

    // MARK: - parse(_:decimalPlaces:)

    @Test("parse('1,234.56', decimalPlaces: 2) → 1234.56")
    func parseWithDecimal() {
        #expect(CurrencyFormatter.parse("1,234.56", decimalPlaces: 2) == 1234.56)
    }

    @Test("parse('1,234,567', decimalPlaces: 0) → 1234567")
    func parseInteger() {
        #expect(CurrencyFormatter.parse("1,234,567", decimalPlaces: 0) == 1234567.0)
    }

    @Test("parse empty string → 0")
    func parseEmpty() {
        #expect(CurrencyFormatter.parse("", decimalPlaces: 2) == 0)
    }

    // MARK: - Legacy integer-only path still works

    @Test("Legacy applyLiveFormatting(to:) still groups VND-style amounts")
    func legacyIntegerFormatting() {
        #expect(CurrencyFormatter.applyLiveFormatting(to: "1234567") == "1,234,567")
        #expect(CurrencyFormatter.applyLiveFormatting(to: "") == "")
        #expect(CurrencyFormatter.applyLiveFormatting(to: "abc") == "")
    }

    @Test("Legacy parse(_:) still works")
    func legacyParse() {
        #expect(CurrencyFormatter.parse("1,234,567") == 1234567.0)
    }

    // MARK: - Input cap (maxWholeDigits = 12) — prevents Int overflow crash

    @Test("Integer path caps whole digits at 12")
    func integerCapAt12() {
        // 16 digits in → first 12 kept, grouped.
        #expect(CurrencyFormatter.applyLiveFormatting(to: "1234567890123456") == "123,456,789,012")
    }

    @Test("Exactly 12 digits is not truncated")
    func exactly12DigitsKept() {
        #expect(CurrencyFormatter.applyLiveFormatting(to: "999999999999") == "999,999,999,999")
    }

    @Test("Decimal overload caps whole part at 12, keeps fraction")
    func decimalOverloadCapsWhole() {
        #expect(
            CurrencyFormatter.applyLiveFormatting(to: "12345678901234567.89", decimalPlaces: 2)
                == "123,456,789,012.89"
        )
    }

    // MARK: - Formatter overflow safety (the crash repro)

    @Test("formatWhole does not trap on a value far outside Int range")
    func formatWholeNoOverflowCrash() {
        // Pre-fix this traps `Int(1e30)` and aborts the test runner.
        let result = CurrencyFormatter.formatWhole(1e30)
        #expect(!result.isEmpty)
    }

    @Test("formatDecimal does not trap on a value far outside Int range")
    func formatDecimalNoOverflowCrash() {
        // 1e30 has no representable fractional part → ".00".
        #expect(CurrencyFormatter.formatDecimal(1e30) == ".00")
    }

    @Test("Non-finite input is handled, not crashed")
    func nonFiniteHandled() {
        #expect(CurrencyFormatter.formatWhole(.infinity) == "0")
        #expect(CurrencyFormatter.formatWhole(.nan) == "0")
        #expect(CurrencyFormatter.formatDecimal(.nan) == ".00")
        #expect(CurrencyFormatter.formatDecimal(.infinity) == ".00")
    }

    // MARK: - Truncation semantics preserved for normal values

    @Test("formatWhole still truncates toward zero")
    func formatWholeTruncates() {
        #expect(CurrencyFormatter.formatWhole(24_500_000.15) == "24,500,000")
        #expect(CurrencyFormatter.formatWhole(24_500_000.99) == "24,500,000")
    }

    @Test("formatDecimal still extracts the fractional part")
    func formatDecimalUnchanged() {
        #expect(CurrencyFormatter.formatDecimal(24_500_000.15) == ".15")
        #expect(CurrencyFormatter.formatDecimal(24_500_000.0) == ".00")
    }
}
