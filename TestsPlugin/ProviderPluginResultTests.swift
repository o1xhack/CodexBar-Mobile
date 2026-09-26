import Foundation
import Testing
@testable import CodexBarCore

struct ProviderPluginResultTests {
    @Test(arguments: ProviderPluginTransportTests.engines)
    func `result envelope preserves usage`(engine: ProviderPluginEngineKind) async throws {
        let runtime = try Self.runtime("{ usage: { primary: { usedPercent: 42 } }, sourceLabel: 'api' }", engine)
        let usage = try await runtime.fetchUsage()
        #expect(usage.primary?.usedPercent == 42)
    }

    @Test(arguments: ProviderPluginTransportTests.engines)
    func `unknown result fields are rejected`(engine: ProviderPluginEngineKind) async throws {
        let runtime = try Self.runtime("{ primary: { usedPercent: 42 }, persist: { OTHER_KEY: 'bad' } }", engine)
        await #expect(throws: ProviderPluginError.self) { try await runtime.fetchUsage() }
    }

    static func runtime(_ result: String, _ engine: ProviderPluginEngineKind) throws -> ProviderPluginRuntime {
        try ProviderPluginRuntime(source: """
        defineProvider({id: 'fireworks', name: 'Fixture', endpoints: ['https://api.fireworks.ai'], settings: [],
          async fetchUsage(ctx) { return \(result); }});
        """, engine: engine)
    }
}

extension ProviderPluginResultTests {
    @Test(arguments: ProviderPluginTransportTests.engines, [
        "{usage:{empty:true}, sourceLabel:null}", "{usage:{empty:true}, sourceLabel:1}",
        "{usage:{empty:true}, sourceLabel:''}", "{usage:{empty:true}, sourceLabel:'x'.repeat(257)}",
        "{usage:{empty:true}, sourceLabel:'line\\nfeed'}", "{usage:{empty:true}, surprise:1}",
        "{usage:{empty:true}, persist:null}", "{usage:{empty:true}, persist:[]}",
        "{usage:{empty:true}, persist:{ACCOUNT_SLUG:3}}", "{usage:{empty:true}, persist:{ACCOUNT_SLUG:'..'}}",
        "{usage:{empty:true}, persist:{OPENAI_PROJECT_ID:'project'}}",
        "{usage:{empty:true}, persist:{FIREWORKS_API_KEY:'secret'}}",
        "{usage:{empty:true}, persist:{ACCOUNT_SLUG:'x'.repeat(257)}}",
        "{usage:{empty:true}, card:{openAIAPIUsage:{}}}", "{usage:{empty:true, typo:1}}",
    ])
    func `malformed envelope values are rejected on both engines`(
        engine: ProviderPluginEngineKind,
        value: String) async throws
    {
        let runtime = try Self.runtime(value, engine)
        await #expect(throws: ProviderPluginError.self) { try await runtime.fetchResult() }
    }

    @Test(arguments: ProviderPluginTransportTests.engines)
    func `OpenAI card adapter rejects unknown unbounded and malformed fields`(
        engine: ProviderPluginEngineKind) async throws
    {
        for card in [
            "null",
            "[]",
            "{}",
            "{unknown:1}",
            "{openAIAPIUsage:{daily:[],historyDays:1,unknown:true}}",
            "{openAIAPIUsage:{daily:[],historyDays:0}}",
            "{openAIAPIUsage:{daily:[],historyDays:366}}",
            "{openAIAPIUsage:{daily:[],historyDays:'1'}}",
            "{openAIAPIUsage:{daily:Array(367).fill({}),historyDays:1}}",
            "{openAIAPIUsage:{daily:[],historyDays:1,projectID:1}}",
        ] {
            let source = """
            defineProvider({id:'openai',name:'Fixture',endpoints:['https://api.openai.com'],settings:[],
              async fetchUsage(ctx) { return {usage:{empty:true},card:\(card)}; }});
            """
            let runtime = try ProviderPluginRuntime(source: source, engine: engine)
            await #expect(throws: ProviderPluginError.self) { try await runtime.fetchResult() }
        }
        let other = try ProviderPluginRuntime(source: """
        defineProvider({id:'openai',name:'Fixture',endpoints:['https://api.openai.com'],settings:[],
          async fetchUsage(ctx) { return {usage:{empty:true},persist:{ACCOUNT_SLUG:'fixture'}}; }});
        """, engine: engine)
        await #expect(throws: ProviderPluginError.self) { try await other.fetchResult() }
    }

