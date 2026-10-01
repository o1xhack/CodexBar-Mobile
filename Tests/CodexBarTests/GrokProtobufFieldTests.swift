import Foundation
import Testing
@testable import CodexBarCore

struct GrokProtobufFieldTests {
    @Test
    func `wire reader bounds continuation and length reads`() {
        let endless = [UInt8(0x08)] + Array(repeating: UInt8(0x80), count: 4096)
        var index = 0
        #expect(GrokProtobufField.read(endless, index: &index) == nil)
        #expect(index == 11)
        let malformed: [[UInt8]] = [[0x00], [0x02, 0], [0x09, 0], [0x15, 0, 0], [0x12, 0x7F, 0], [0x08]]
        for bytes in malformed {
            #expect(GrokProtobufField.fields(in: bytes) == nil)
        }
    }

    @Test
    func `wire reader accepts maximum integers and leaves opaque bytes uninterpreted`() throws {
        let maximum = [UInt8(0x08)] + Array(repeating: UInt8(0xFF), count: 9) + [0x01]
        let fields = try #require(GrokProtobufField.fields(in: maximum + [0x12, 0x01, 0xFF]))
        #expect(fields.count == 2)
        #expect(fields[0].varint == UInt64.max)
        #expect(fields[1].message == [0xFF])
    }
}
