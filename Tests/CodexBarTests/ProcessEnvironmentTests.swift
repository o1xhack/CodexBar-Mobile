import Foundation
import Testing
@testable import CodexBarCore

extension ProcessEnvironment: CustomTestStringConvertible {
    public var testDescription: String {
        self.description
    }
}

struct ProcessEnvironmentTests {
    private static let sentinel = "sentinel-environment-value-must-not-be-rendered"
    private static let sentinelKey = "CODEXBAR_TEST_SENTINEL_SECRET"

    @Test
    func `fetcher descriptions and recursive mirrors hide environment contents`() {
        for value in Self.storingValues() {
            Self.expectRedacted(String(describing: value))
            Self.expectRedacted(String(reflecting: value))
            Self.expectRedacted(String(describingForTest: value))
            var output = ""
            dump(value, to: &output)
            Self.expectRedacted(output)
            Self.expectMirrorRedacted(value)
        }
    }

    @Test
    func `failed expectations hide captured environment contents`() {
        for value in Self.storingValues() {
            let captured = CapturedValue(value: value)
            let other = CapturedValue(value: nil)
            withKnownIssue("Deliberate failure exercises Swift Testing operand expansion") {
                #expect(captured == other)
            } matching: { issue in
                // Issue descriptions omit expanded operands; inspect the recorded values too.
                var rendered = ""
                dump(issue, to: &rendered)
                return !rendered.contains(Self.sentinel) && !rendered.contains(Self.sentinelKey)
            }
        }
    }

    @Test
    func `wrapper preserves dictionary access and reports only the current count`() {
        var environment = ProcessEnvironment(wrappedValue: [Self.sentinelKey: Self.sentinel])
        #expect(environment.wrappedValue[Self.sentinelKey] == Self.sentinel)
        environment.wrappedValue["ORDINARY_NAME"] = Self.sentinel
        #expect(environment.wrappedValue.count == 2)
        #expect(environment.description == "ProcessEnvironment(2 entries; redacted)")
        #expect(environment.debugDescription == environment.description)
        #expect(String(describingForTest: environment) == environment.description)
        let children = Array(Mirror(reflecting: environment).children)
        #expect(children.count == 1)
        #expect(children.first?.label == "entryCount")
        #expect(children.first?.value as? Int == 2)
        Self.expectMirrorRedacted(environment)
    }

    private static func storingValues() -> [Any] {
        let environment = [Self.sentinelKey: Self.sentinel, "ORDINARY_NAME": Self.sentinel]
        let fetcher = UsageFetcher(environment: environment)
        let browserDetection = BrowserDetection(homeDirectory: "/synthetic-home")
        let claudeFetcher = ClaudeUsageFetcher(browserDetection: browserDetection, environment: environment)
        let context = ProviderFetchContext(
            runtime: .cli,
            sourceMode: .auto,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: environment,
            settings: nil,
            fetcher: fetcher,
            claudeFetcher: claudeFetcher,
            browserDetection: browserDetection)
        return [
            fetcher, claudeFetcher, context,
            CodexStatusProbe(environment: environment),
            ClaudeStatusProbe(environment: environment),
            TTYCommandRunner.Options(baseEnvironment: environment),
            CodexCLISession.CaptureOptions(
                timeout: 1, rows: 1, cols: 1, environment: environment, extraArgs: [], workingDirectory: nil),
            PiSessionCostScanner.Options(environment: environment),
            PiSessionProcessContext(
                command: "pi", workingDirectory: nil, selectorEnvironment: ["PI_PROFILE": Self.sentinel]),
            AgentProcessRecord(
                pid: 1, ppid: 0, startedAt: nil, command: "pi", piSelectorEnvironment: ["PI_PROFILE": Self.sentinel]),
            DefaultCodexAccountReconciler(baseEnvironment: environment),
            AntigravityRemoteUsageFetcher(homeDirectory: "/synthetic-home", environment: environment),
            QwenCloudTokenPlanAPIClient.Context(
                secToken: "",
                secTokenSource: "fixture",
                environment: environment,
                apiCookieHeader: "",
                dashboardURL: URL(string: "https://example.com")!),
            MiniMaxUsageFetcher.WebFetchContext(
                cookie: "",
                authorizationToken: nil,
                region: .global,
                environment: environment,
                transport: ProviderHTTPClient.shared),
        ]
    }

    @Test
    func `optional environments preserve absence mutation and value equality`() {
        var absent = OptionalConfiguration()
        let empty = OptionalConfiguration(environment: [:])
        #expect(absent.environment == nil)
        #expect(absent != empty)
        #expect(absent == OptionalConfiguration())
        absent.environment = [Self.sentinelKey: Self.sentinel]
        #expect(absent == OptionalConfiguration(environment: [Self.sentinelKey: Self.sentinel]))
        var copy = absent
        copy.environment?["ORDINARY_NAME"] = Self.sentinel
        #expect(copy != absent)
        #expect(absent.environment?.count == 1)
        #expect(copy.environment?.count == 2)
        #expect(String(describing: copy) == String(describing: OptionalConfiguration(
            environment: ["unrelated": "value", "different": "contents"])))
        Self.expectMirrorRedacted(copy)
        absent.environment = nil
        #expect(absent == OptionalConfiguration())
        Self.expectMirrorRedacted(absent)
    }

    @Test
    func `optional wrapper counts track mutations without equating missing and empty values`() {
        var environment = ProcessEnvironment(wrappedValue: nil as [String: String]?)
        #expect(environment.description == "ProcessEnvironment(0 entries; redacted)")
        #expect(environment != ProcessEnvironment(wrappedValue: [:] as [String: String]?))
        environment.wrappedValue = [Self.sentinelKey: Self.sentinel]
        #expect(environment.description == "ProcessEnvironment(1 entries; redacted)")
        Self.expectMirrorRedacted(environment)
        environment.wrappedValue?["ORDINARY_NAME"] = Self.sentinel
        #expect(environment.description == "ProcessEnvironment(2 entries; redacted)")
    }

    private struct OptionalConfiguration: Equatable {
        @ProcessEnvironment var environment: [String: String]?
    }

    private struct CapturedValue: Equatable {
        let value: Any?

        static func == (_: Self, _: Self) -> Bool { false }
    }

    private static func expectRedacted(_ output: String) {
        #expect(!output.contains(self.sentinel))
        #expect(!output.contains(self.sentinelKey))
        #expect(!output.contains("ORDINARY_NAME"))
    }

    private static func expectMirrorRedacted(_ value: Any, depth: Int = 0) {
        guard depth < 20 else { return }
        for child in Mirror(reflecting: value).children {
            self.expectRedacted(String(describing: child.value))
            self.expectMirrorRedacted(child.value, depth: depth + 1)
        }
    }
}