    @Test
    func `CLI writes preserve unrelated config and reject stale or foreign changes`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CodexBarConfigStore(fileURL: directory.appendingPathComponent("config.json"))
        var config = CodexBarConfig.makeDefault()
        var fireworks = ProviderConfig(id: .fireworks)
        fireworks.apiKey = "fixture-key"
        var other = ProviderConfig(id: .openai)
        other.workspaceID = "project-fixture"
        config.setProviderConfig(fireworks)
        config.setProviderConfig(other)
        try store.save(config)
        let writer = ProviderPluginConfigWriter()
        #expect(await writer.save(
            provider: .fireworks,
            values: ["ACCOUNT_SLUG": "fixture"],
            expected: fireworks,
            store: store) == .saved)
        let saved = try #require(try store.load())
        #expect(ProviderPluginResultPolicy.matches(saved.providerConfig(for: .openai), other))
        #expect(saved.providerConfig(for: .fireworks)?.apiKey == "fixture-key")
        #expect(saved.providerConfig(for: .fireworks)?.accountSlug == "fixture")
        #expect(await writer.save(
            provider: .fireworks,
            values: ["ACCOUNT_SLUG": "late"],
            expected: fireworks,
            store: store) == .stale)
        let current = saved.providerConfig(for: .fireworks)
        #expect(await writer.save(
            provider: .fireworks,
            values: ["ACCOUNT_SLUG": "fixture"],
            expected: current,
            store: store) == .unchanged)
        #expect(await writer
            .save(provider: .openai, values: ["ACCOUNT_SLUG": "bad"], expected: other, store: store) == .failed)
        #expect(await writer.save(
            provider: .fireworks,
            values: ["OPENAI_PROJECT_ID": "bad"],
            expected: current,
            store: store) == .failed)
        let reloaded = try #require(try store.load())
        #expect(try store.encodedData(for: reloaded) == store.encodedData(for: saved))
        let blocked = directory.appendingPathComponent("file")
        try Data().write(to: blocked)
        #expect(await writer.save(
            provider: .fireworks,
            values: ["ACCOUNT_SLUG": "fixture"],
            expected: CodexBarConfig.makeDefault().providerConfig(for: .fireworks),
            store: CodexBarConfigStore(fileURL: blocked.appendingPathComponent("config.json"))) ==
            .failed)
    }
}

extension ProviderPluginResultTests {
    @Test(arguments: ProviderPluginTransportTests.engines)
    func `hidden unknown keys and user plugin write requests are refused`(
        engine: ProviderPluginEngineKind) async throws
    {
        for value in [
            "Object.defineProperty({usage:{empty:true}}, 'unknown', {value:1})",
            "Object.defineProperty({usage:{empty:true}}, 'sourceLabel', {value:1})",
            "{usage:{empty:true}, [Symbol('usage')]:1}",
            "{usage:{details:Array(2147483648)}}",
        ] {
            let runtime = try Self.runtime(value, engine)
            await #expect(throws: ProviderPluginError.self) { try await runtime.fetchResult() }
        }
        let runtime = try ProviderPluginRuntime(source: """
        defineProvider({id:'fireworks',name:'Fixture',endpoints:['https://api.fireworks.ai'],settings:[],
          async fetchUsage(ctx) { return {usage:{empty:true},persist:{ACCOUNT_SLUG:'fixture'}}; }});
        """, enforcesUserResponsePolicy: true, engine: engine)
        await #expect(throws: ProviderPluginError.self) { try await runtime.fetchResult() }
    }

    @Test
    func `cancelled CLI discovery cannot write settings`() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CodexBarConfigStore(fileURL: directory.appendingPathComponent("config.json"))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await ProviderPluginConfigWriter.shared.save(
                provider: .fireworks, values: ["ACCOUNT_SLUG": "fixture"], expected: nil, store: store)
        }
        #expect(await task.value == .stale)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    }
}
