import Testing
@testable import OnePlan

/// Solana encodes array lengths as compact-u16: seven bits per byte, high bit set
/// while more bytes follow. The transaction verifier needs it to walk the wire
/// format.
@Suite("ShortVec compact-u16")
struct ShortVecTests {

    @Test("single byte values decode as themselves")
    func singleByte() throws {
        var offset = 0
        #expect(try ShortVec.decode([0x00], at: &offset) == 0)
        #expect(offset == 1)

        offset = 0
        #expect(try ShortVec.decode([0x7f], at: &offset) == 127)
        #expect(offset == 1)
    }

    @Test("two byte values decode across the continuation bit")
    func twoBytes() throws {
        var offset = 0
        #expect(try ShortVec.decode([0x80, 0x01], at: &offset) == 128)
        #expect(offset == 2)

        offset = 0
        #expect(try ShortVec.decode([0xff, 0x7f], at: &offset) == 16383)
        #expect(offset == 2)
    }

    @Test("three byte values decode")
    func threeBytes() throws {
        var offset = 0
        #expect(try ShortVec.decode([0x80, 0x80, 0x01], at: &offset) == 16384)
        #expect(offset == 3)
    }

    @Test("decoding continues from the given offset")
    func respectsOffset() throws {
        var offset = 2
        #expect(try ShortVec.decode([0xaa, 0xbb, 0x05], at: &offset) == 5)
        #expect(offset == 3)
    }

    @Test("running off the end throws")
    func truncated() {
        var offset = 0
        #expect(throws: SolanaDecodeError.self) {
            try ShortVec.decode([0x80], at: &offset)
        }
    }

    @Test("an empty buffer throws")
    func empty() {
        var offset = 0
        #expect(throws: SolanaDecodeError.self) {
            try ShortVec.decode([], at: &offset)
        }
    }
}
