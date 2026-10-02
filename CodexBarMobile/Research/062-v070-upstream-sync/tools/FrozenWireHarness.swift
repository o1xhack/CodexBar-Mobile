import Foundation

@main
struct Harness {
    static let capture = Date(timeIntervalSince1970: 1_790_913_600)
    static let monthlyReset = capture.addingTimeInterval(86400 * 20)

    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 4 else { fatalError("mode, path, device required") }
        if args[1] == "merge" {
            let envelopes = try args[2...3].map {
                try CloudSyncConstants.makeJSONDecoder().decode(
                    ProviderUsageEnvelope.self, from: Data(contentsOf: URL(fileURLWithPath: $0)))
            }
            let snapshots = envelopes.map { envelope in
                let localTokens = ProviderUsageSnapshot(
                    providerID: "codex",
                    providerName: "Synthetic Codex",
                    primary: nil,
                    secondary: nil,
                    accountEmail: nil,
                    loginMethod: nil,
                    statusMessage: nil,
                    isError: false,
                    lastUpdated: envelope.provider.lastUpdated,
                    costSummary: envelope.provider.costSummary)
                return SyncedUsageSnapshot(
                    providers: [envelope.provider, localTokens],
                    syncTimestamp: envelope.syncTimestamp,
                    deviceName: envelope.deviceName,
                    deviceID: envelope.deviceID)
            }
            for sources in [snapshots, Array(snapshots.reversed())] {
                guard let merged = ProviderSnapshotMerger.mergeSnapshots(sources),
                      let kimi = merged.providers.first(where: { $0.providerID == "kimi" }),
                      let codex = merged.providers.first(where: { $0.providerID == "codex" })
                else { fatalError("Both fixture providers must survive the merge") }
                precondition(merged.providers.count == 2)
                // Equal capture times resolve deterministically to writer mac-b.
                precondition(kimi.primary?.usedPercent == envelopes[1].provider.primary?.usedPercent)
                precondition(kimi.primary?.resetsAt == envelopes[1].provider.primary?.resetsAt)
                precondition(kimi.rateWindows.first?.usedPercent == kimi.primary?.usedPercent)
                precondition(kimi.costSummary?.daily.first?.totalTokens == 12)
                precondition(kimi.costSummary?.daily.first?.costIsKnown == false)
                precondition(codex.costSummary?.daily.first?.totalTokens == 24)
                precondition(codex.costSummary?.daily.first?.costIsKnown == false)
                #if NEW_WIRE
                precondition(kimi.primary?.blockingQuota == envelopes[1].provider.primary?.blockingQuota)
                let expectedNames = envelopes.flatMap { $0.provider.costSummary?.daily.first?.modelsUsed ?? [] }
                precondition(codex.costSummary?.daily.first?.modelsUsed ==
                    (expectedNames.isEmpty ? nil : Array(Set(expectedNames)).sorted()))
                #endif
            }
            // Removed devices must not reappear from the previous reduction.
            let retained = ProviderSnapshotMerger.mergeSnapshots([snapshots[0]])
            precondition(retained?.deviceName == "Synthetic mac-a")
            precondition(retained?.providers.first(where: { $0.providerID == "codex" })?
                .costSummary?.daily.first?.totalTokens == 12)
            print("PASS: real consumer merge, stable order, blocked availability, local token sum, removed writer")
            return
        }
        let url = URL(fileURLWithPath: args[2])
        if args[1] == "write" {
            var window = SyncRateWindow(
                id: "primary", label: "Weekly", usedPercent: 25,
                windowMinutes: 10080, resetsAt: capture.addingTimeInterval(86400), resetDescription: nil)
            var daily = SyncDailyPoint(
                dayKey: "2026-10-01", costUSD: 0, totalTokens: 12,
                costIsKnown: false, tokenCountIsKnown: true)
            #if NEW_WIRE
            window = SyncRateWindow(
                id: "primary", label: "Weekly", usedPercent: 100,
                windowMinutes: 10080, resetsAt: self.monthlyReset, resetDescription: nil,
                blockingQuota: SyncBlockingQuota(
                    windowID: "kimi-monthly", rawUsedPercent: 25,
                    rawResetsAt: self.capture.addingTimeInterval(86400),
                    rawResetDescription: nil, rawNextRegenPercent: nil))
            daily = SyncDailyPoint(
                dayKey: "2026-10-01", costUSD: 0, totalTokens: 12,
                costIsKnown: false, tokenCountIsKnown: true,
                modelsUsed: ["Observed Fictitious Model"])
            #endif
            let summary = SyncCostSummary(
                sessionCostUSD: nil, sessionTokens: 12,
                last30DaysCostUSD: nil, last30DaysTokens: 12, daily: [daily])
            let provider = ProviderUsageSnapshot(
                providerID: "kimi", providerName: "Synthetic Kimi", primary: window,
                secondary: nil, accountEmail: nil, loginMethod: nil, statusMessage: nil,
                isError: false, lastUpdated: capture, costSummary: summary, rateWindows: [window])
            let envelope = ProviderUsageEnvelope(
                deviceID: args[3], deviceName: "Synthetic " + args[3], appVersion: "fixture",
                mobileVersion: "fixture", syncTimestamp: self.capture,
                notificationPushEnabled: false, provider: provider)
            try CloudSyncConstants.makeJSONEncoder().encode(envelope).write(to: url)
            return
        }
        let envelope = try CloudSyncConstants.makeJSONDecoder().decode(
            ProviderUsageEnvelope.self, from: Data(contentsOf: url))
        precondition(envelope.deviceID == args[3])
        let provider = envelope.provider
        precondition(provider.primary == provider.rateWindows.first)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let sourceProvider = json["provider"] as! [String: Any]
        let sourcePrimary = sourceProvider["primary"] as! [String: Any]
        let isNew = sourcePrimary["blockingQuota"] != nil
        precondition(provider.primary?.usedPercent == (isNew ? 100 : 25))
        precondition(provider.primary?.resetsAt == (isNew ? self.monthlyReset : self.capture.addingTimeInterval(86400)))
        precondition(provider.costSummary?.daily.first?.costIsKnown == false)
        precondition(provider.costSummary?.daily.first?.totalTokens == 12)
        #if NEW_WIRE
        precondition(provider.primary?.blockingQuota?.rawUsedPercent == (isNew ? 25 : nil))
        precondition(provider.primary?.blockingQuota?.windowID == (isNew ? "kimi-monthly" : nil))
        precondition(provider.primary?.blockingQuota?
            .rawResetsAt == (isNew ? self.capture.addingTimeInterval(86400) : nil))
        precondition(provider.costSummary?.daily.first?.modelsUsed == (isNew ? ["Observed Fictitious Model"] : nil))
        #endif
        let roundtrip = try CloudSyncConstants.makeJSONEncoder().encode(envelope)
        let restored = try CloudSyncConstants.makeJSONDecoder().decode(ProviderUsageEnvelope.self, from: roundtrip)
        precondition(restored == envelope)
        print(
            "PASS \(args[3]) \(isNew ? "new" : "old") producer: envelope, availability, unknown cost, independent device ID, JSON roundtrip")
    }
}
