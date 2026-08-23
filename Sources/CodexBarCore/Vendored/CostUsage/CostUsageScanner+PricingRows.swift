import Foundation

extension CostUsageScanner {
    struct CodexRowCostBreakdown {
        var standardCostUSD: Double = 0
        var priorityCostUSD: Double = 0
        var standardTokens: Int = 0
        var priorityTokens: Int = 0
        var sawStandardCost = false
        var sawPriorityCost = false
        var hasUnstableTokenRows = false
        var hasTokenOverflow = false
        var hasIncompletePricing = false
        var hasEstimatedPricing = false

        var optionalStandardCostUSD: Double? {
            self.sawStandardCost ? self.standardCostUSD : nil
        }

        var optionalPriorityCostUSD: Double? {
            self.sawPriorityCost ? self.priorityCostUSD : nil
        }

        var optionalStandardTokens: Int? {
            self.standardTokens > 0 ? self.standardTokens : nil
        }

        var optionalPriorityTokens: Int? {
            self.priorityTokens > 0 ? self.priorityTokens : nil
        }

        var totalCostUSD: Double? {
            guard self.sawStandardCost || self.sawPriorityCost else { return nil }
            return self.standardCostUSD + self.priorityCostUSD
        }

        var hasModeSplit: Bool {
            self.sawPriorityCost || self.priorityTokens > 0
        }

        func isTrusted(canonicalTotalTokens: Int) -> Bool {
            let (rowTokenTotal, overflow) = self.standardTokens.addingReportingOverflow(self.priorityTokens)
            return !self.hasUnstableTokenRows
                && !self.hasTokenOverflow
                && !self.hasIncompletePricing
                && !overflow
                && rowTokenTotal == canonicalTotalTokens
        }
    }

    static func codexRowCostBreakdown(
        rows: [CodexUsageRow],
        priorityTurns: [String: CodexPriorityTurnMetadata],
        modelsDevCatalog: ModelsDevCatalog?,
        modelsDevCacheRoot: URL?,
        customPricing: CostUsageCustomPricing? = nil) -> CodexRowCostBreakdown
    {
        var breakdown = CodexRowCostBreakdown()
        for row in rows {
            let (tokenCount, tokenOverflow) = max(0, row.input).addingReportingOverflow(max(0, row.output))
            let hasTokens = row.input > 0 || row.cached > 0 || row.output > 0
            if tokenOverflow {
                breakdown.hasTokenOverflow = true
            }
            if hasTokens, row.eventIndex == nil {
                breakdown.hasUnstableTokenRows = true
            }
            if (row.unpricedTokens ?? 0) > 0 {
                breakdown.hasIncompletePricing = true
            }
            let priorityMetadata = row.turnID.flatMap { priorityTurns[$0] }
            let isPriority = priorityMetadata != nil || row.pricingMode == "priority"
            if isPriority {
                let (total, overflow) = breakdown.priorityTokens.addingReportingOverflow(tokenCount)
                breakdown.priorityTokens = overflow ? breakdown.priorityTokens : total
                breakdown.hasTokenOverflow = breakdown.hasTokenOverflow || overflow
            } else {
                let (total, overflow) = breakdown.standardTokens.addingReportingOverflow(tokenCount)
                breakdown.standardTokens = overflow ? breakdown.standardTokens : total
                breakdown.hasTokenOverflow = breakdown.hasTokenOverflow || overflow
            }
            guard let cost = self.codexResolvedCostUSD(
                for: row,
                priorityTurns: priorityTurns,
                modelsDevCatalog: modelsDevCatalog,
                modelsDevCacheRoot: modelsDevCacheRoot,
                customPricing: customPricing)
            else {
                breakdown.hasIncompletePricing = breakdown.hasIncompletePricing || hasTokens
                continue
            }
            breakdown.hasEstimatedPricing = breakdown.hasEstimatedPricing
                || self.codexPricingIsEstimated(
                    for: row,
                    priorityMetadata: priorityMetadata,
                    modelsDevCatalog: modelsDevCatalog,
                    customPricing: customPricing)
            if isPriority {
                breakdown.priorityCostUSD += cost
                breakdown.sawPriorityCost = true
            } else {
                breakdown.standardCostUSD += cost
                breakdown.sawStandardCost = true
            }
        }
        return breakdown
    }

