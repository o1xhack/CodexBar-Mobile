#if os(macOS)
import CryptoKit
import Foundation

extension CodexLaunchPreflight {
    struct SignatureIdentity: Hashable, Sendable {
        let digest: Data

        static func read(_ path: String) -> Self? {
            guard let file = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return nil }
            defer { try? file.close() }
            return Self.read(file)
        }

        /// The caller owns the handle; reading must not reopen a pathname that may now name another file.
        static func read(_ file: FileHandle) -> Self? {
            do {
                let reader = try SignatureReader(file: file, length: Int(exactly: file.seekToEnd()))
                return try Self(digest: reader.digest())
            } catch {
                return nil
            }
        }
    }
}

private struct SignatureReader {
    private enum Invalid: Error { case signature }
    let file: FileHandle
    let length: Int?

    /// Bound untrusted allocations/work; larger or unfamiliar files retain fresh assessment.
    private func read(_ offset: Int, _ count: Int, limit: Int = 16 * 1024 * 1024) throws -> Data {
        guard let length, offset >= 0, count >= 0, count <= limit,
              offset <= length, count <= length - offset else { throw Invalid.signature }
        try self.file.seek(toOffset: UInt64(offset))
        guard let data = try self.file.read(upToCount: count), data.count == count else { throw Invalid.signature }
        return data
    }

    private func word(_ data: Data, _ offset: Int, little: Bool = false) throws -> UInt32 {
        guard offset >= 0, offset <= data.count, data.count - offset >= 4 else { throw Invalid.signature }
        let value = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
        return little ? value.littleEndian : value.bigEndian
    }

    private func wide(_ data: Data, _ offset: Int, little: Bool) throws -> Int {
        let first = try UInt64(self.word(data, offset, little: little))
        let second = try UInt64(self.word(data, offset + 4, little: little))
        guard let value = Int(exactly: little ? first | second << 32 : first << 32 | second)
        else { throw Invalid.signature }
        return value
    }

    func digest() throws -> Data {
        guard let length else { throw Invalid.signature }
        let prefix = try self.read(0, 8)
        let magic = try self.word(prefix, 0)
        var hash = SHA256()
        if [0xCAFE_BABE, 0xBEBA_FECA, 0xCAFE_BABF, 0xBFBA_FECA].contains(magic) {
            let little = magic == 0xBEBA_FECA || magic == 0xBFBA_FECA
            let wide = magic == 0xCAFE_BABF || magic == 0xBFBA_FECA
            let count = try Int(self.word(prefix, 4, little: little))
            guard (1...64).contains(count) else { throw Invalid.signature }
            let stride = wide ? 32 : 20
            let table = try self.read(0, 8 + count * stride)
            hash.update(data: table)
            var ranges: [Range<Int>] = []
            for index in 0..<count {
                let entry = 8 + index * stride
                let offset = try wide ? self.wide(table, entry + 8, little: little)
                    : Int(self.word(table, entry + 8, little: little))
                let size = try wide ? self.wide(table, entry + 16, little: little)
                    : Int(self.word(table, entry + 12, little: little))
                guard offset >= table.count, offset <= length, size > 0, size <= length - offset,
                      !ranges.contains(where: { $0.overlaps(offset..<(offset + size)) })
                else { throw Invalid.signature }
                ranges.append(offset..<(offset + size))
                let cpu = try self.word(table, entry, little: little)
                let subtype = try self.word(table, entry + 4, little: little)
                try self.slice(offset, size, cpu: cpu, subtype: subtype, hash: &hash)
            }
        } else {
            try self.slice(0, length, cpu: nil, subtype: nil, hash: &hash)
        }
        return Data(hash.finalize())
    }

