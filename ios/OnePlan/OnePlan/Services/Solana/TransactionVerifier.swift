import Foundation

/// Base58 with the Bitcoin alphabet, which Solana uses for addresses.
enum Base58 {
    private static let alphabet = Array(
        "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    )

    static func encode(_ bytes: [UInt8]) -> String {
        var digits: [UInt8] = [0]
        for byte in bytes {
            var carry = Int(byte)
            for i in 0 ..< digits.count {
                carry += Int(digits[i]) << 8
                digits[i] = UInt8(carry % 58)
                carry /= 58
            }
            while carry > 0 {
                digits.append(UInt8(carry % 58))
                carry /= 58
            }
        }
        // Every leading zero byte is one leading '1'.
        let leadingZeros = bytes.prefix { $0 == 0 }.count
        let body = digits.reversed().map { alphabet[Int($0)] }
        return String(repeating: "1", count: leadingZeros) + String(body)
    }
}

struct DecodedInstruction {
    let programId: String
    let accountKeys: [String]
    let data: [UInt8]
}

struct DecodedTransaction {
    let accountKeys: [String]
    let instructions: [DecodedInstruction]
}

/// Decodes a legacy Solana transaction far enough to check it against the request
/// the app itself made, then refuses to sign on any mismatch.
///
/// The server builds every transaction, so without this a compromised server could
/// hand back one that drains the vault while the screen still reads
/// "200,000d to Nguyen Van A".
///
/// This is a machine check. Nothing here is shown to the user, who continues to
/// see only the human summary.
///
/// Legacy format only. The server is constrained to legacy transactions precisely
/// so this stays short: versioned transactions add address lookup tables, and
/// resolving those would mean fetching accounts before it is safe to sign.
enum TransactionVerifier {

    static func decode(base64: String) throws -> DecodedTransaction {
        guard let data = Data(base64Encoded: base64) else {
            throw SolanaDecodeError.truncated
        }
        let bytes = [UInt8](data)
        var offset = 0

        let signatureCount = try ShortVec.decode(bytes, at: &offset)
        offset += signatureCount * 64
        guard offset + 3 <= bytes.count else { throw SolanaDecodeError.truncated }
        offset += 3  // header: required signatures, readonly signed, readonly unsigned

        let accountCount = try ShortVec.decode(bytes, at: &offset)
        var accountKeys: [String] = []
        accountKeys.reserveCapacity(accountCount)
        for _ in 0 ..< accountCount {
            guard offset + 32 <= bytes.count else { throw SolanaDecodeError.truncated }
            accountKeys.append(Base58.encode(Array(bytes[offset ..< offset + 32])))
            offset += 32
        }

        guard offset + 32 <= bytes.count else { throw SolanaDecodeError.truncated }
        offset += 32  // recent blockhash

        let instructionCount = try ShortVec.decode(bytes, at: &offset)
        var instructions: [DecodedInstruction] = []
        instructions.reserveCapacity(instructionCount)

        for _ in 0 ..< instructionCount {
            guard offset < bytes.count else { throw SolanaDecodeError.truncated }
            let programIndex = Int(bytes[offset])
            offset += 1
            guard programIndex < accountKeys.count else {
                throw SolanaDecodeError.accountIndexOutOfRange
            }

            let accountIndexCount = try ShortVec.decode(bytes, at: &offset)
            guard offset + accountIndexCount <= bytes.count else {
                throw SolanaDecodeError.truncated
            }
            var referenced: [String] = []
            for i in 0 ..< accountIndexCount {
                let index = Int(bytes[offset + i])
                guard index < accountKeys.count else {
                    throw SolanaDecodeError.accountIndexOutOfRange
                }
                referenced.append(accountKeys[index])
            }
            offset += accountIndexCount

            let dataLength = try ShortVec.decode(bytes, at: &offset)
            guard offset + dataLength <= bytes.count else {
                throw SolanaDecodeError.truncated
            }
            let data = Array(bytes[offset ..< offset + dataLength])
            offset += dataLength

            instructions.append(
                DecodedInstruction(
                    programId: accountKeys[programIndex],
                    accountKeys: referenced,
                    data: data
                )
            )
        }

        return DecodedTransaction(accountKeys: accountKeys, instructions: instructions)
    }

    /// Throws unless the transaction contains exactly the one instruction the app
    /// asked for, against the expected program, amount and accounts.
    static func verify(
        base64: String,
        expectedProgramId: String,
        expectedDiscriminator: [UInt8],
        expectedAmountMicro: UInt64?,
        expectedAccounts: [String]
    ) throws {
        let decoded = try decode(base64: base64)

        guard decoded.instructions.count == 1 else {
            throw SolanaDecodeError.instructionCountMismatch
        }
        let instruction = decoded.instructions[0]

        guard instruction.programId == expectedProgramId else {
            throw SolanaDecodeError.unexpectedProgram
        }
        guard instruction.data.count >= 8,
              Array(instruction.data.prefix(8)) == expectedDiscriminator else {
            throw SolanaDecodeError.discriminatorMismatch
        }

        if let expectedAmountMicro {
            guard instruction.data.count >= 16 else {
                throw SolanaDecodeError.argumentMismatch(field: "amount")
            }
            let raw = Array(instruction.data[8 ..< 16])
            let amount = raw.reversed().reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            guard amount == expectedAmountMicro else {
                throw SolanaDecodeError.argumentMismatch(field: "amount")
            }
        }

        for account in expectedAccounts {
            guard instruction.accountKeys.contains(account) else {
                throw SolanaDecodeError.argumentMismatch(field: "account \(account)")
            }
        }
    }
}
