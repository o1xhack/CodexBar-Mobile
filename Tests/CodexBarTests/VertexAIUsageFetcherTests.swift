import Foundation
import Testing
@testable import CodexBarCore

struct VertexAIUsageFetcherTests {
    @Test
    func `usage without limit name matches the regional named limit`() throws {
        let response = try VertexAIUsageFetcher.parseQuotaUsage(
            usageData: Self.fixture("issue-2958-usage-without-limit-name"),
            limitData: Self.fixture("issue-2958-regional-and-global-limits"))

        #expect(response.requestsUsedPercent == 1)
    }

    @Test
    func `existing exact limit name match remains authoritative`() throws {
        let response = try VertexAIUsageFetcher.parseQuotaUsage(
            usageData: Self.fixture("exact-named-usage"),
            limitData: Self.fixture("exact-named-limits"))

        #expect(response.requestsUsedPercent == 25)
    }

    @Test
    func `unnamed usage does not guess between limits in the same region`() throws {
        #expect(throws: VertexAIFetchError.self) {
            try VertexAIUsageFetcher.parseQuotaUsage(
                usageData: Self.fixture("issue-2958-usage-without-limit-name"),
                limitData: Self.fixture("ambiguous-regional-limits"))
        }
    }

    @Test(arguments: [[nil], [""], ["page-2", nil], ["page-2", "page-2"], [
        "page-2",
        "page-3",
        "page-2",
    ]] as [[String?]])
    func `pagination retains each distinct page once for usage and limits`(nextTokens: [String?]) async {
        let pages = Pages(nextTokens: nextTokens)
        let response = try? await VertexAIUsageFetcher.fetchUsage(
            accessToken: "fixture-token", projectId: "fixture-project", transport: pages)
        let expectedTokens: [String?] = [nil] + nextTokens.dropLast()
        #expect(await pages.tokens == expectedTokens + expectedTokens)
        #expect(response?.requestsUsedPercent == 25 * pow(3, Double(nextTokens.count - 1)) / Double(nextTokens.count))
    }

    @Test
    func `unique page tokens cannot exceed the per-query page budget`() async throws {
        let pages = Pages(nextTokens: (1...101).map { "page-\($0)" })
        await #expect {
            _ = try await VertexAIUsageFetcher.fetchUsage(
                accessToken: "fixture-token", projectId: "fixture-project", transport: pages)
        } throws: { error in
            guard case let .invalidResponse(message) = error as? VertexAIFetchError else { return false }
            return message == "Monitoring page limit exceeded"
        }
        #expect(await pages.tokens.count == 100)
    }

    @Test
    func `a final page at the page budget still succeeds`() async throws {
        let pages = Pages(nextTokens: (1..<100).map { "page-\($0)" } + [nil])
        _ = try await VertexAIUsageFetcher.fetchUsage(
            accessToken: "fixture-token", projectId: "fixture-project", transport: pages)
        #expect(await pages.tokens.count == 200)
    }

    private actor Pages: ProviderHTTPTransport {
        let nextTokens: [String?]
        private(set) var tokens: [String?] = []

        init(nextTokens: [String?]) {
            self.nextTokens = nextTokens
        }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            let url = try #require(request.url)
            let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            let token = query.first { $0.name == "pageToken" }?.value
            let isLimit = query.first { $0.name == "filter" }?.value?.contains("quota/limit") == true
            let index = self.tokens.count - (isLimit ? self.nextTokens.count : 0)
            self.tokens.append(token)
            // Bound the broken implementation by request count, never by elapsed time.
            guard self.nextTokens.indices.contains(index) else { throw URLError(.badServerResponse) }
            let value = isLimit ? 100 * Double(index + 1) : 25 * pow(3, Double(index))
            let next = self.nextTokens[index].map { #", "nextPageToken":"\#($0)""# } ?? ""
            let body = #"""
            {"timeSeries":[{"metric":{"labels":{"quota_metric":"fixture-quota"}},"resource":{},
            "points":[{"value":{"doubleValue":\#(value)}}]}]\#(next)}
            """#
            return try (Data(body.utf8), #require(HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil, headerFields: nil)))
        }
    }

    private static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: #require(Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures/Providers/VertexAI")))
    }
}