    static func codexResolvedCostUSD(
        for row: CodexUsageRow,
        priorityTurns: [String: CodexPriorityTurnMetadata] = [:],
        modelsDevCatalog: ModelsDevCatalog?,
        modelsDevCacheRoot: URL?,
        customPricing: CostUsageCustomPricing? = nil) -> Double?
    {
        if let authoritativeCostNanos = row.knownCostNanos {
            return Double(authoritativeCostNanos) / self.costScale
        }
        let priorityMetadata = row.turnID.flatMap { priorityTurns[$0] }
        let isPriority = priorityMetadata != nil || row.pricingMode == "priority"
        let pricedModel = self.codexPricingModel(for: row, priorityMetadata: priorityMetadata)
        let overlay = customPricing ?? .empty
        let pricingDate = row.timestampUnixMs.map { Date(timeIntervalSince1970: Double($0) / 1000) }
        let baseCost = CostUsagePricing.codexCostUSD(
            model: pricedModel,
            inputTokens: row.input,
            cachedInputTokens: row.cached,
            outputTokens: row.output,
            pricingDate: pricingDate,
            modelsDevCatalog: modelsDevCatalog,
            modelsDevCacheRoot: modelsDevCacheRoot,
            customPricing: overlay)
        guard isPriority else { return baseCost }
        guard let priorityCost = CostUsagePricing.codexPriorityCostUSD(
            model: pricedModel,
            inputTokens: row.input,
            cachedInputTokens: row.cached,
            outputTokens: row.output,
            pricingDate: pricingDate,
            modelsDevCatalog: modelsDevCatalog,
            modelsDevCacheRoot: modelsDevCacheRoot,
            customPricing: overlay)
        else { return baseCost }
        return max(priorityCost, baseCost ?? priorityCost)
    }

    static func codexResolvedCostNanos(
        for row: CodexUsageRow,
        priorityTurns: [String: CodexPriorityTurnMetadata] = [:],
        modelsDevCatalog: ModelsDevCatalog?,
        modelsDevCacheRoot: URL?,
        customPricing: CostUsageCustomPricing? = nil) -> Int64?
    {
        guard let cost = self.codexResolvedCostUSD(
            for: row,
            priorityTurns: priorityTurns,
            modelsDevCatalog: modelsDevCatalog,
            modelsDevCacheRoot: modelsDevCacheRoot,
            customPricing: customPricing)
        else { return nil }
        let nanos = cost * self.costScale
        guard nanos.isFinite, nanos >= Double(Int64.min), nanos <= Double(Int64.max) else { return nil }
        return Int64(nanos.rounded())
    }

    static func codexRowsForReadTimePricing(_ usage: CostUsageFileUsage) -> [CodexUsageRow] {
        if let rows = usage.codexRows, !rows.isEmpty {
            return rows
        }
        return usage.days.flatMap { day, models in
            models.map { model, packed in
                CodexUsageRow(
                    day: day,
                    model: model,
                    turnID: nil,
                    eventIndex: nil,
                    input: packed[safe: 0] ?? 0,
                    cached: packed[safe: 1] ?? 0,
                    output: packed[safe: 2] ?? 0,
                    knownCostNanos: usage.codexCostNanos?[day]?[model],
                    pricingModel: model,
                    pricingMode: usage.codexPriorityTokens?[day]?[model] == nil ? "standard" : "priority")
            }
        }
    }

    static func codexPriorityPricingModel(
        for row: CodexUsageRow,
        priorityMetadata: CodexPriorityTurnMetadata) -> String
    {
        guard let model = priorityMetadata.model,
              CostUsagePricing.codexAPIFastMultiplier(model: model) != nil
        else { return row.model }
        return model
    }

    static func codexPricingModel(
        for row: CodexUsageRow,
        priorityMetadata: CodexPriorityTurnMetadata?) -> String
    {
        priorityMetadata.map { self.codexPriorityPricingModel(for: row, priorityMetadata: $0) }
            ?? row.pricingModel
            ?? row.model
    }

    static func codexPricingIsEstimated(
        for row: CodexUsageRow,
        priorityMetadata: CodexPriorityTurnMetadata?,
        modelsDevCatalog: ModelsDevCatalog?,
        customPricing: CostUsageCustomPricing? = nil) -> Bool
    {
        guard row.knownCostNanos == nil else { return false }
        let model = self.codexPricingModel(for: row, priorityMetadata: priorityMetadata)
        if customPricing?.rates(
            providerID: CostUsagePricing.codexModelsDevProviderID,
            model: model) != nil
        {
            return false
        }
        return !CostUsagePricing.hasExactCodexPricing(
            model,
            modelsDevCatalog: modelsDevCatalog)
    }

    static func codexPricingIsEstimated(
        model: String,
        cost: Double?,
        rowCost: CodexRowCostBreakdown?,
        rowCostIsTrusted: Bool,
        modelsDevCatalog: ModelsDevCatalog?,
        customPricing: CostUsageCustomPricing? = nil) -> Bool
    {
        guard cost != nil else { return false }
        if rowCostIsTrusted, rowCost?.totalCostUSD != nil {
            return rowCost?.hasEstimatedPricing == true
        }
        if customPricing?.rates(
            providerID: CostUsagePricing.codexModelsDevProviderID,
            model: model) != nil
        {
            return false
        }
        return !CostUsagePricing.hasExactCodexPricing(model, modelsDevCatalog: modelsDevCatalog)
    }
}
