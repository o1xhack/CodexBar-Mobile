import Foundation
import Testing
@testable import CodexBarCLI
@testable import CodexBarCore

struct GrokPrepaidBalanceTests {
    enum Wallet: CaseIterable {
        case absent, positive, stringAmount, zero, empty, null, malformed, negative, fractional, overflow
        case unknownObject, scalar, nullAmount, precisionLoss

        var field: String {
            switch self {
            case .absent: ""
            case .positive: #","prepaidBalance":{"val":1446}"#
            case .stringAmount: #","prepaidBalance":{"val":"1446"}"#
            case .zero: #","prepaidBalance":{"val":0}"#
            case .empty: #","prepaidBalance":{}"#
            case .null: #","prepaidBalance":null"#
            case .malformed: #","prepaidBalance":{"val":"invalid"}"#
            case .negative: #","prepaidBalance":{"val":-1}"#
            case .fractional: #","prepaidBalance":{"val":1.5}"#
            case .overflow: #","prepaidBalance":{"val":9223372036854775808}"#
            case .unknownObject: #","prepaidBalance":{"amount":100}"#
            case .scalar: #","prepaidBalance":100"#
            case .nullAmount: #","prepaidBalance":{"val":null}"#
            case .precisionLoss: #","prepaidBalance":{"val":9007199254740993}"#
            }
        }

        var balance: Double? {
            switch self {
            case .positive, .stringAmount: 14.46
            case .zero, .empty: 0
            default: nil
            }
        }
    }

    @Test(arguments: Wallet.allCases)
    func `CLI JSON exports only valid prepaid USD balances without changing quota`(wallet: Wallet) throws {
        let data = Data("{\"config\":{\"creditUsagePercent\":12.5\(wallet.field)}}".utf8)
        let billing = try GrokCreditsProxyFetcher.parseSnapshot(data)
        let usage = Self.usage(billing)
        #expect(usage.primary?.usedPercent == 12.5)
        #expect(usage.providerCost?.balance == wallet.balance)
        let payload = ProviderPayload(
            provider: .grok,
            account: nil,
            version: nil,
            source: "grok-cli-proxy",
            status: nil,
            usage: usage,
            credits: nil,
            antigravityPlanInfo: nil,
            openaiDashboard: nil,
            error: nil)
        let encoded = try JSONEncoder().encode(payload)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let exportedUsage = try #require(object["usage"] as? [String: Any])
        let cost = exportedUsage["providerCost"] as? [String: Any]
        if let balance = wallet.balance {
            #expect(cost?["balance"] as? Double == balance)
            #expect(cost?["currencyCode"] as? String == "USD")
            #expect(cost?["used"] as? Double == 0)
            #expect(cost?["limit"] as? Double == 0)
        } else {
            #expect(cost == nil)
        }
    }

    @Test(arguments: [
        #""onDemandCap":{"val":1000},"onDemandUsed":{"val":250},"#,
        #""billingPeriodEnd":"2026-08-13T00:00:00Z","#,
        "",
    ])
    func `wallet is retained on legacy and quota absent proxy shapes`(fields: String) throws {
        let data = Data("{\"config\":{\(fields)\"prepaidBalance\":{\"val\":1446}}}".utf8)
        let usage = try Self.usage(GrokCreditsProxyFetcher.parseSnapshot(data))
        #expect(usage.providerCost?.balance == 14.46)
        #expect(usage.primary?.usedPercent == (fields.contains("onDemandCap") ? 25 : nil))
    }

    @Test
    func `wallet survives plan overlay and usage enrichment`() async throws {
        let proxy = try GrokCreditsProxyFetcher.parseSnapshot(Data(#"{"config":{"prepaidBalance":{"val":1446}}}"#.utf8))
            .applying(subscriptionTier: "SuperGrok")
        let credentials = GrokCredentials(
            accessToken: "synthetic",
            refreshToken: nil,
            scope: "",
            authMode: nil,
            userId: nil,
            email: nil,
            firstName: nil,
            lastName: nil,
            teamId: nil,
            oidcIssuer: nil,
            oidcClientId: nil,
            expiresAt: nil,
            createTime: nil)
        let enriched = try await GrokOAuthFetchStrategy.resolvingUnknownUsage(
            proxy, credentials: credentials, grpcBilling: { _ in
                GrokWebBillingSnapshot(usedPercent: 70, resetsAt: nil)
            }).snapshot
        let usage = Self.usage(enriched)
        #expect(usage.primary?.usedPercent == 70)
        #expect(usage.providerCost?.balance == 14.46)
    }

    private static func usage(_ billing: GrokWebBillingSnapshot) -> UsageSnapshot {
        GrokUsageSnapshot(
            billing: nil,
            webBilling: billing,
            credentials: nil,
            localSummary: nil,
            cliVersion: nil,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)).toUsageSnapshot()
    }
}
