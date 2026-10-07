#if os(macOS)
import Darwin
import Foundation

@_silgen_name("csr_get_active_config")
private func codexBarCSRGetActiveConfig(_ configuration: UnsafeMutablePointer<UInt32>) -> Int32

extension CodexLaunchPreflight {
    struct HostEnforcement: Sendable {
        static let current = Self.read()
        static let allowsMemoization = Self.current.isEnforced
        static let forbiddenBootArguments = ["amfi", "cs_enforcement", "cs_debug", "-arm64e_preview_abi"]

        let csrStatus: Int32
        let csrConfiguration: UInt32
        let systemEnforcement: Int32?
        let bootArguments: String?

        var isEnforced: Bool {
            guard self.csrStatus == 0, self.csrConfiguration == 0, self.systemEnforcement == 1,
                  let bootArguments = self.bootArguments?.lowercased() else { return false }
            return !Self.forbiddenBootArguments.contains(where: bootArguments.contains)
        }

        private static func read() -> Self {
            var configuration: UInt32 = 0
            let csrStatus = codexBarCSRGetActiveConfig(&configuration)
            var enforcement: Int32 = 0
            var size = MemoryLayout<Int32>.size
            let readable = sysctlbyname("vm.cs_system_enforcement", &enforcement, &size, nil, 0) == 0 &&
                size == MemoryLayout<Int32>.size
            return Self(
                csrStatus: csrStatus,
                csrConfiguration: configuration,
                systemEnforcement: readable ? enforcement : nil,
                bootArguments: self.readBootArguments())
        }

        private static func readBootArguments() -> String? {
            var size = 0
            guard sysctlbyname("kern.bootargs", nil, &size, nil, 0) == 0, (1...65536).contains(size)
            else { return nil }
            var data = Data(count: size)
            let result = data.withUnsafeMutableBytes {
                sysctlbyname("kern.bootargs", $0.baseAddress, &size, nil, 0)
            }
            guard result == 0, size > 0, size <= data.count, data[size - 1] == 0,
                  !data.prefix(size - 1).contains(0) else { return nil }
            return String(data: data.prefix(size - 1), encoding: .utf8)
        }
    }
}
#endif
