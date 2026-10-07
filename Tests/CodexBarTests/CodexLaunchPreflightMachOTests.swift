import Foundation
import Testing
@testable import CodexBarCore

#if os(macOS)
struct CodexLaunchPreflightMachOTests {
    private typealias Fixture = CodexLaunchPreflightSignatureTests.Fixture
    private typealias Signature = CodexLaunchPreflight.SignatureIdentity

    private static func word(_ data: Data, _ offset: Int, little: Bool = false) -> UInt32 {
        let value = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
        return little ? value.littleEndian : value.bigEndian
    }

    private static func write(
        _ value: some FixedWidthInteger,
        to data: inout Data,
        at offset: Int,
        little: Bool = false)
    {
        let bytes = withUnsafeBytes(of: little ? value.littleEndian : value.bigEndian, Array.init)
        data.replaceSubrange(offset..<(offset + bytes.count), with: bytes)
    }

    @Test(arguments: [false, true], [false, true])
    func `fat headers support both byte orders and entry widths`(little: Bool, wide: Bool) throws {
        let fixture = try Fixture(universal: true)
        let original = try Data(contentsOf: URL(fileURLWithPath: fixture.path))
        var data = original
        Self.write(UInt32(wide ? 0xCAFE_BABF : 0xCAFE_BABE), to: &data, at: 0, little: little)
        Self.write(UInt32(fixture.slices.count), to: &data, at: 4, little: little)
        for index in fixture.slices.indices {
            let old = 8 + index * 20
            let entry = 8 + index * (wide ? 32 : 20)
            Self.write(Self.word(original, old), to: &data, at: entry, little: little)
            Self.write(Self.word(original, old + 4), to: &data, at: entry + 4, little: little)
            if wide {
                Self.write(UInt64(Self.word(original, old + 8)), to: &data, at: entry + 8, little: little)
                Self.write(UInt64(Self.word(original, old + 12)), to: &data, at: entry + 16, little: little)
                Self.write(Self.word(original, old + 16), to: &data, at: entry + 24, little: little)
                Self.write(UInt32(0), to: &data, at: entry + 28, little: little)
            } else {
                for field in [8, 12, 16] {
                    Self.write(Self.word(original, old + field), to: &data, at: entry + field, little: little)
                }
            }
        }
        try data.write(to: URL(fileURLWithPath: fixture.path))
        #expect(Signature.read(fixture.path) != nil)
        if wide {
            Self.write(UInt64.max, to: &data, at: 16, little: little)
            try data.write(to: URL(fileURLWithPath: fixture.path))
            #expect(Signature.read(fixture.path) == nil)
        }
    }

    @Test
    func `every slice must be hardened and all signature padding is hashed`() throws {
        let fixture = try Fixture(universal: true)
        let initial = try #require(Signature.read(fixture.path))
        let second = try #require(fixture.slices.last)
        fixture.change(second.signature + second.signatureSize - 1)
        #expect(try #require(Signature.read(fixture.path)) != initial)
        fixture.change(second.signature + second.signatureSize - 1)
        let directory = try #require(second.blobs[0])
        // CS_RUNTIME is 0x00010000 in the big-endian CodeDirectory flags field.
        fixture.change(directory + 13)
        #expect(Signature.read(fixture.path) == nil)
        var calls = 0
        let memo = CodexLaunchPreflight.AssessmentMemo(hostAllowsMemoization: true)
        for _ in 0..<3 {
            _ = memo.assessment(path: fixture.path, isDefinitive: { _ in true }, assess: { path in
                calls += 1
                return .init(output: "\(path): accepted", exitStatus: 0)
            })
        }
        #expect(calls == 3)
    }

    @Test
    func `DER opt out is detected even without the XML entitlement slot`() throws {
        let fixture = try Fixture(universal: true, optOut: true)
        var bytes = try Data(contentsOf: URL(fileURLWithPath: fixture.path))
        for slice in fixture.slices {
            try #require(slice.blobs[7] != nil)
            let count = Self.word(bytes, slice.signature + 8)
            for index in 0..<Int(count) {
                let entry = slice.signature + 12 + index * 8
                if Self.word(bytes, entry) == 5 {
                    Self.write(UInt32(255), to: &bytes, at: entry)
                }
            }
        }
        try bytes.write(to: URL(fileURLWithPath: fixture.path))
        #expect(Signature.read(fixture.path) == nil)
    }

    @Test
    func `truncated overflowing overlapping and missing signature structures bypass the memo`() throws {
        let fixture = try Fixture(universal: true)
        let original = try Data(contentsOf: URL(fileURLWithPath: fixture.path))
        let slice = try #require(fixture.slices.first)
        let directory = try #require(slice.blobs[0])
        let fields: [(Int, UInt32, Bool)] = [
            (4, UInt32.max, false), // Fat count.
            (16, UInt32.max, false), // Slice offset.
            (20, UInt32.max, false), // Slice size.
            (36, UInt32(slice.base), false), // Overlapping second slice.
            (slice.base, 0, true), // Mach-O magic.
            (slice.base + 12, 1, true), // Object, not executable.
            (slice.base + 16, UInt32.max, true), // Load-command count.
            (slice.base + 20, UInt32.max, true), // Load-command byte size.
            (slice.base + 36, 0, true), // Zero-size load command.
            (slice.signature, 0, false), // Superblob magic.
            (slice.signature + 4, UInt32.max, false), // Superblob length.
            (slice.signature + 8, UInt32.max, false), // Blob count.
            (slice.signature + 12, 99, false), // Missing primary CodeDirectory.
            (slice.signature + 16, UInt32.max, false), // Blob offset.
            (slice.signature + 20, 0, false), // Duplicate primary slot.
            (directory, 0, false), // CodeDirectory magic.
            (directory + 4, UInt32.max, false), // CodeDirectory length.
        ]
        var malformed = [Data(original.prefix(7)), Data(original.prefix(slice.base + 27)), Data(original.dropLast())]
        for (offset, value, little) in fields {
            var bytes = original
            Self.write(value, to: &bytes, at: offset, little: little)
            malformed.append(bytes)
        }
        for (index, bytes) in malformed.enumerated() {
            let path = fixture.root.appendingPathComponent("malformed-\(index)")
            try bytes.write(to: path)
            #expect(Signature.read(path.path) == nil, "Malformed case \(index) must not be memoized")
        }
    }
}
#endif
