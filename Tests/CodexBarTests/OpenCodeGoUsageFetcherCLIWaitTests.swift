import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct OpenCodeGoUsageFetcherCLIWaitTests {
    private struct UsageWindow {
        let percent: Double
        let resetInSec: Int
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OpenCodeGoCLIWaitStubURLProtocol.self]
        return URLSession(configuration: config)
    }

    @Test(.timeLimit(.minutes(1)))
    func `cli wait policy includes explicitly released zen balance`() async throws {
        defer {
            OpenCodeGoCLIWaitStubURLProtocol.handler = nil
        }

        OpenCodeGoCLIWaitStubURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            if url.path == "/workspace/wrk_TEST123" {
                return Self.makeResponse(
                    url: url,
                    body: #"<html><body><h2>現在の残高 $98.76</h2></body></html>"#,
                    statusCode: 200,
                    contentType: "text/html")
            }
            return Self.makeResponse(
                url: url,
                body: Self.goUsagePageHTML(
                    workspaceID: "wrk_TEST123",
                    rolling: UsageWindow(percent: 17, resetInSec: 600),
                    weekly: UsageWindow(percent: 75, resetInSec: 7200),
                    monthly: nil),
                statusCode: 200,
                contentType: "text/html")
        }

        let balanceStarted = AsyncStream.makeStream(of: Void.self)
        let joinStarted = AsyncStream.makeStream(of: Duration.self)
        let deadline = AsyncStream.makeStream(of: Void.self)
        let now = ContinuousClock.now
        OpenCodeGoCLIWaitStubURLProtocol.onHold = { balanceStarted.continuation.yield(()) }
        defer { OpenCodeGoCLIWaitStubURLProtocol.onHold = nil }
        let holdDeadline: @Sendable (Duration) async throws -> Void = { duration in
            joinStarted.continuation.yield(duration)
            for await _ in deadline.stream {}
            try Task.checkCancellation()
        }
        let task = Task {
            defer {
                balanceStarted.continuation.finish()
                joinStarted.continuation.finish()
            }
            return try await BoundedTaskJoinTiming.$sleep.withValue(holdDeadline) {
                try await OpenCodeGoUsageFetcher.fetchUsage(
                    cookieHeader: "auth=test",
                    timeout: 60,
                    workspaceIDOverride: "wrk_TEST123",
                    waitForZenBalance: true,
                    session: self.makeSession(),
                    clockNow: { now })
            }
        }
        defer {
            task.cancel()
            OpenCodeGoCLIWaitStubURLProtocol.heldResponse.setValue(nil)
        }
        for await _ in balanceStarted.stream {
            break
        }
        var join = joinStarted.stream.makeAsyncIterator()
        // The balance is still held when the CLI chooses its full budget, rather than the app's short grace.
        #expect(await join.next() == .seconds(5))
        let deliver = try #require(OpenCodeGoCLIWaitStubURLProtocol.heldResponse.value)
        OpenCodeGoCLIWaitStubURLProtocol.heldResponse.setValue(nil)
        deliver()
        let snapshot = try await task.value

        #expect(snapshot.rollingUsagePercent == 17)
        #expect(snapshot.zenBalanceUSD == 98.76)
    }

    @Test
    func `cli wait policy keeps subscription result when balance fetch fails`() async throws {
        defer {
            OpenCodeGoCLIWaitStubURLProtocol.handler = nil
        }

        OpenCodeGoCLIWaitStubURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            if url.path == "/workspace/wrk_TEST123" {
                throw URLError(.timedOut)
            }
            return Self.makeResponse(
                url: url,
                body: Self.goUsagePageHTML(
                    workspaceID: "wrk_TEST123",
                    rolling: UsageWindow(percent: 17, resetInSec: 600),
                    weekly: UsageWindow(percent: 75, resetInSec: 7200),
                    monthly: nil),
                statusCode: 200,
                contentType: "text/html")
        }

        let snapshot = try await OpenCodeGoUsageFetcher.fetchUsage(
            cookieHeader: "auth=test",
            timeout: 60,
            workspaceIDOverride: "wrk_TEST123",
            waitForZenBalance: true,
            session: self.makeSession())

        #expect(snapshot.rollingUsagePercent == 17)
        #expect(snapshot.zenBalanceUSD == nil)
    }

    @Test
    func `cli wait policy keeps configured timeout when zen balance becomes required`() async throws {
        defer {
            OpenCodeGoCLIWaitStubURLProtocol.handler = nil
        }

        var rootTimeout: TimeInterval?
        OpenCodeGoCLIWaitStubURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            if url.path == "/workspace/wrk_TEST123" {
                rootTimeout = request.timeoutInterval
                return Self.makeResponse(
                    url: url,
                    body: #"<html><body><h2>Current balance $17.25</h2></body></html>"#,
                    statusCode: 200,
                    contentType: "text/html")
            }
            return Self.makeResponse(
                url: url,
                body: #"<script>rollingUsage:{usagePercent:12}</script>"#,
                statusCode: 200,
                contentType: "text/html")
        }

        let snapshot = try await OpenCodeGoUsageFetcher.fetchUsage(
            cookieHeader: "auth=test",
            timeout: 60,
            workspaceIDOverride: "wrk_TEST123",
            waitForZenBalance: true,
            session: self.makeSession())

        #expect(snapshot.isBalanceOnly)
        #expect(snapshot.zenBalanceUSD == 17.25)
        #expect(rootTimeout == 60)
    }

    @Test
    func `cli wait policy bounds optional balance wait from task start`() async throws {
        defer {
            OpenCodeGoCLIWaitStubURLProtocol.handler = nil
            OpenCodeGoCLIWaitStubURLProtocol.hangPaths = []
        }

        let startedAt = ContinuousClock.now
        let clock = LockIsolated(startedAt)
        let clockReads = LockIsolated<[ContinuousClock.Instant]>([])
        let clockStarted = DispatchSemaphore(value: 0)
        OpenCodeGoCLIWaitStubURLProtocol.hangPaths = ["/workspace/wrk_TEST123"]
        OpenCodeGoCLIWaitStubURLProtocol.handler = { request in
            guard let url = request.url else { throw URLError(.badURL) }
            if url.path == "/workspace/wrk_TEST123/go" {
                #expect(clockStarted.wait(timeout: .now() + 30) == .success)
                clock.setValue(startedAt.advanced(by: .seconds(8)))
            }
            return Self.makeResponse(
                url: url,
                body: Self.goUsagePageHTML(
                    workspaceID: "wrk_TEST123",
                    rolling: UsageWindow(percent: 17, resetInSec: 600),
                    weekly: UsageWindow(percent: 75, resetInSec: 7200),
                    monthly: nil),
                statusCode: 200,
                contentType: "text/html")
        }

        let snapshot = try await OpenCodeGoUsageFetcher.fetchUsage(
            cookieHeader: "auth=test",
            timeout: 60,
            workspaceIDOverride: "wrk_TEST123",
            waitForZenBalance: true,
            session: self.makeSession(),
            clockNow: {
                let now = clock.value
                clockReads.setValue(clockReads.value + [now])
                clockStarted.signal()
                return now
            })

        #expect(snapshot.rollingUsagePercent == 17)
        #expect(snapshot.zenBalanceUSD == nil)
        #expect(clockReads.value == [startedAt, startedAt.advanced(by: .seconds(8))])
        for (elapsed, expected) in [(0, 5), (2, 3), (5, 0), (8, 0)] {
            #expect(OpenCodeGoUsageFetcher.optionalZenBalanceJoinTimeout(
                since: startedAt,
                waitForZenBalance: true,
                now: startedAt.advanced(by: .seconds(elapsed))) == .seconds(expected))
        }
        #expect(OpenCodeGoUsageFetcher.optionalZenBalanceJoinTimeout(
            since: startedAt,
            waitForZenBalance: false,
            now: startedAt.advanced(by: .seconds(8))) == .milliseconds(250))
    }

    private static func goUsagePageHTML(
        workspaceID: String,
        rolling: UsageWindow,
        weekly: UsageWindow,
        monthly: UsageWindow?) -> String
    {
        let monthlyField: String? = if let monthly {
            #"monthlyUsage:{status:"ok",resetInSec:\#(monthly.resetInSec),usagePercent:\#(monthly.percent)}"#
        } else {
            nil
        }

        let usageFields = [
            #"rollingUsage:{status:"ok",resetInSec:\#(rolling.resetInSec),usagePercent:\#(rolling.percent)}"#,
            #"weeklyUsage:{status:"ok",resetInSec:\#(weekly.resetInSec),usagePercent:\#(weekly.percent)}"#,
            monthlyField,
        ]
            .compactMap(\.self)
            .joined(separator: ",")

        return """
        <!DOCTYPE html>
        <html>
        <body>
        <script>
        _$HY.r["lite.subscription.get[\\"\(workspaceID)\\"]"]=$R[17]=$R[2]($R[18]={p:0,s:0,f:0});
        $R[24]($R[18],$R[27]={mine:!0,useBalance:!1,\(usageFields)});
        </script>
        </body>
        </html>
        """
    }

    private static func makeResponse(
        url: URL,
        body: String,
        statusCode: Int,
        contentType: String) -> (HTTPURLResponse, Data)
    {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": contentType])!
        return (response, Data(body.utf8))
    }
}

private final class OpenCodeGoCLIWaitStubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let handlerBox = LockIsolated<((URLRequest) throws -> (HTTPURLResponse, Data))?>(nil)
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { Self.handlerBox.value }
        set { Self.handlerBox.setValue(newValue) }
    }

    private static let hangPathsBox = LockIsolated<Set<String>>([])
    static var hangPaths: Set<String> {
        get { hangPathsBox.value }
        set { hangPathsBox.setValue(newValue) }
    }

    static let heldResponse = LockIsolated<(() -> Void)?>(nil)
    private static let onHoldBox = LockIsolated<(() -> Void)?>(nil)
    static var onHold: (() -> Void)? {
        get { onHoldBox.value }
        set { onHoldBox.setValue(newValue) }
    }

    override static func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "opencode.ai"
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = self.request.url else {
            self.client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        if Self.hangPaths.contains(url.path) {
            return
        }
        let deliver: () -> Void = { [weak self] in
            guard let self else { return }
            do {
                let (response, data) = try Self.response(for: self.request)
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: data)
                self.client?.urlProtocolDidFinishLoading(self)
            } catch {
                self.client?.urlProtocol(self, didFailWithError: error)
            }
        }
        if url.path == "/workspace/wrk_TEST123", let onHold = Self.onHold {
            Self.heldResponse.setValue(deliver)
            onHold()
        } else {
            deliver()
        }
    }

    private static func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        guard let handler = Self.handler else {
            throw URLError(.badServerResponse)
        }
        return try handler(request)
    }

    override func stopLoading() {}
}
