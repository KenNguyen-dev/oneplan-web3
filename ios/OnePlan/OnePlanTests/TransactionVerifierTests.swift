import Foundation
import Testing
@testable import OnePlan

/// Builds a minimal legacy transaction: signature count, blank signatures, a
/// three byte header, the account keys, a blockhash, then one instruction.
private func makeTransaction(
    signerCount: Int = 2,
    accountKeys: [[UInt8]],
    programIndex: UInt8,
    instructionAccounts: [UInt8],
    data: [UInt8]
) -> String {
    var bytes: [UInt8] = []
    bytes.append(UInt8(signerCount))
    bytes.append(contentsOf: [UInt8](repeating: 0, count: 64 * signerCount))
    bytes.append(contentsOf: [UInt8(signerCount), 0, 1])
    bytes.append(UInt8(accountKeys.count))
    for key in accountKeys { bytes.append(contentsOf: key) }
    bytes.append(contentsOf: [UInt8](repeating: 7, count: 32))  // blockhash
    bytes.append(1)                                             // one instruction
    bytes.append(programIndex)
    bytes.append(UInt8(instructionAccounts.count))
    bytes.append(contentsOf: instructionAccounts)
    bytes.append(UInt8(data.count))
    bytes.append(contentsOf: data)
    return Data(bytes).base64EncodedString()
}

private func key(_ seed: UInt8) -> [UInt8] { [UInt8](repeating: seed, count: 32) }

/// Anchor instruction data: eight discriminator bytes then borsh arguments.
private let discriminator: [UInt8] = [77, 79, 85, 150, 33, 217, 52, 106]

private func u64le(_ value: UInt64) -> [UInt8] {
    withUnsafeBytes(of: value.littleEndian) { Array($0) }
}

@Suite("TransactionVerifier")
struct TransactionVerifierTests {

    private func base58(_ bytes: [UInt8]) -> String { Base58.encode(bytes) }

    @Test("decodes account keys and one instruction")
    func decodes() throws {
        let tx = makeTransaction(
            accountKeys: [key(1), key(2), key(9)],
            programIndex: 2,
            instructionAccounts: [0, 1],
            data: discriminator + u64le(7_660_000)
        )
        let decoded = try TransactionVerifier.decode(base64: tx)

        #expect(decoded.accountKeys.count == 3)
        #expect(decoded.instructions.count == 1)
        #expect(decoded.instructions[0].programId == base58(key(9)))
        #expect(decoded.instructions[0].data.count == 16)
    }

    @Test("accepts a transaction matching the request")
    func accepts() throws {
        let tx = makeTransaction(
            accountKeys: [key(1), key(2), key(9)],
            programIndex: 2,
            instructionAccounts: [0, 1],
            data: discriminator + u64le(7_660_000)
        )
        try TransactionVerifier.verify(
            base64: tx,
            expectedProgramId: base58(key(9)),
            expectedDiscriminator: discriminator,
            expectedAmountMicro: 7_660_000,
            expectedAccounts: [base58(key(1))]
        )
    }

    @Test("rejects a tampered amount")
    func rejectsAmount() {
        let tx = makeTransaction(
            accountKeys: [key(1), key(2), key(9)],
            programIndex: 2,
            instructionAccounts: [0, 1],
            data: discriminator + u64le(999_999_999)
        )
        #expect(throws: SolanaDecodeError.self) {
            try TransactionVerifier.verify(
                base64: tx,
                expectedProgramId: base58(key(9)),
                expectedDiscriminator: discriminator,
                expectedAmountMicro: 7_660_000,
                expectedAccounts: [base58(key(1))]
            )
        }
    }

    @Test("rejects a substituted program")
    func rejectsProgram() {
        let tx = makeTransaction(
            accountKeys: [key(1), key(2), key(3)],
            programIndex: 2,
            instructionAccounts: [0, 1],
            data: discriminator + u64le(7_660_000)
        )
        #expect(throws: SolanaDecodeError.self) {
            try TransactionVerifier.verify(
                base64: tx,
                expectedProgramId: base58(key(9)),
                expectedDiscriminator: discriminator,
                expectedAmountMicro: 7_660_000,
                expectedAccounts: []
            )
        }
    }

    @Test("rejects a different instruction")
    func rejectsDiscriminator() {
        let tx = makeTransaction(
            accountKeys: [key(1), key(2), key(9)],
            programIndex: 2,
            instructionAccounts: [0, 1],
            data: [1, 2, 3, 4, 5, 6, 7, 8] + u64le(7_660_000)
        )
        #expect(throws: SolanaDecodeError.self) {
            try TransactionVerifier.verify(
                base64: tx,
                expectedProgramId: base58(key(9)),
                expectedDiscriminator: discriminator,
                expectedAmountMicro: 7_660_000,
                expectedAccounts: []
            )
        }
    }

    @Test("rejects a missing expected account")
    func rejectsMissingAccount() {
        let tx = makeTransaction(
            accountKeys: [key(1), key(2), key(9)],
            programIndex: 2,
            instructionAccounts: [0, 1],
            data: discriminator + u64le(7_660_000)
        )
        #expect(throws: SolanaDecodeError.self) {
            try TransactionVerifier.verify(
                base64: tx,
                expectedProgramId: base58(key(9)),
                expectedDiscriminator: discriminator,
                expectedAmountMicro: 7_660_000,
                expectedAccounts: [base58(key(5))]
            )
        }
    }

    @Test("rejects more than one instruction")
    func rejectsMultipleInstructions() {
        var bytes = Array(Data(base64Encoded: makeTransaction(
            accountKeys: [key(1), key(2), key(9)],
            programIndex: 2,
            instructionAccounts: [0, 1],
            data: discriminator + u64le(7_660_000)
        ))!)
        // Claim two instructions while supplying one.
        let instructionCountIndex = 1 + 64 * 2 + 3 + 1 + 32 * 3 + 32
        bytes[instructionCountIndex] = 2
        #expect(throws: SolanaDecodeError.self) {
            try TransactionVerifier.decode(base64: Data(bytes).base64EncodedString())
        }
    }

    @Test("rejects a truncated transaction")
    func rejectsTruncated() {
        #expect(throws: SolanaDecodeError.self) {
            try TransactionVerifier.decode(base64: Data([1, 2, 3]).base64EncodedString())
        }
    }
}
