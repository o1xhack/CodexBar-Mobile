import Foundation
import Testing
@testable import CodexBarCore

#if os(macOS)
struct CodexLaunchPreflightHostEnforcementTests {
    private typealias Host = CodexLaunchPreflight.HostEnforcement

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var total: Int {
            self.lock.withLock { self.value }
        }

        func increment() { self.lock.withLock { self.value += 1 } }
    }

    @Test(arguments: ["", "-v", "keepsyms=1 debug=0x100"])
    func `fully enforced hosts accept readable ordinary boot arguments`(bootArguments: String) {
        #expect(Host(
            csrStatus: 0, csrConfiguration: 0, systemEnforcement: 1, bootArguments: bootArguments).isEnforced)
    }

    @Test(arguments: [
        "amfi_get_out_of_my_way=1", "AMFI=0", "-v cs_enforcement_disable=1", "CS_EnForCement=1",
        "cs_debug=0", "-ArM64E_PrEvIeW_AbI", "prefix_amfi_suffix=1",
    ])
    func `enforcement boot overrides are rejected case insensitively`(bootArguments: String) {
        #expect(!Host(
            csrStatus: 0, csrConfiguration: 0, systemEnforcement: 1, bootArguments: bootArguments).isEnforced)
    }

    @Test
    func `CSR failures and any partial SIP configuration disable memoization`() {
        for status: Int32 in [-1, 1, 5] {
            #expect(!Host(csrStatus: status, csrConfiguration: 0, systemEnforcement: 1, bootArguments: "").isEnforced)
        }
        for configuration: UInt32 in [1, 2, 0x67, .max] {
            #expect(!Host(
                csrStatus: 0, csrConfiguration: configuration, systemEnforcement: 1, bootArguments: "").isEnforced)
        }
    }

    @Test
    func `sysctl failures and unenforced values disable memoization`() {
        for enforcement: Int32? in [nil, -1, 0, 2] {
            #expect(!Host(csrStatus: 0, csrConfiguration: 0, systemEnforcement: enforcement, bootArguments: "")
                .isEnforced)
        }
        #expect(!Host(csrStatus: 0, csrConfiguration: 0, systemEnforcement: 1, bootArguments: nil).isEnforced)
    }

    @Test
    func `a disallowed host bypasses identity reads and cached results entirely`() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("synthetic executable".utf8).write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }
        let signatureReads = Counter()
        let memo = CodexLaunchPreflight.AssessmentMemo(
            hostAllowsMemoization: false,
            readSignature: { _ in
                signatureReads.increment()
                return .init(digest: Data("synthetic signature".utf8))
            })
        var calls = 0
        for expected in 1...100 {
            let result = memo.assessment(path: path.path, isDefinitive: { _ in true }, assess: { candidate in
                #expect(candidate == path.path)
                calls += 1
                return .init(output: "assessment \(calls)", exitStatus: 0)
            })
            #expect(result?.output == "assessment \(expected)")
        }
        #expect(calls == 100)
        #expect(signatureReads.total == 0)
        print("host gate bypass: requests=100 assessments=\(calls) signatureReads=\(signatureReads.total)")
    }
}
#endif
