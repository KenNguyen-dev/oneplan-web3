import Foundation

enum SolanaDecodeError: Error, Equatable {
    case truncated
    case malformedLength
    case unexpectedProgram
    case accountIndexOutOfRange
    case instructionCountMismatch
    case discriminatorMismatch
    case argumentMismatch(field: String)
}

/// Solana's compact-u16: seven bits of payload per byte, high bit set while more
/// bytes follow, at most three bytes.
enum ShortVec {
    static func decode(_ bytes: [UInt8], at offset: inout Int) throws -> Int {
        var value = 0
        var shift = 0
        var index = offset

        while true {
            guard index < bytes.count else { throw SolanaDecodeError.truncated }
            let byte = bytes[index]
            index += 1
            value |= Int(byte & 0x7f) << shift
            if byte & 0x80 == 0 { break }
            shift += 7
            if shift > 14 { throw SolanaDecodeError.malformedLength }
        }

        offset = index
        return value
    }
}
