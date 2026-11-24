import Foundation

extension CostUsageScanner {
    struct CodexRowCostBreakdown {
        var standardCostUSD: Double = 0
        var priorityCostUSD: Double = 0
        var ultrafastCostUSD: Double = 0
        var ultrafastTokens = 0
        var sawUltrafastCost = false
        var standardTokens: Int = 0
        var priorityTokens: Int = 0
        var sawStandardCost = false
        var sawPriorityCost = false
        var hasUnstableTokenRows = false
        var hasTokenOverflow = false
        var hasIncompletePricing = false
        var hasEstimatedPricing = false
        /// Requests with tokens whose cost is known; marked or unresolvable requests are counted separately.
        var pricedRequestCount = 0
        var unpricedRequestCount = 0

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
            guard self.sawStandardCost || self.sawPriorityCost || self.sawUltrafastCost else { return nil }
            return self.standardCostUSD + self.priorityCostUSD + self.ultrafastCostUSD
        }

        var hasModeSplit: Bool {
            self.sawPriorityCost || self.priorityTokens > 0
        }

        /// The rows account for exactly the group's billed tokens, so their per-request costs describe it.
        func coversGroup(canonicalTotalTokens: Int) -> Bool {
            !self.hasUnstableTokenRows && !self.hasTokenOverflow
                && CheckedSum.integers([self.standardTokens, self.priorityTokens, self.ultrafastTokens])
                == canonicalTotalTokens
        }
    }

    static func codexRowCostBreakdown(
        rows: [CodexUsageRow],
        priorityTurns: [String: CodexPriorityTurnMetadata],
        modelsDevCatalog: ModelsDevCatalog?,
        modelsDevCacheRoot: URL?,
        customPricing: CostUsageCustomPricing? = nil,
        pricingResolver: CostUsagePricing.CodexResolver? = nil) -> CodexRowCostBreakdown
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
            let isMarkedUnpriced = (row.unpricedTokens ?? 0) > 0
            if isMarkedUnpriced {
                breakdown.hasIncompletePricing = true
            }
            let priorityMetadata = row.turnID.flatMap { priorityTurns[$0] }
            let isPriority = priorityMetadata != nil || row.pricingMode == "priority"
            if row.pricingMode == "ultrafast" {
                let (total, overflow) = breakdown.ultrafastTokens.addingReportingOverflow(tokenCount)
                breakdown.ultrafastTokens = overflow ? breakdown.ultrafastTokens : total
                breakdown.hasTokenOverflow = breakdown.hasTokenOverflow || overflow
            } else if isPriority {
                let (total, overflow) = breakdown.priorityTokens.addingReportingOverflow(tokenCount)
                breakdown.priorityTokens = overflow ? breakdown.priorityTokens : total
                breakdown.hasTokenOverflow = breakdown.hasTokenOverflow || overflow
            } else {
                let (total, overflow) = breakdown.standardTokens.addingReportingOverflow(tokenCount)
                breakdown.standardTokens = overflow ? breakdown.standardTokens : total
                breakdown.hasTokenOverflow = breakdown.hasTokenOverflow || overflow
            }
            // Retained history without proven pricing stays unknown; current list prices are not its price.
            guard !isMarkedUnpriced, let cost = self.codexResolvedCostUSD(
                for: row,
                priorityTurns: priorityTurns,
                modelsDevCatalog: modelsDevCatalog,
                modelsDevCacheRoot: modelsDevCacheRoot,
                customPricing: customPricing,
                pricingResolver: pricingResolver)
            else {
                breakdown.hasIncompletePricing = breakdown.hasIncompletePricing || hasTokens
                if hasTokens { breakdown.unpricedRequestCount += 1 }
                continue
            }
            if hasTokens { breakdown.pricedRequestCount += 1 }
            breakdown.hasEstimatedPricing = breakdown.hasEstimatedPricing
                || self.codexPricingIsEstimated(
                    for: row,
                    priorityMetadata: priorityMetadata,
                    modelsDevCatalog: modelsDevCatalog,
                    customPricing: customPricing,
                    pricingResolver: pricingResolver)
            if row.pricingMode == "ultrafast" {
                breakdown.ultrafastCostUSD += cost
                breakdown.sawUltrafastCost = true
            } else if isPriority {
                breakdown.priorityCostUSD += cost
                breakdown.sawPriorityCost = true
            } else {
                breakdown.standardCostUSD += cost
                breakdown.sawStandardCost = true
            }
        }
        return breakdown
    }

    // MARK: - File cache construction

    static func codexResolvedCostUSD(
        for row: CodexUsageRow,
        priorityTurns: [String: CodexPriorityTurnMetadata] = [:],
        modelsDevCatalog: ModelsDevCatalog?,
        modelsDevCacheRoot: URL?,
        customPricing: CostUsageCustomPricing? = nil,
        pricingResolver: CostUsagePricing.CodexResolver? = nil) -> Double?
    {
        if let authoritativeCostNanos = row.knownCostNanos {
            return Double(authoritativeCostNanos) / self.costScale
        }
        if row.isIncludedInPlan == true { return 0 }
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
            customPricing: overlay,
            pricingResolver: pricingResolver)
        if row.pricingMode == "ultrafast" {
            return CostUsagePricing.codexAPIUltrafastMultiplier(model: pricedModel, date: pricingDate)
                .flatMap { multiplier in baseCost.map { $0 * multiplier } }
        }
        guard isPriority else { return baseCost }
        guard let priorityCost = CostUsagePricing.codexPriorityCostUSD(
            model: pricedModel,
            inputTokens: row.input,
            cachedInputTokens: row.cached,
            outputTokens: row.output,
            pricingDate: pricingDate,
            modelsDevCatalog: modelsDevCatalog,
            modelsDevCacheRoot: modelsDevCacheRoot,
            customPricing: overlay,
            pricingResolver: pricingResolver)
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

    /// The model whose rates price `row`, as the custom overlay and catalogs look it up.
    static func codexPricedModel(for row: CodexUsageRow, priorityTurns: [String: CodexPriorityTurnMetadata]) -> String {
        guard row.pricingMode != "ultrafast" else { return row.pricingModel ?? row.model }
        return row.turnID.flatMap { priorityTurns[$0] }
            .map { self.codexPriorityPricingModel(for: row, priorityMetadata: $0) } ?? row.pricingModel ?? row.model
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
        customPricing: CostUsageCustomPricing? = nil,
        pricingResolver: CostUsagePricing.CodexResolver? = nil) -> Bool
    {
        guard row.knownCostNanos == nil else { return false }
        // Upstream v0.75 (#4452): ChatGPT-created Auto-review requests are included in the plan and
        // priced at $0 with certainty, so they must not mark the day as estimated for the iPhone.
        if row.isIncludedInPlan == true { return false }
        let model = self.codexPricingModel(for: row, priorityMetadata: priorityMetadata)
        if customPricing?.rates(
            providerID: CostUsagePricing.codexModelsDevProviderID,
            model: model) != nil
        {
            return false
        }
        return !CostUsagePricing.hasExactCodexPricing(
            model,
            modelsDevCatalog: modelsDevCatalog,
            pricingResolver: pricingResolver)
    }

    static func codexPricingIsEstimated(
        model: String,
        cost: Double?,
        rowCost: CodexRowCostBreakdown?,
        rowCostIsTrusted: Bool,
        modelsDevCatalog: ModelsDevCatalog?,
        customPricing: CostUsageCustomPricing? = nil,
        pricingResolver: CostUsagePricing.CodexResolver? = nil) -> Bool
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
        return !CostUsagePricing.hasExactCodexPricing(
            model,
            modelsDevCatalog: modelsDevCatalog,
            pricingResolver: pricingResolver)
    }
}
