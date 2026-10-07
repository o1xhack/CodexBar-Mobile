import Foundation

/// v0.72 wire fixture: a WorkBuddy-like percentage provider with a balance description and a
/// detail row carrying progress metadata, plus a LithosAI-like balance amount.
@main
struct Harness {
    static let capture = Date(timeIntervalSince1970: 1_791_500_000)
    static let reset = capture.addingTimeInterval(86400 * 18)
    static let balanceText = "3,800 / 5,000 credits left"

    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 4 else { fatalError("mode, path, device required") }
        if args[1] == "merge" {
            let envelopes = try args[2...3].map {
                try CloudSyncConstants.makeJSONDecoder().decode(
                    ProviderUsageEnvelope.self, from: Data(contentsOf: URL(fileURLWithPath: $0)))
            }
            let snapshots = envelopes.map { envelope in
                SyncedUsageSnapshot(
                    providers: [envelope.provider],
                    syncTimestamp: envelope.syncTimestamp,
                    deviceName: envelope.deviceName,
                    deviceID: envelope.deviceID)
            }
            for sources in [snapshots, Array(snapshots.reversed())] {
                guard let merged = ProviderSnapshotMerger.mergeSnapshots(sources),
                      let provider = merged.providers.first(where: { $0.providerID == "workbuddy" })
                else { fatalError("The fixture provider must survive the merge") }
                precondition(merged.providers.count == 1)
                precondition(provider.primary?.usedPercent == 24)
                precondition(provider.primary?.resetsAt == self.reset)
                precondition(provider.primary?.resetDescription == self.balanceText)
                precondition(provider.details.first?.rows.first?.label == "Credits")
                precondition(provider.providerAmount?.amount == 42.5)
                #if NEW_WIRE
                // Equal capture times: whichever writer wins, the merged window and details
                // must be one writer's complete observation, never a mix of old and new fields.
                let winnerHasMetadata = provider.primary?.balanceDescription != nil
                precondition(winnerHasMetadata == (provider.details.first?.rows.first?.progress != nil))
                let anyNewWriter = envelopes.contains { $0.provider.primary?.balanceDescription != nil }
                if !anyNewWriter { precondition(!winnerHasMetadata) }
                if winnerHasMetadata {
                    precondition(provider.primary?.balanceDescription == self.balanceText)
                    precondition(provider.details.first?.rows.first?.usageValue == 3800)
                }
                #endif
            }
            let retained = ProviderSnapshotMerger.mergeSnapshots([snapshots[0]])
            precondition(retained?.deviceName == "Synthetic mac-a")
            print("PASS: real consumer merge, stable winner, complete per-writer metadata, removed writer")
            return
        }
        let url = URL(fileURLWithPath: args[2])
        if args[1] == "write" {
            var window = SyncRateWindow(
                id: "primary", label: "Monthly", usedPercent: 24,
                windowMinutes: 43200, resetsAt: self.reset, resetDescription: self.balanceText)
            var row = SyncProviderDetailSection.Row(label: "Credits", value: "3,800")
            #if NEW_WIRE
            window = SyncRateWindow(
                id: "primary", label: "Monthly", usedPercent: 24,
                windowMinutes: 43200, resetsAt: self.reset, resetDescription: self.balanceText,
                balanceDescription: self.balanceText)
            row = SyncProviderDetailSection.Row(
                id: "credits-left", label: "Credits", value: "3,800",
                progress: .init(used: 1200, total: 5000), usageValue: 3800)
            #endif
            let provider = ProviderUsageSnapshot(
                providerID: "workbuddy", providerName: "Synthetic WorkBuddy", primary: window,
                secondary: nil, accountEmail: nil, loginMethod: "Pro", statusMessage: nil,
                isError: false, lastUpdated: self.capture, rateWindows: [window],
                providerAmount: SyncProviderAmount(
                    kind: "balance", amount: 42.5, currencyCode: "USD", period: "Prepaid credits",
                    isEstimated: false),
                details: [SyncProviderDetailSection(title: nil, rows: [row])])
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
        precondition(provider.primary?.usedPercent == 24)
        precondition(provider.primary?.resetDescription == self.balanceText)
        precondition(provider.details.first?.rows.first?.value == "3,800")
        precondition(provider.providerAmount?.amount == 42.5)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let sourcePrimary = (json["provider"] as! [String: Any])["primary"] as! [String: Any]
        let isNew = sourcePrimary["balanceDescription"] != nil
        #if NEW_WIRE
        precondition(provider.primary?.balanceDescription == (isNew ? self.balanceText : nil))
        precondition(provider.details.first?.rows.first?.id == (isNew ? "credits-left" : nil))
        precondition(provider.details.first?.rows.first?.progress?.total == (isNew ? 5000 : nil))
        precondition(provider.details.first?.rows.first?.usageValue == (isNew ? 3800 : nil))
        #endif
        let roundtrip = try CloudSyncConstants.makeJSONEncoder().encode(envelope)
        let restored = try CloudSyncConstants.makeJSONDecoder().decode(ProviderUsageEnvelope.self, from: roundtrip)
        precondition(restored == envelope)
        print("PASS \(args[3]) \(isNew ? "new" : "old") producer: envelope, balance metadata, details, amount, JSON roundtrip")
    }
}
