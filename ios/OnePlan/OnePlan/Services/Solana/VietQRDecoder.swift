import Foundation

enum VietQRDecodeError: Error, Equatable {
    case empty
    case truncated
    case badLength(String)
    case missingMerchantAccount
    case missingBeneficiary
    case missingAccount
    case unsupportedCurrency(String)
    case badAmount(String)
}

struct VietQRPayload: Equatable {
    let bankBin: String
    let accountNumber: String
    let amountVnd: UInt64?
    let description: String?
}

/// Minimal EMVCo QR decoder for VietQR.
///
/// The format is a flat sequence of tag-length-value triples: a two digit tag, a
/// two digit decimal length, then that many characters. Tags 38 and 62 nest
/// another TLV sequence inside their value.
///
/// Decoding happens on device: a scanned code is parsed here and only the fields
/// we understand are sent to the server, so an unrecognised payload never leaves
/// the phone.
///
/// Most merchant codes are static and carry no amount, which is why the payment
/// flow asks the user to type one.
enum VietQRDecoder {
    private static let tagMerchantAccount = "38"
    private static let tagCurrency = "53"
    private static let tagAmount = "54"
    private static let tagAdditional = "62"
    private static let subTagBankBin = "00"
    private static let subTagAccount = "01"
    private static let subTagBeneficiary = "01"
    private static let subTagDescription = "08"
    private static let currencyVND = "704"

    static func decode(_ payload: String) throws -> VietQRPayload {
        guard !payload.isEmpty else { throw VietQRDecodeError.empty }

        let root = try parseTLV(payload)

        if let currency = root[tagCurrency], currency != currencyVND {
            throw VietQRDecodeError.unsupportedCurrency(currency)
        }

        guard let merchant = root[tagMerchantAccount] else {
            throw VietQRDecodeError.missingMerchantAccount
        }
        guard let beneficiary = try parseTLV(merchant)[subTagBeneficiary] else {
            throw VietQRDecodeError.missingBeneficiary
        }

        let fields = try parseTLV(beneficiary)
        guard let bankBin = fields[subTagBankBin],
              let accountNumber = fields[subTagAccount] else {
            throw VietQRDecodeError.missingAccount
        }

        var amountVnd: UInt64?
        if let raw = root[tagAmount] {
            // VND has no minor units; a trailing ".00" is tolerated.
            let whole = raw.split(separator: ".").first.map(String.init) ?? raw
            guard !whole.isEmpty, whole.allSatisfy(\.isNumber),
                  let parsed = UInt64(whole) else {
                throw VietQRDecodeError.badAmount(raw)
            }
            amountVnd = parsed
        }

        var description: String?
        if let additional = root[tagAdditional] {
            description = try parseTLV(additional)[subTagDescription]
        }

        return VietQRPayload(
            bankBin: bankBin,
            accountNumber: accountNumber,
            amountVnd: amountVnd,
            description: description
        )
    }

    private static func parseTLV(_ input: String) throws -> [String: String] {
        var out: [String: String] = [:]
        let chars = Array(input)
        var i = 0

        while i < chars.count {
            guard i + 4 <= chars.count else { throw VietQRDecodeError.truncated }
            let tag = String(chars[i ..< i + 2])
            let rawLength = String(chars[i + 2 ..< i + 4])
            guard rawLength.allSatisfy(\.isNumber), let length = Int(rawLength) else {
                throw VietQRDecodeError.badLength(rawLength)
            }
            let start = i + 4
            let end = start + length
            guard end <= chars.count else { throw VietQRDecodeError.truncated }
            out[tag] = String(chars[start ..< end])
            i = end
        }

        return out
    }
}
