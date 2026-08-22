import Testing
@testable import OnePlan

/// Builds an EMVCo TLV string: two digit tag, two digit length, then the value.
private func tlv(_ tag: String, _ value: String) -> String {
    tag + String(format: "%02d", value.count) + value
}

private func buildQR(
    bankBin: String,
    account: String,
    amount: String? = nil,
    description: String? = nil
) -> String {
    let merchant = tlv("00", "A000000727")
        + tlv("01", tlv("00", bankBin) + tlv("01", account))
        + tlv("02", "QRIBFTTA")
    var body = tlv("00", "01")
        + tlv("01", amount == nil ? "11" : "12")
        + tlv("38", merchant)
        + tlv("53", "704")
    if let amount { body += tlv("54", amount) }
    body += tlv("58", "VN")
    if let description { body += tlv("62", tlv("08", description)) }
    return body + tlv("63", "ABCD")
}

@Suite("VietQRDecoder")
struct VietQRDecoderTests {

    @Test("extracts bank bin and account from a static code")
    func staticCode() throws {
        let decoded = try VietQRDecoder.decode(
            buildQR(bankBin: "970412", account: "109000636588")
        )
        #expect(decoded.bankBin == "970412")
        #expect(decoded.accountNumber == "109000636588")
        #expect(decoded.amountVnd == nil)
    }

    @Test("extracts the amount from a dynamic code")
    func dynamicCode() throws {
        let decoded = try VietQRDecoder.decode(
            buildQR(bankBin: "970407", account: "19036045678901", amount: "200000")
        )
        #expect(decoded.amountVnd == 200_000)
    }

    @Test("tolerates a trailing decimal on the amount")
    func decimalAmount() throws {
        let decoded = try VietQRDecoder.decode(
            buildQR(bankBin: "970407", account: "1903604", amount: "200000.00")
        )
        #expect(decoded.amountVnd == 200_000)
    }

    @Test("extracts the description when present")
    func description() throws {
        let decoded = try VietQRDecoder.decode(
            buildQR(bankBin: "970436", account: "1234567890", description: "Chuyen tien")
        )
        #expect(decoded.description == "Chuyen tien")
    }

    @Test("rejects a payload with no merchant account field")
    func missingMerchant() {
        let qr = tlv("00", "01") + tlv("53", "704") + tlv("63", "ABCD")
        #expect(throws: VietQRDecodeError.self) { try VietQRDecoder.decode(qr) }
    }

    @Test("rejects a currency other than VND")
    func wrongCurrency() {
        let qr = buildQR(bankBin: "970412", account: "1234")
            .replacingOccurrences(of: tlv("53", "704"), with: tlv("53", "840"))
        #expect(throws: VietQRDecodeError.self) { try VietQRDecoder.decode(qr) }
    }

    @Test("rejects a truncated payload")
    func truncated() {
        #expect(throws: VietQRDecodeError.self) { try VietQRDecoder.decode("0002015802") }
    }

    @Test("rejects an empty payload")
    func empty() {
        #expect(throws: VietQRDecodeError.self) { try VietQRDecoder.decode("") }
    }

    @Test("rejects a non-numeric length field")
    func badLength() {
        #expect(throws: VietQRDecodeError.self) { try VietQRDecoder.decode("00XX01") }
    }
}
