import Foundation

#if os(macOS)
import Darwin

extension CodexLaunchPreflight {
    /// Remembers Gatekeeper verdicts for standalone Mach-O launch candidates.
    ///
    /// `spctl --assess` re-hashes the whole binary on every call and nothing upstream caches a
    /// `rejected (… does not seem to be an app)` verdict, so each Codex lookup cost seconds of `syspolicyd`
    /// CPU and the total scaled with refresh cadence (#4078).
    ///
    /// A verdict is bound to a file, not to a path. The memo resolves the candidate to its device and inode
    /// and has Gatekeeper assess `/.vol/<device>/<inode>`, which names that file directly, so no symlink or
    /// directory swapped while `spctl` runs can change what was assessed. The key includes stat metadata and
    /// a hash of every embedded signature; unsigned files and app bundles are never memoized.
    /// Mapped writes can leave stat unchanged: changing any signature byte invalidates the key. Only hardened
    /// runtime code without a page-protection opt-out is eligible (Apple TN3126). The kernel validates signed
    /// pages at page-in only on enforcing hosts: a process-wide gate requires full SIP, system enforcement,
    /// and readable boot arguments without enforcement overrides. Otherwise every assessment stays fresh.
    /// Quarantine/xattr changes invalidate via ctime; the remaining check-then-exec race exists without the memo.
    /// A verdict is kept only if the file's identity is unchanged when `spctl` returns, and a caller receives
    /// it only while its own path still names that file; otherwise the caller gets a fresh, unshared
    /// assessment of its path. The lifetime bounds how long a certificate revoked in place, with the file
    /// untouched, can go unnoticed. Where `/.vol` cannot reach the file, nothing is memoized.
    final class AssessmentMemo: @unchecked Sendable {
        static let shared = AssessmentMemo()
        static let capacity = 16
        static let lifetime: TimeInterval = 5 * 60

        /// Assessments are synchronous. Each pending file has its own result promise, so waiting callers
        /// share even a transient result without holding the dictionary lock or blocking unrelated files.
        /// `bound` records whether the file was unchanged when `spctl` returned.
        private final class Flight {
            private let condition = NSCondition()
            private var completed = false
            private var result: (assessment: GatekeeperAssessment?, bound: Bool) = (nil, false)

            func wait() -> (assessment: GatekeeperAssessment?, bound: Bool) {
                self.condition.lock()
                defer { self.condition.unlock() }
                while !self.completed {
                    self.condition.wait()
                }
                return self.result
            }

            func complete(_ assessment: GatekeeperAssessment?, bound: Bool) {
                self.condition.lock()
                self.result = (assessment, bound)
                self.completed = true
                self.condition.broadcast()
                self.condition.unlock()
            }
        }

        private let lock = NSLock()
        private var entries: [FileIdentity: (assessment: GatekeeperAssessment, expiresAt: TimeInterval)] = [:]
        private var flights: [FileIdentity: Flight] = [:]
        private let hostAllowsMemoization: Bool
        private let onJoin: @Sendable () -> Void
        private let onCacheHit: @Sendable () -> Void
        private let readSignature: @Sendable (FileHandle) -> SignatureIdentity?

        init(
            hostAllowsMemoization: Bool = HostEnforcement.allowsMemoization,
            onJoin: @escaping @Sendable () -> Void = {},
            onCacheHit: @escaping @Sendable () -> Void = {},
            readSignature: @escaping @Sendable (FileHandle) -> SignatureIdentity? = SignatureIdentity.read)
        {
            self.hostAllowsMemoization = hostAllowsMemoization
            self.onJoin = onJoin
            self.onCacheHit = onCacheHit
            self.readSignature = readSignature
        }

        private func identity(_ path: String) -> FileIdentity? {
            guard Self.isStandalone(path) else { return nil }
            let descriptor = open(path, O_RDONLY | O_CLOEXEC)
            guard descriptor >= 0 else { return nil }
            let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            defer { try? file.close() }
            var info = stat()
            guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
                  let signature = self.readSignature(file) else { return nil }
            let identity = FileIdentity(info: info, signature: signature)
            // Hash the descriptor we stat'ed, then check the pathname last: it may have moved during the read.
            guard Self.isStandalone(path), stat(path, &info) == 0,
                  FileIdentity(info: info, signature: signature) == identity else { return nil }
            return identity
        }

