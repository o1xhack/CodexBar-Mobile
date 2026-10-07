import Foundation
import Testing
@testable import CodexBarCore

#if os(macOS)
import Darwin

struct CodexLaunchPreflightSignatureTests {
    private typealias Memo = CodexLaunchPreflight.AssessmentMemo
    private typealias Signature = CodexLaunchPreflight.SignatureIdentity

    private static func run(_ executable: String, _ arguments: [String] = []) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process
    }

    struct Slice {
        let cpu: UInt32
        let base: Int
        let signature: Int
        let signatureSize: Int
        let text: Int
        let blobs: [UInt32: Int]
    }

    private static func word(_ bytes: Data, _ offset: Int, big: Bool = false) -> UInt32 {
        let value = bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
        return big ? value.bigEndian : value.littleEndian
    }

    /// Only parses the trusted Mach-O fixtures emitted by clang/codesign; production parsing is bounds checked.
    private static func slices(_ bytes: Data) throws -> [Slice] {
        let bases = Self.word(bytes, 0, big: true) == 0xCAFE_BABE
            ? (0..<Int(Self.word(bytes, 4, big: true))).map { Int(Self.word(bytes, 16 + $0 * 20, big: true)) }
            : [0]
        return try bases.map { base in
            var position = base + 32
            var text: Int?
            var signature: Int?
            var signatureSize = 0
            for _ in 0..<Self.word(bytes, base + 16) {
                if Self.word(bytes, position) == 0x19 {
                    for index in 0..<Int(Self.word(bytes, position + 64)) {
                        let section = position + 72 + index * 80
                        if bytes[section..<(section + 16)].starts(with: Data("__text\0".utf8)) {
                            text = base + Int(Self.word(bytes, section + 48))
                        }
                    }
                } else if Self.word(bytes, position) == 0x1D {
                    signature = base + Int(Self.word(bytes, position + 8))
                    signatureSize = Int(Self.word(bytes, position + 12))
                }
                position += Int(Self.word(bytes, position + 4))
            }
            let start = try #require(signature)
            var blobs: [UInt32: Int] = [:]
            for index in 0..<Int(Self.word(bytes, start + 8, big: true)) {
                blobs[Self.word(bytes, start + 12 + index * 8, big: true)] = start +
                    Int(Self.word(bytes, start + 16 + index * 8, big: true))
            }
            return try Slice(
                cpu: Self.word(bytes, base + 4),
                base: base,
                signature: start,
                signatureSize: signatureSize,
                text: #require(text),
                blobs: blobs)
        }
    }

    final class Fixture: @unchecked Sendable {
        let root: URL
        let path: String
        let descriptor: Int32
        let mapped: UnsafeMutableRawPointer
        let size: Int
        let slices: [Slice]

        init(universal: Bool = false, hardened: Bool = true, optOut: Bool = false) throws {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            var completed = false
            defer { if !completed { try? FileManager.default.removeItem(at: root) } }
            let source = root.appendingPathComponent("fixture.c")
            let path = root.appendingPathComponent("fixture").path
            // Keep main off the header page so mutation proves a page-in kill, rather than EBADEXEC at spawn.
            try "__attribute__((aligned(16384))) int main(void) { return 0; }\n"
                .write(to: source, atomically: true, encoding: .utf8)
            let architectures = universal ? ["-arch", "arm64", "-arch", "x86_64"] : []
            let compiled = try Self.run("/usr/bin/xcrun", ["clang"] + architectures + [source.path, "-o", path])
            try #require(compiled.terminationStatus == 0)
            let entitlements = root.appendingPathComponent("entitlements.plist")
            let values: [String: Any] = optOut
                ? ["com.apple.security.cs.disable-executable-page-protection": true] :
                ["com.apple.security.cs.allow-jit": true]
            try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
                .write(to: entitlements)
            let options = hardened ? ["--options", "runtime"] : []
            let signed = try Self.run(
                "/usr/bin/codesign",
                ["--force", "--sign", "-"] + options +
                    ["--entitlements", entitlements.path, "--requirements", "=designated => identifier fixture", path])
            try #require(signed.terminationStatus == 0)
            var bytes = try Data(contentsOf: URL(fileURLWithPath: path))
            let slices = try CodexLaunchPreflightSignatureTests.slices(bytes)
            for slice in slices {
                // Ad-hoc signatures ignore CMS. Put one synthetic payload byte in its existing alignment padding;
                // this remains a valid native ad-hoc fixture and tests the same CMS region as Developer ID code.
                let cms = try #require(slice.blobs[0x10000])
                let length = Int(CodexLaunchPreflightSignatureTests.word(bytes, slice.signature + 4, big: true))
                try #require(length < slice.signatureSize)
                try #require(CodexLaunchPreflightSignatureTests.word(bytes, cms + 4, big: true) == 8)
                bytes.replaceSubrange((cms + 4)..<(cms + 8), with: withUnsafeBytes(of: UInt32(9).bigEndian, Array.init))
                bytes.replaceSubrange(
                    (slice.signature + 4)..<(slice.signature + 8),
                    with: withUnsafeBytes(of: UInt32(length + 1).bigEndian, Array.init))
                bytes[cms + 8] = 0x41
            }
            try bytes.write(to: URL(fileURLWithPath: path))
            try #require(Self.run("/usr/bin/codesign", ["--verify", "--strict", path]).terminationStatus == 0)
            let descriptor = open(path, O_RDWR)
            try #require(descriptor >= 0)
            var mappedSuccessfully = false
            defer { if !mappedSuccessfully { close(descriptor) } }
            let mapped = try #require(mmap(nil, bytes.count, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0))
            try #require(mapped != MAP_FAILED)
            self.root = root
            self.path = path
            self.descriptor = descriptor
            self.mapped = mapped
            self.size = bytes.count
            self.slices = slices
            mappedSuccessfully = true
            completed = true
        }

        private static func run(_ executable: String, _ arguments: [String]) throws -> Process {
            try CodexLaunchPreflightSignatureTests.run(executable, arguments)
        }

        deinit {
            munmap(self.mapped, self.size)
            close(self.descriptor)
            try? FileManager.default.removeItem(at: self.root)
        }

        func metadata() throws -> [Int64] {
            var info = stat()
            try #require(stat(self.path, &info) == 0)
            return [
                Int64(info.st_mode),
                Int64(info.st_dev),
                Int64(info.st_ino),
                Int64(info.st_size),
                Int64(info.st_mtimespec.tv_sec),
                Int64(info.st_mtimespec.tv_nsec),
                Int64(info.st_ctimespec.tv_sec),
                Int64(info.st_ctimespec.tv_nsec),
            ]
        }

        func change(_ offset: Int) {
            self.mapped.advanced(by: offset).assumingMemoryBound(to: UInt8.self).pointee ^= 1
        }
    }

    @Test(arguments: [UInt32(0), 2, 5, 0x10000], [false, true])
    func `all signature components invalidate the memo in every slice`(kind: UInt32, duringHit: Bool) throws {
        let fixture = try Fixture(universal: true)
        for slice in fixture.slices {
            let blob = try #require(slice.blobs[kind])
            let offset: Int
            switch kind {
            case 0:
                let identifier = fixture.mapped.loadUnaligned(fromByteOffset: blob + 20, as: UInt32.self).bigEndian
                offset = blob + Int(identifier)
            case 0x10000: offset = blob + 8
            case 5:
                let length = fixture.mapped.loadUnaligned(fromByteOffset: blob + 4, as: UInt32.self).bigEndian
                let data = Data(bytes: fixture.mapped.advanced(by: blob), count: Int(length))
                offset = try blob + #require(data.range(of: Data("allow-jit".utf8))).lowerBound
            default:
                let length = fixture.mapped.loadUnaligned(fromByteOffset: blob + 4, as: UInt32.self).bigEndian
                offset = blob + Int(length) - 1
            }
            let original = try #require(Signature.read(fixture.path))
            let memo = Memo(hostAllowsMemoization: true, onCacheHit: { if duringHit { fixture.change(offset) } })
            var calls = 0
            func assess() {
                _ = memo.assessment(path: fixture.path, isDefinitive: { _ in true }, assess: { path in
                    calls += 1
                    return .init(output: "\(path): accepted", exitStatus: 0)
                })
            }
            assess()
            let before = try fixture.metadata()
            if !duringHit { fixture.change(offset) }
            assess()
            #expect(try fixture.metadata() == before)
            #expect(try #require(Signature.read(fixture.path)) != original)
            #expect(calls == 2)
            fixture.change(offset)
            print("signature component=\(kind) cpu=\(slice.cpu) finalRecheck=\(duringHit) assessments=\(calls)")
        }
    }

    @Test(arguments: [false, true])
    func `mapped hardened text follows the real host enforcement gate`(universal: Bool) throws {
        let fixture = try Fixture(universal: universal)
        let original = try #require(Signature.read(fixture.path))
        let baseline = try Self.run(fixture.path)
        try #require(baseline.terminationReason == .exit && baseline.terminationStatus == 0)
        let host = CodexLaunchPreflight.HostEnforcement.current
        let allowed = CodexLaunchPreflight.HostEnforcement.allowsMemoization
        let bootMatches = CodexLaunchPreflight.HostEnforcement.forbiddenBootArguments.filter {
            host.bootArguments?.lowercased().contains($0) == true
        }
        print("host gate: csrStatus=\(host.csrStatus) csrConfiguration=\(host.csrConfiguration) " +
            "systemEnforcement=\(String(describing: host.systemEnforcement)) " +
            "bootargsReadable=\(host.bootArguments != nil) bootargsEmpty=\(host.bootArguments?.isEmpty == true) " +
            "bootargsMatches=\(bootMatches) allowed=\(allowed)")
        #expect(allowed == host.isEnforced)
        let memo = Memo()
        var calls = 0
        func assess() {
            _ = memo.assessment(path: fixture.path, isDefinitive: { _ in true }, assess: { path in
                calls += 1
                return .init(output: "\(path): accepted", exitStatus: 0)
            })
        }
        assess()
        let before = try fixture.metadata()
        #if arch(arm64)
        let cpu: UInt32 = 0x100000C
        #else
        let cpu: UInt32 = 0x1000007
        #endif
        try fixture.change(#require(fixture.slices.first { $0.cpu == cpu }).text)
        #expect(try fixture.metadata() == before)
        #expect(try #require(Signature.read(fixture.path)) == original)
        assess()
        if allowed {
            #expect(calls == 1)
            let changed = try Self.run(fixture.path)
            #expect(changed.terminationReason == .uncaughtSignal)
            #expect(changed.terminationStatus == SIGKILL)
            print(
                "mapped hardened text: universal=\(universal) assessments=\(calls) signal=\(changed.terminationStatus)")
        } else {
            #expect(calls == 2)
            assess()
            #expect(calls == 3)
            print("mapped hardened text: universal=\(universal) hostGate=false freshAssessments=\(calls)")
        }
    }

    @Test
    func `a hardened executable shares one assessment across one hundred lookups`() throws {
        let fixture = try Fixture()
        let memo = Memo(hostAllowsMemoization: true)
        var calls = 0
        for _ in 0..<100 {
            let result = memo.assessment(path: fixture.path, isDefinitive: { _ in true }, assess: { path in
                calls += 1
                return .init(output: "\(path): accepted", exitStatus: 0)
            })
            #expect(result?.exitStatus == 0)
        }
        #expect(calls == 1)
        print("hardened memo: requests=100 assessments=\(calls)")
    }

    @Test(arguments: [false, true])
    func `hardened binaries opting out of page protection are never memoized`(universal: Bool) throws {
        let fixture = try Fixture(universal: universal, optOut: true)
        #expect(Signature.read(fixture.path) == nil)
        let memo = Memo(hostAllowsMemoization: true)
        var calls = 0
        for _ in 0..<3 {
            _ = memo.assessment(path: fixture.path, isDefinitive: { _ in true }, assess: { path in
                calls += 1
                return .init(output: "\(path): accepted", exitStatus: 0)
            })
        }
        #expect(calls == 3)
    }

    @Test(arguments: [false, true])
    func `non hardened and unsigned files always use fresh assessment`(universal: Bool) throws {
        let fixture = try Fixture(universal: universal, hardened: false)
        let text = fixture.root.appendingPathComponent("plain-text")
        try Data("synthetic fixture".utf8).write(to: text)
        for path in [fixture.path, text.path, fixture.root.appendingPathComponent("missing").path] {
            #expect(Signature.read(path) == nil)
            var calls = 0
            let memo = Memo(hostAllowsMemoization: true)
            for _ in 0..<3 {
                _ = memo.assessment(path: path, isDefinitive: { _ in true }, assess: { candidate in
                    #expect(candidate == path)
                    calls += 1
                    return .init(output: "\(candidate): rejected", exitStatus: 3)
                })
            }
            #expect(calls == 3)
        }
        try #require(Self.run("/usr/bin/codesign", ["--remove-signature", fixture.path]).terminationStatus == 0)
        #expect(Signature.read(fixture.path) == nil)
    }
}
#endif
