import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

struct ProviderPluginOptionalPOSTTests {
    @Test(arguments: BundledPluginTestSupport.engines, [false, true])
    func `optional POST overlaps GET with independent body headers and five second cap`(
        engine: ProviderPluginEngineKind, form: Bool) async throws
    {
        let (started, continuation) = AsyncStream<Void>.makeStream()
        let runtime = try Self.runtime(engine, optional: """
        {url: 'https://console.example.com/optional', method: 'POST',
         \(form ? "form: { token: 'fixture +&' }" : "body: { token: 'fixture' }"),
         headers: {'X-Optional': 'yes'}, timeoutSeconds: 90}
        """) { request in
            if request.httpMethod == "GET" {
                #expect(request.httpBody == nil)
                #expect(request.value(forHTTPHeaderField: "X-Optional") == nil)
                for await _ in started {
                    break
                }
            } else {
                #expect(request.timeoutInterval == 5)
                #expect(request.value(forHTTPHeaderField: "X-Optional") == "yes")
                #expect(request.value(forHTTPHeaderField: "Content-Type") ==
                    (form ? "application/x-www-form-urlencoded" : "application/json"))
                let body = try #require(String(data: request.httpBody ?? Data(), encoding: .utf8))
                #expect(form ? body == "token=fixture%20%2B%26" : body.contains("fixture"))
                continuation.yield(())
                continuation.finish()
            }
            return ProviderPluginConsoleCapabilitiesTests.response(request, body: "ready")
        }
        #expect(try await runtime.fetchUsage().identity?.loginMethod == "ready")
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `optional POST can collect beyond the existing GET default`(engine: ProviderPluginEngineKind) async throws {
        let runtime = try Self.runtime(engine, budget: "5") { request in
            if request.httpMethod == "POST" { try await Task.sleep(for: .seconds(1)) }
            return ProviderPluginConsoleCapabilitiesTests.response(request, body: "ready")
        }
        #expect(try await runtime.fetchUsage().identity?.loginMethod == "ready")
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `optional POST failures never fail primary or retry POST`(engine: ProviderPluginEngineKind) async throws {
        let calls = Calls()
        let runtime = try Self.runtime(engine) { request in
            if request.httpMethod == "POST" {
                calls.started()
                throw URLError(.timedOut)
            }
            return ProviderPluginConsoleCapabilitiesTests.response(request, body: "ready")
        }
        #expect(try await runtime.fetchUsage().identity?.loginMethod == "none")
        #expect(calls.count == 1)
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `invalid optional POST origin method body and budget are refused before either request`(
        engine: ProviderPluginEngineKind) async throws
    {
        for (optional, budget) in [
            ("{url:'https://undeclared.test/',method:'POST',body:{}}", "5"),
            ("{url:'https://console.example.com/',method:'DELETE',body:{}}", "5"),
            ("{url:'https://console.example.com/',method:'POST',form:{x:2}}", "5"),
            ("{url:'https://console.example.com/',method:'POST',form:{},body:{}}", "5"),
            ("{url:'https://console.example.com/',method:'POST',body:{}}", "6"),
            ("{url:'https://console.example.com/',method:'POST',body:{}}", "true"),
        ] {
            let runtime = try Self.runtime(engine, optional: optional, budget: budget) { _ in
                Issue.record("Invalid request reached transport")
                throw URLError(.badURL)
            }
            await #expect(throws: ProviderPluginError.self) { try await runtime.fetchUsage() }
        }
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `optional form secrets are redacted even when optional transport fails`(
        engine: ProviderPluginEngineKind) async throws
    {
        let runtime = try Self.runtime(engine, optional: """
        {url:'https://console.example.com/optional',method:'POST',form:{token:'private-fixture+&'}}
        """, suffix: "throw new Error('private-fixture+& private-fixture%2B%26');") { request in
            if request.httpMethod == "POST" { throw URLError(.cannotConnectToHost) }
            return ProviderPluginConsoleCapabilitiesTests.response(request, body: "ready")
        }
        let error = await #expect(throws: ProviderPluginError.self) { try await runtime.fetchUsage() }
        #expect(error?.localizedDescription.contains("private-fixture") == false)
    }

    @Test(arguments: BundledPluginTestSupport.engines)
    func `caller cancellation interrupts required GET and optional POST`(engine: ProviderPluginEngineKind) async throws {
        let calls = Calls()
        let runtime = try Self.runtime(engine) { request in
            calls.started()
            do { try await Task.sleep(for: .seconds(30)) } catch {
                calls.cancelled()
                throw error
            }
            return ProviderPluginConsoleCapabilitiesTests.response(request, body: "late")
        }
        let task = Task { try await runtime.fetchUsage() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while calls.count < 2, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(calls.count == 2)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        while calls.cancellations < 2, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(calls.cancellations == 2)
    }

    private static func runtime(
        _ engine: ProviderPluginEngineKind,
        optional: String = "{url:'https://console.example.com/optional',method:'POST',body:{}}",
        budget: String = "5",
        suffix: String = "return {identity:{loginMethod:response.optional?.bodyText || 'none'}};",
        handler: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) throws -> ProviderPluginRuntime
    {
        try ProviderPluginConsoleCapabilitiesTests.runtime(engine, body: """
        const response = await ctx.http.getWithOptional('https://console.example.com/primary',
          \(optional), {optionalBudgetSeconds:\(budget)});
        \(suffix)
        """, transport: ProviderHTTPTransportHandler(handler))
    }

    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var starts = 0
        private var cancels = 0
        var count: Int {
            self.lock.withLock { self.starts }
        }

        var cancellations: Int {
            self.lock.withLock { self.cancels }
        }

        func started() { self.lock.withLock { self.starts += 1 } }
        func cancelled() { self.lock.withLock { self.cancels += 1 } }
    }
}