        private static func isStandalone(_ path: String) -> Bool {
            // An external npm wrapper can select app-contained code; its bundle resources are not in this key.
            guard CodexLaunchPreflight.containingAppBundlePath(for: path) == nil else { return false }
            let resolvedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            return CodexLaunchPreflight.containingAppBundlePath(for: resolvedPath) == nil
        }

        /// Returns the remembered verdict for the unchanged regular file `path` names, or assesses it. Only
        /// verdicts `isDefinitive` accepts are kept; timeouts, launch failures, and `spctl` errors stay
        /// retryable. App bundles and their code stay uncached. Verdicts are reported for `path`.
        func assessment(
            path: String,
            now: TimeInterval = ProcessInfo.processInfo.systemUptime,
            isDefinitive: (GatekeeperAssessment) -> Bool,
            assess: (String) -> GatekeeperAssessment?) -> GatekeeperAssessment?
        {
            guard self.hostAllowsMemoization,
                  let file = self.identity(path), self.identity(file.volumePath) == file
            else { return assess(path) }
            self.lock.lock()
            if let entry = self.entries[file], now < entry.expiresAt {
                self.lock.unlock()
                self.onCacheHit()
                return self.deliver(entry.assessment, bound: true, file: file, path: path, assess: assess)
            }
            if let flight = self.flights[file] {
                self.lock.unlock()
                self.onJoin()
                let shared = flight.wait()
                return self.deliver(shared.assessment, bound: shared.bound, file: file, path: path, assess: assess)
            }
            let flight = Flight()
            self.flights[file] = flight
            self.lock.unlock()

            let result = assess(file.volumePath)
            // Kept only if the file did not change while `spctl` read it.
            let bound = self.identity(file.volumePath) == file
            self.lock.withLock {
                self.entries = self.entries.filter { now < $0.value.expiresAt }
                if let result, bound, let reported = Self.attributed(result, from: file.volumePath, to: path),
                   isDefinitive(reported)
                {
                    if self.entries.count >= Self.capacity,
                       let firstToExpire = self.entries.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key
                    {
                        self.entries.removeValue(forKey: firstToExpire)
                    }
                    self.entries[file] = (result, now + Self.lifetime)
                }
                flight.complete(result, bound: bound)
                self.flights.removeValue(forKey: file)
            }
            return self.deliver(result, bound: bound, file: file, path: path, assess: assess)
        }

        /// Every answer (cache hit, shared, or fresh) is checked against what the caller's path names
        /// immediately before it is returned. A verdict for a file the path no longer names is not an answer
        /// for this lookup, so the caller gets a fresh, unshared assessment of its path instead.
        private func deliver(
            _ assessment: GatekeeperAssessment?,
            bound: Bool,
            file: FileIdentity,
            path: String,
            assess: (String) -> GatekeeperAssessment?) -> GatekeeperAssessment?
        {
            guard bound, self.identity(path) == file else { return assess(path) }
            return Self.attributed(assessment, from: file.volumePath, to: path)
        }

        /// `spctl` names the path it was given at the start of its first line; report the caller's path.
        private static func attributed(
            _ assessment: GatekeeperAssessment?,
            from source: String,
            to path: String) -> GatekeeperAssessment?
        {
            guard let assessment, assessment.output.hasPrefix("\(source):") else { return assessment }
            return GatekeeperAssessment(
                output: path + String(assessment.output.dropFirst(source.count)),
                exitStatus: assessment.exitStatus)
        }
    }

    private struct FileIdentity: Hashable {
        let mode: mode_t
        let device: dev_t
        let inode: ino_t
        let size: off_t
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int

        let signature: SignatureIdentity

        /// Names this file without traversing any directory or symlink.
        var volumePath: String {
            "/.vol/\(self.device)/\(self.inode)"
        }

        init(info: stat, signature: SignatureIdentity) {
            self.signature = signature
            self.mode = info.st_mode
            self.device = info.st_dev
            self.inode = info.st_ino
            self.size = info.st_size
            self.modifiedSeconds = info.st_mtimespec.tv_sec
            self.modifiedNanoseconds = info.st_mtimespec.tv_nsec
            self.changedSeconds = info.st_ctimespec.tv_sec
            self.changedNanoseconds = info.st_ctimespec.tv_nsec
        }
    }
}
#endif
