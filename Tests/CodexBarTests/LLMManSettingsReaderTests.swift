import Testing
@testable import CodexBarCore

struct LLMManSettingsReaderTests {
    static let addresses: [(String, String)] = [
        ("localhost", "http://localhost:17434"),
        ("127.0.0.1", "http://127.0.0.1:17434"),
        ("0.0.0.0", "http://127.0.0.1:17434"),
        ("0.0.0.0:18000", "http://127.0.0.1:18000"),
        ("http://0.0.0.0:18000", "http://127.0.0.1:18000"),
        ("192.168.1.10", "http://192.168.1.10:17434"),
        ("daemon.local", "http://daemon.local:17434"),
        ("[::1]", "http://[::1]:17434"),
        ("127.0.0.1:18000", "http://127.0.0.1:18000"),
        ("http://localhost", "http://localhost"),
        ("https://llmman.example.com", "https://llmman.example.com"),
        ("http://127.0.0.1:17434///", "http://127.0.0.1:17434"),
        ("http://127.0.0.1:17434/v1/", "http://127.0.0.1:17434/v1"),
    ]

    @Test(arguments: Self.addresses)
    func `daemon addresses preserve upstream port defaults`(address: (String, String)) {
        #expect(LLMManSettingsReader.baseURL(environment: ["LLMMAN_HOST": address.0])?.absoluteString == address.1)
    }

    @Test(arguments: [
        "http://127.0.0.1:17434?probe=1",
        "http://127.0.0.1:17434#x",
        "localhost?probe=1",
        "127.0.0.1#x",
        "http://127.0.0.1:17434?",
        "http://127.0.0.1:17434#",
        "http://public.example.com",
        "public.example.com",
        "http://user:password@127.0.0.1:17434",
        "https://user:password@example.com",
        "file:///tmp/llmman",
    ])
    func `unsafe or unsupported URL components are rejected`(address: String) {
        #expect(LLMManSettingsReader.baseURL(environment: ["LLMMAN_HOST": address]) == nil)
    }
}