    private func slice(_ offset: Int, _ size: Int, cpu: UInt32?, subtype: UInt32?, hash: inout SHA256) throws {
        guard size >= 28 else { throw Invalid.signature }
        let prefix = try self.read(offset, 28)
        let magic = try self.word(prefix, 0)
        guard [0xFEED_FACE, 0xCEFA_EDFE, 0xFEED_FACF, 0xCFFA_EDFE].contains(magic)
        else { throw Invalid.signature }
        let little = magic == 0xCEFA_EDFE || magic == 0xCFFA_EDFE
        let headerSize = magic == 0xFEED_FACF || magic == 0xCFFA_EDFE ? 32 : 28
        let count = try Int(self.word(prefix, 16, little: little))
        let commandSize = try Int(self.word(prefix, 20, little: little))
        guard size >= headerSize, commandSize <= size - headerSize, count <= 4096, count <= commandSize / 8,
              try self.word(prefix, 12, little: little) == 2,
              try cpu == nil || cpu == self.word(prefix, 4, little: little),
              try subtype == nil || subtype == self.word(prefix, 8, little: little)
        else { throw Invalid.signature }
        let header = try self.read(offset, headerSize)
        let commands = try self.read(offset + headerSize, commandSize, limit: 1024 * 1024)
        hash.update(data: header)
        hash.update(data: commands)
        var position = 0
        var signature: Data?
        for _ in 0..<count {
            let command = try self.word(commands, position, little: little)
            let length = try Int(self.word(commands, position + 4, little: little))
            guard length >= 8, length <= commands.count - position, length % (headerSize == 32 ? 8 : 4) == 0
            else { throw Invalid.signature }
            if command == 0x1D {
                guard signature == nil, length == 16 else { throw Invalid.signature }
                let start = try Int(self.word(commands, position + 8, little: little))
                let bytes = try Int(self.word(commands, position + 12, little: little))
                guard start >= headerSize + commandSize, start <= size, bytes <= size - start
                else { throw Invalid.signature }
                signature = try self.read(offset + start, bytes)
            }
            position += length
        }
        guard position == commands.count, let signature else { throw Invalid.signature }
        try self.validate(signature)
        // Include the layout as well as all signature bytes, including padding and non-primary blobs.
        hash.update(data: signature)
    }

    private func validate(_ signature: Data) throws {
        guard try self.word(signature, 0) == 0xFADE_0CC0 else { throw Invalid.signature }
        let length = try Int(self.word(signature, 4))
        let count = try Int(self.word(signature, 8))
        guard length >= 12, length <= signature.count, count <= 64,
              count <= (length - 12) / 8 else { throw Invalid.signature }
        var types: Set<UInt32> = []
        var ranges: [Range<Int>] = []
        for index in 0..<count {
            let type = try self.word(signature, 12 + index * 8)
            let offset = try Int(self.word(signature, 16 + index * 8))
            guard types.insert(type).inserted, offset >= 12 + count * 8, offset <= length - 8
            else { throw Invalid.signature }
            let size = try Int(self.word(signature, offset + 4))
            guard size >= 8, size <= length - offset,
                  !ranges.contains(where: { $0.overlaps(offset..<(offset + size)) }) else { throw Invalid.signature }
            ranges.append(offset..<(offset + size))
            if type == 0 || (0x1000..<0x1005).contains(type) {
                guard size >= 44, try self.word(signature, offset) == 0xFADE_0C02,
                      try self.word(signature, offset + 12) & 0x10000 != 0 else { throw Invalid.signature }
            }
            // CS_RUNTIME alone is insufficient on Intel when this entitlement opts out (TN3126).
            let optOut = "com.apple.security.cs.disable-executable-page-protection"
            if type == 5 {
                guard try self.word(signature, offset) == 0xFADE_7171,
                      let values = try PropertyListSerialization.propertyList(
                          from: signature.subdata(in: (offset + 8)..<(offset + size)),
                          options: [],
                          format: nil) as? [String: Any], values[optOut] == nil
                else { throw Invalid.signature }
            } else if type == 7 {
                // DER entitlement keys are literal UTF-8; conservatively exclude even a false-valued opt-out.
                guard try self.word(signature, offset) == 0xFADE_7172,
                      signature.subdata(in: (offset + 8)..<(offset + size)).range(of: Data(optOut.utf8)) == nil
                else { throw Invalid.signature }
            }
        }
        guard types.contains(0) else { throw Invalid.signature }
    }
}
#endif
