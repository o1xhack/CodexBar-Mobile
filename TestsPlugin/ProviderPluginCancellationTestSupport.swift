import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

enum ProviderPluginCancellationTestSupport {
    static func checkCallerCancellation(
        engine: ProviderPluginEngineKind,
        optionalMethod: String,
        waitingForAdmission: Bool) async throws
    {
        let (starts, started) = AsyncStream<String>.makeStream()
        let (cancellations, cancelled) = AsyncStream<String>.makeStream()
        let caller = CancellationRequest()
        let optional = optionalMethod == "POST"
            ? "{url: 'https://example.test/optional', method: 'POST', body: {}}"
            : "'https://example.test/optional'"
        defer {
            started.finish()
            cancelled.finish()
        }
        let hold: @Sendable (URLRequest) async throws -> Void = { request in
            let path = request.url!.path
            let (pending, release) = AsyncStream<Void>.makeStream()
            defer { release.finish() }
            try await withTaskCancellationHandler {
                started.yield(path)
                for await _ in pending {}
                try Task.checkCancellation()
                Issue.record("Request was released without cancellation")
            } onCancel: {
                #expect(caller.wasRequested, "A request timeout must not substitute for caller cancellation")
                cancelled.yield(path)
            }
        }
        let runtime = try ProviderPluginRuntime(
            source: """
            defineProvider({
              id: 'cancellation-fixture', name: 'Cancellation fixture', endpoints: ['https://example.test'], settings: [],
              async fetchUsage(ctx) {
                await ctx.http.getWithOptional('https://example.test/primary',
                  \(optional), {optionalBudgetSeconds: 5});
                return {empty: true};
              }
            });
            """,
            resourceBundle: CodexBarCoreResources.bundle,
            transport: ProviderHTTPTransportHandler { request in
                #expect(!waitingForAdmission, "Cancelled admission must not reach transport")
                try await hold(request)
                throw CancellationError()
            },
            allowsDynamicID: true,
            contextOptions: ProviderPluginContextOptions(
                optionalRequestTimeoutSeconds: nil,
                waitForOptionalDeadline: { _, budget in
                    #expect(budget == .seconds(5))
                    // Only caller cancellation may end collection in this test.
                    let (pending, release) = AsyncStream<Void>.makeStream()
                    defer { release.finish() }
                    for await _ in pending {}
                    try Task.checkCancellation()
                },
                beforeHTTPAttempt: { request in
                    // Admission coverage cannot be rescued by the independent request timers.
                    if waitingForAdmission { try await hold(request) }
                }),
            engine: engine)
        let task = Task {
            defer { started.finish() }
            do {
                return try await runtime.fetchUsage()
            } catch {
                if !(error is CancellationError) { Issue.record(error) }
                throw error
            }
        }
        defer {
            caller.request()
            task.cancel()
        }
        var startIterator = starts.makeAsyncIterator()
        let first = try #require(await startIterator.next())
        let second = try #require(await startIterator.next())
        #expect(Set([first, second]) == ["/primary", "/optional"])
        caller.request()
        task.cancel()
        switch await BoundedTaskJoin(sourceTask: task).value(joinGrace: .seconds(10)) {
        case let .failure(error): #expect(error is CancellationError)
        case .value, .timedOut:
            Issue.record("Cancelled fetch did not return CancellationError")
            return
        }
        var cancellationIterator = cancellations.makeAsyncIterator()
        let firstCancelled = try #require(await cancellationIterator.next())
        let secondCancelled = try #require(await cancellationIterator.next())
        #expect(Set([firstCancelled, secondCancelled]) == ["/primary", "/optional"])
    }

    private final class CancellationRequest: @unchecked Sendable {
        private let lock = NSLock()
        private var requested = false
        var wasRequested: Bool {
            self.lock.withLock { self.requested }
        }

        func request() { self.lock.withLock { self.requested = true } }
    }
}
