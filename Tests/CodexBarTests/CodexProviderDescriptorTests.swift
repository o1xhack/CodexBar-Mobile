import Foundation
import Testing
@testable import CodexBarCore

struct CodexProviderDescriptorTests {
    @Test
    func `usage dashboard resolves the registered Codex analytics usage URL`() throws {
        let metadata = try #require(ProviderDefaults.metadata[.codex])
        let dashboardURL = try #require(metadata.dashboardURL)
        let url = try #require(URL(string: dashboardURL))
        #expect(url.absoluteString == "https://chatgpt.com/codex/cloud/settings/analytics#usage")
        #expect(url.fragment == "usage")
    }
}
