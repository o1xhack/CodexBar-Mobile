#if canImport(Glibc) || canImport(Musl)
import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import Testing
@testable import CodexBarCLI

@Suite(.serialized)
struct CLIServeRequestDeadlineLinuxTests {
    private final class Client: @unchecked Sendable {
        private let fd: Int32
        private let lock = NSLock()
        private let writerFinished = DispatchGroup()
        private var stopped = false

        init(port: UInt16) throws {
            #if canImport(Glibc)
            let streamType = Int32(SOCK_STREAM.rawValue)
            #else
            let streamType = Int32(SOCK_STREAM)
            #endif
            let fd = socket(AF_INET, streamType, 0)
            guard fd >= 0 else { throw POSIXError(.EIO) }
            var address = sockaddr_in()
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            let connected = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    connect(fd, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            // This timeout is only a hang guard, not a response-time expectation.
            var timeout = timeval(tv_sec: 60, tv_usec: 0)
            guard connected == 0,
                  setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0
            else {
                close(fd)
                throw POSIXError(.EIO)
            }
            self.fd = fd
        }

        func sendRequest(_ request: String) -> Bool {
            let bytes = Array(request.utf8)
            let sent = bytes.withUnsafeBytes { send(self.fd, $0.baseAddress, $0.count, Int32(MSG_NOSIGNAL)) }
            return sent == bytes.count
        }

        func startTrickling() {
            self.writerFinished.enter()
            Thread.detachNewThread { [self] in
                defer { self.writerFinished.leave() }
                // Never finish the header or approach the 16 KiB request-size cap.
                // Keep sending inside the per-read window until the server responds.
                while !self.lock.withLock({ self.stopped }) {
                    var byte: UInt8 = 97
                    guard send(self.fd, &byte, 1, Int32(MSG_NOSIGNAL)) == 1 else { return }
                    Thread.sleep(forTimeInterval: 0.3)
                }
            }
        }

        func response() throws -> String {
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while true {
                let count = buffer.withUnsafeMutableBytes { recv(self.fd, $0.baseAddress, $0.count, 0) }
                if count < 0, errno == EINTR { continue }
                // A close/reset after a response is normal while the peer is still writing.
                if count == 0 || (count < 0 && errno == ECONNRESET) {
                    guard let response = String(bytes: data, encoding: .utf8) else { throw POSIXError(.EILSEQ) }
                    return response
                }
                guard count > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                data.append(contentsOf: buffer.prefix(count))
            }
        }

        func stop() {
            let shouldStop = self.lock.withLock {
                guard !self.stopped else { return false }
                self.stopped = true
                return true
            }
            guard shouldStop else { return }
            // Wake any blocked send, then join before closing/reusing the descriptor.
            _ = shutdown(self.fd, Int32(SHUT_RDWR))
            guard self.writerFinished.wait(timeout: .now() + 60) == .success else {
                Issue.record("Trickling writer did not stop before the hang guard")
                return
            }
            close(self.fd)
        }
    }

    /// The accept loop and handlers use the cooperative executor. Keep blocking
    /// fixture I/O off it so a two-core runner still has a thread to serve clients.
    private static func onBackgroundThread<Value: Sendable>(
        onFailure: @escaping @Sendable () -> Void = {},
        _ operation: @escaping @Sendable () throws -> Value) async throws -> Value
    {
        try await withCheckedThrowingContinuation { continuation in
            Thread.detachNewThread {
                do {
                    try continuation.resume(returning: operation())
                } catch {
                    // Release blocked server workers before resuming on their executor.
                    onFailure()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    @Test
    func `trickling clients are rejected before their request headers finish`() async throws {
        let connectionCap = 3
        let listening = DispatchSemaphore(value: 0)
        let server = CLILocalHTTPServer(
            host: "127.0.0.1",
            port: 0,
            allowedHosts: .loopbackOnly,
            maximumConnections: connectionCap,
            totalReadTimeoutMilliseconds: 1500)
        { _ in
            CLILocalHTTPResponse(status: .ok, body: Data(#"{"ok":true}"#.utf8))
        }
        let task = Task { try await server.run { listening.signal() } }
        defer { server.stop() }
        let didListen = try await Self.onBackgroundThread { listening.wait(timeout: .now() + 60) == .success }
        try #require(didListen)
        let port = try #require(server.listeningPort)

        var clients: [Client] = []
        defer { clients.forEach { $0.stop() } }
        for _ in 0..<connectionCap {
            let client = try Client(port: port)
            clients.append(client)
            try #require(client.sendRequest("GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Pad: "))
            client.startTrickling()
        }
        let stopConnections: @Sendable () -> Void = { [clients] in
            server.stop()
            clients.forEach { $0.stop() }
        }

        for client in clients {
            // Requiring the rejection (not merely a later healthy probe) proves each
            // connection was admitted and evicted with its incomplete writer still open.
            let response = try await Self.onBackgroundThread(onFailure: stopConnections) { try client.response() }
            #expect(response.hasPrefix("HTTP/1.1 400 Bad Request\r\n"))
            #expect(response.hasSuffix(#"{"error":"invalid request"}"#))
        }

        // Closing a socket precedes releasing its slot. Retry that handoff with a
        // generous hang guard, and assert the actual response rather than its latency.
        let hangGuard = ContinuousClock.now.advanced(by: .seconds(60))
        var healthy = false
        repeat {
            let client = try Client(port: port)
            defer { client.stop() }
            if client.sendRequest("GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n") {
                let response = try await Self.onBackgroundThread(
                    onFailure: {
                        stopConnections()
                        client.stop()
                    },
                    { try client.response() })
                healthy = response.hasPrefix("HTTP/1.1 200 OK\r\n") && response.hasSuffix(#"{"ok":true}"#)
            }
            if !healthy { try await Task.sleep(for: .milliseconds(20)) }
        } while !healthy && ContinuousClock.now < hangGuard
        #expect(healthy, "Connection slots were not released before the hang guard")

        server.stop()
        try await task.value
    }
}
#endif
