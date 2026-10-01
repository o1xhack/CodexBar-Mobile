import Foundation

/// Bounded protobuf wire reader shared by Grok billing and reset-coupon messages.
struct GrokProtobufField {
    var number: UInt64
    var varint: UInt64?
    var fixed32: Float?
    var message: [UInt8]?

    static func fields(in bytes: [UInt8]) -> [Self]? {
        var fields: [Self] = []
        var index = 0
        while index < bytes.count {
            guard let field = self.read(bytes, index: &index) else { return nil }
            fields.append(field)
        }
        return fields
    }

    static func read(_ bytes: [UInt8], index: inout Int) -> Self? {
        guard let key = self.readVarint(bytes, index: &index),
              key >> 3 > 0, key >> 3 <= 536_870_911 else { return nil }
        var field = Self(number: key >> 3)
        switch key & 0x07 {
        case 0:
            guard let value = self.readVarint(bytes, index: &index) else { return nil }
            field.varint = value
        case 1:
            guard bytes.count - index >= 8 else { return nil }
            index += 8
        case 2:
            guard let length = self.readVarint(bytes, index: &index),
                  length <= UInt64(bytes.count - index) else { return nil }
            let end = index + Int(length)
            field.message = Array(bytes[index..<end])
            index = end
        case 5:
            guard bytes.count - index >= 4 else { return nil }
            let bits = UInt32(bytes[index]) | (UInt32(bytes[index + 1]) << 8)
                | (UInt32(bytes[index + 2]) << 16) | (UInt32(bytes[index + 3]) << 24)
            field.fixed32 = Float(bitPattern: bits)
            index += 4
        default:
            return nil
        }
        return field
    }

    private static func readVarint(_ bytes: [UInt8], index: inout Int) -> UInt64? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while index < bytes.count, shift < 64 {
            let byte = bytes[index]
            index += 1
            if shift == 63, byte > 1 { return nil }
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
        }
        return nil
    }
}
