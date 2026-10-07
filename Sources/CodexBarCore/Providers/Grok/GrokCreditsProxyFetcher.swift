import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Fetches credits from the Grok CLI's billing backend. The grok.com gRPC-web endpoint now requires
/// a browser-held WKE keypair (#2812), so the CLI proxy is the supported bearer-token path.
public enum GrokCreditsProxyFetcher {
    public static let defaultEndpoint = URL(
        string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!
    private static let requestTimeoutSeconds: TimeInterval = 15

    public static func fetch(
        credentials: GrokCredentials,
        session transport: any ProviderHTTPTransport = ProviderHTTPClient.shared,
        endpoint: URL = Self.defaultEndpoint) async throws -> GrokWebBillingSnapshot
    {
        guard !credentials.isExpired else {
            throw GrokWebBillingError.missingCredentials
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.requestTimeoutSeconds
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "x-xai-token-auth")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CodexBar", forHTTPHeaderField: "User-Agent")

        let response: ProviderHTTPResponse
        do {
            response = try await transport.response(for: request)
        } catch let error as URLError where error.code == .badServerResponse {
            throw GrokWebBillingError.invalidResponse
        } catch {
            throw error
        }
        guard response.statusCode == 200 else {
            let body = String(data: response.data.prefix(400), encoding: .utf8) ?? ""
            throw GrokWebBillingError.requestFailed(response.statusCode, body)
        }
        return try Self.parseSnapshot(response.data)
    }

    static func parseSnapshot(_ data: Data, now: Date = .now) throws -> GrokWebBillingSnapshot {
        let response: CreditsResponse
        do {
            response = try JSONDecoder().decode(CreditsResponse.self, from: data)
        } catch {
            throw GrokWebBillingError.parseFailed
        }
        guard let config = response.config else {
            throw GrokWebBillingError.parseFailed
        }

        let subscriptionTier = GrokPlan.displayName(
            from: config.subscriptionTier ?? response.subscriptionTier)
        let currentPeriodEnd = ISO8601DateParser.parse(config.currentPeriod?.end)
        let resetsAt = currentPeriodEnd ?? ISO8601DateParser.parse(config.billingPeriodEnd)
        // Match the start to the selected end; never combine different billing periods.
        let periodStart = currentPeriodEnd == nil ? config.billingPeriodStart : config.currentPeriod?.start
        let windowMinutes = Self.windowMinutes(start: periodStart, end: resetsAt, now: now)

        let percent: Double? = if let reported = config.creditUsagePercent, reported.isFinite {
            reported
        } else if let cap = config.onDemandCap?.val, cap > 0, let used = config.onDemandUsed?.val {
            used / cap * 100
        } else {
            nil
        }
        guard percent != nil || resetsAt != nil || config.prepaidBalance?.usd != nil else {
            throw GrokWebBillingError.parseFailed
        }
        return GrokWebBillingSnapshot(
            usedPercent: percent.map { min(100, max(0, $0)) },
            resetsAt: resetsAt,
            windowMinutes: windowMinutes,
            subscriptionTier: subscriptionTier,
            productUsage: config.creditUsagePercent.map {
                GrokProductUsage.composing(config.productUsage?.values ?? [], creditUsagePercent: $0)
            } ?? [],
            prepaidBalanceUSD: config.prepaidBalance?.usd)
    }

    private static func windowMinutes(start: String?, end: Date?, now: Date) -> Int? {
        guard let start = ISO8601DateParser.parse(start),
              let end, end > start, start <= now,
              let minutes = Int(exactly: (end.timeIntervalSince(start) / 60).rounded(.down)),
              minutes > 0
        else { return nil }
        return minutes
    }

    private struct CreditsResponse: Decodable {
        let config: CreditsConfig?
        let subscriptionTier: String?
    }

    private struct CreditsConfig: Decodable {
        let creditUsagePercent: Double?
        let currentPeriod: CurrentPeriod?
        let billingPeriodStart: String?
        let billingPeriodEnd: String?
        let onDemandCap: CreditsAmount?
        let onDemandUsed: CreditsAmount?
        let subscriptionTier: String?
        let productUsage: LossyProductUsageArray?
        let prepaidBalance: PrepaidBalance?
    }

    /// The official Grok billing contract defines this as USD cents. Keep malformed optional
    /// wallet data local so it cannot discard an otherwise valid quota response.
    private struct PrepaidBalance: Decodable {
        let usd: Double?

        private enum CodingKeys: String, CodingKey { case val }

        init(from decoder: Decoder) throws {
            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                self.usd = nil
                return
            }
            let cents: Int64?
            if !container.contains(.val) {
                // Proto3 JSON omits the zero scalar: an existing empty Cent object means zero.
                let empty = try? decoder.singleValueContainer().decode([String: Int64].self)
                cents = empty?.isEmpty == true ? 0 : nil
            } else if let number = try? container.decode(Int64.self, forKey: .val) {
                cents = number
            } else if let string = try? container.decode(String.self, forKey: .val) {
                cents = Int64(string)
            } else {
                cents = nil
            }
            guard let cents, cents >= 0, let exact = Double(exactly: cents) else {
                self.usd = nil
                return
            }
            self.usd = exact / 100
        }
    }

    private struct LossyProductUsageArray: Decodable {
        let values: [GrokProductUsage]?

        init(from decoder: Decoder) {
            self.values = (try? decoder.singleValueContainer().decode([LossyProductUsage].self))?
                .map(\.value)
        }
    }

    private struct LossyProductUsage: Decodable {
        let value: GrokProductUsage

        private enum CodingKeys: String, CodingKey {
            case product
            case usagePercent
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let product = try container.decode(String.self, forKey: .product)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let percent = try container.decode(Double.self, forKey: .usagePercent)
            guard !product.isEmpty, percent.isFinite, percent >= 0 else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid product usage"))
            }
            self.value = GrokProductUsage(product: product, usedPercent: percent)
        }
    }

    private struct CurrentPeriod: Decodable {
        let start: String?
        let end: String?
    }

    /// The proxy reports amounts as `{ "val": <number> }`; accept fractional values so an unusual
    /// cap/used shape cannot fail decoding of an otherwise valid response.
    private struct CreditsAmount: Decodable {
        let val: Double?
    }
}
