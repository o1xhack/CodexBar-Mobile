#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

enum CostUsagePricingKey {
    static func codex(
        modelsDevArtifact: ModelsDevCacheArtifact?,
        formulaVersion: Int,
        parserHash: String? = nil,
        modelsDevProviderIDs: Set<String> = CostUsagePricing.codexModelsDevProviderIDs,
        customPricingFingerprint: String = CostUsageCustomPricing.load().fingerprint) -> String
    {
        var parts = [
            "costFormulaVersion=\(formulaVersion)",
            "builtInPricing:\n\(CostUsagePricing.codexBuiltInPricingFingerprint())",
            "customPricing=\(customPricingFingerprint)",
        ]
        if let parserHash {
            parts.append("parserHash=\(parserHash)")
        }

        let prefix: String
        if let modelsDevArtifact {
            prefix = "models-dev-v\(modelsDevArtifact.version)"
            let modelsDevPricing = self.modelsDevPricingFingerprint(
                modelsDevArtifact.catalog,
                providerIDs: modelsDevProviderIDs)
            parts.append("modelsDevPricing:\n\(modelsDevPricing)")
        } else {
            prefix = "builtin"
            parts.append("modelsDevPricing:none")
        }
        return "\(prefix)-\(self.sha256Hex(Data(parts.joined(separator: "\n").utf8)))"
    }

    private static func modelsDevPricingFingerprint(
        _ catalog: ModelsDevCatalog,
        providerIDs: Set<String>) -> String
    {
        var parts: [String] = []
        let normalizedProviderIDs = Set(providerIDs.map(ModelsDevProvider.normalizeProviderID))
        for providerID in normalizedProviderIDs.sorted() {
            guard let provider = catalog.providers[providerID] else { continue }
            for modelKey in provider.models.keys.sorted() {
                guard let model = provider.models[modelKey], model.isPriceable else { continue }
                let cost = model.cost
                let contextOver200K = cost?.contextOver200K
                parts.append([
                    "provider=\(providerID)",
                    "model=\(modelKey)",
                    model.id,
                    CostUsagePricing.optionalPricingFingerprint(cost?.input),
                    CostUsagePricing.optionalPricingFingerprint(cost?.output),
                    CostUsagePricing.optionalPricingFingerprint(cost?.cacheRead),
                    CostUsagePricing.optionalPricingFingerprint(cost?.cacheWrite),
                    contextOver200K == nil ? "contextOver200K=absent" : "contextOver200K=present",
                    model.pricing(providerID: providerID, providerName: nil)?.thresholdTokens.map(String.init) ?? "nil",
                    CostUsagePricing.optionalPricingFingerprint(contextOver200K?.input),
                    CostUsagePricing.optionalPricingFingerprint(contextOver200K?.output),
                    CostUsagePricing.optionalPricingFingerprint(contextOver200K?.cacheRead),
                    CostUsagePricing.optionalPricingFingerprint(contextOver200K?.cacheWrite),
                ].joined(separator: "|"))
            }
        }
        return parts.joined(separator: "\n")
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
