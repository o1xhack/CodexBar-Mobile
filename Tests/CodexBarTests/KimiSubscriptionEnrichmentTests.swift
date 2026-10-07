import Foundation
import Testing
@testable import CodexBarCore

struct KimiSubscriptionEnrichmentTests {
    @Test(.timeLimit(.minutes(1)))
    func `slow plan metadata cannot discard completed subscription quotas`() async throws {
        let plan = KimiEnrichmentLatch()
        let hangGuard = plan.hangGuard()
        defer { hangGuard.cancel() }
        let transport = Self.transport(plan: plan)
        let snapshot: KimiUsageSnapshot
        do {
            snapshot = try await KimiUsageFetcher.fetchUsage(
                authToken: "fixture-web-token",
                transport: transport,
                subscriptionGrace: .milliseconds(100))
        } catch {
            await plan.release()
            throw error
        }
        let planWasRequested = await plan.started
        #expect(await !plan.released)
        await plan.release()

        #expect(planWasRequested)
        #expect(snapshot.weekly?.used == "25")
        #expect(snapshot.subscriptionBalance?.amountUsedRatio == 0.42)
        #expect(snapshot.subscriptionCodeWeeklyLimit?.ratio == 0.17)
        #expect(snapshot.planName == nil)
        let windows = snapshot.toUsageSnapshot().extraRateWindows ?? []
        #expect(windows.first { $0.id == "kimi-monthly" }?.window.usedPercent == 42)
        #expect(windows.first { $0.id == "kimi-code-7d" }?.window.usedPercent == 17)
    }

    @Test(.timeLimit(.minutes(1)))
    func `API usage retains completed monthly quota while plan enrichment times out`() async throws {
        let plan = KimiEnrichmentLatch()
        let hangGuard = plan.hangGuard()
        defer { hangGuard.cancel() }
        let snapshot: KimiUsageSnapshot
        do {
            snapshot = try await KimiUsageFetcher.fetchCodeAPIUsage(
                apiKey: "fixture-api-key",
                webAuthToken: "fixture-web-token",
                transport: Self.transport(plan: plan))
        } catch {
            await plan.release()
            throw error
        }
        #expect(await !plan.released)
        await plan.release()
        #expect(snapshot.weekly?.used == "25")
        #expect(snapshot.subscriptionBalance?.amountUsedRatio == 0.42)
        #expect(snapshot.subscriptionCodeWeeklyLimit?.ratio == 0.17)
        #expect(snapshot.planName == nil)
    }

    @Test
    func `plan can complete independently of stalled statistics`() async throws {
        let stats = KimiEnrichmentLatch()
        let hangGuard = stats.hangGuard()
        defer { hangGuard.cancel() }
        let snapshot: KimiUsageSnapshot
        do {
            snapshot = try await KimiUsageFetcher.fetchUsage(
                authToken: "fixture-web-token",
                transport: Self.transport(plan: stats, stalledPath: "/GetSubscriptionStats"),
                subscriptionGrace: .milliseconds(100))
        } catch {
            await stats.release()
            throw error
        }
        #expect(await !stats.released)
        await stats.release()
        #expect(snapshot.weekly?.used == "25")
        #expect(snapshot.subscriptionBalance == nil)
        #expect(snapshot.planName == "Allegro")
    }

    @Test(.timeLimit(.minutes(1)))
    func `cancelled enrichment returns before a cancellation ignoring plan request`() async throws {
        let plan = KimiEnrichmentLatch()
        let hangGuard = plan.hangGuard()
        defer { hangGuard.cancel() }
        let task = Task {
            try await KimiUsageFetcher.fetchUsage(
                authToken: "fixture-web-token",
                transport: Self.transport(plan: plan),
                subscriptionGrace: .seconds(30))
        }
        await plan.waitUntilStarted()
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(await !plan.released)
        await plan.release()
    }

    private static func transport(
        plan: KimiEnrichmentLatch,
        stalledPath: String = "/GetSubscription") -> ProviderHTTPTransportHandler
    {
        ProviderHTTPTransportHandler { request in
            let url = try #require(request.url)
            let json: String
            if url.path.hasSuffix(stalledPath) {
                await plan.hold()
            }
            if url.path.hasSuffix("/GetSubscription") {
                json = Self.planJSON
            } else if url.path.hasSuffix("/GetSubscriptionStats") {
                json = Self.statsJSON
            } else if url.path.hasSuffix("/usages") {
                json = #"{"usage":{"limit":"100","used":"25","remaining":"75"}}"#
            } else {
                #expect(url.path.hasSuffix("/GetUsages"))
                json = Self.usageJSON
            }
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (Data(json.utf8), response)
        }
    }

    private static let usageJSON = """
    {"usages":[{"scope":"FEATURE_CODING",
    "detail":{"limit":"100","used":"25","remaining":"75"},"limits":[]}]}
    """
    private static let statsJSON = """
    {"subscriptionBalance":{"amountUsedRatio":0.42},
    "ratelimitCode7d":{"ratio":0.17,"enabled":true}}
    """
    private static let planJSON = """
    {"subscription":{"active":true,"status":"SUBSCRIPTION_STATUS_ACTIVE",
    "goods":{"title":"Allegro"}}}
    """
}

actor KimiEnrichmentLatch {
    private(set) var started = false
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    nonisolated func hangGuard() -> Task<Void, Never> {
        Task {
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
            Issue.record("Enrichment did not finish before the fixture hang guard")
            await self.release()
        }
    }

    func hold() async {
        self.started = true
        self.startedWaiters.forEach { $0.resume() }
        self.startedWaiters.removeAll()
        if self.released {
            return
        }
        await withCheckedContinuation { self.waiters.append($0) }
    }

    func waitUntilStarted() async {
        if self.started || self.released {
            return
        }
        await withCheckedContinuation { self.startedWaiters.append($0) }
    }

    func release() {
        self.released = true
        self.startedWaiters.forEach { $0.resume() }
        self.startedWaiters.removeAll()
        self.waiters.forEach { $0.resume() }
        self.waiters.removeAll()
    }
}
