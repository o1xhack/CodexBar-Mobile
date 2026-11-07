import Foundation

/// Frozen production model/consumer sources execute in separate writer and reader processes.
/// This is offline wire/merge evidence, not CloudKit, SwiftData, APNs or physical-device proof.
@main
struct Harness {
    static let now = Date(timeIntervalSince1970: 1_793_174_400)
    static let additions = ["opendesign"]
    static let ids = ["claude", "perplexity", "workbuddy", "minimax", "plugin:fixture"] + additions

    static func provider(_ id: String, new: Bool, device: String) -> ProviderUsageSnapshot? {
        if self.additions.contains(id), !new { return nil }
        let window: SyncRateWindow
        let progress: SyncProviderDetailSection.Row.Progress?
        #if NEW_WIRE
        window = SyncRateWindow(
            id: "monthly", label: "Monthly", usedPercent: 30,
            windowMinutes: 43200, period: .monthly,
            resetsAt: self.now.addingTimeInterval(86400 * 4), resetDescription: nil,
            quotaLimit: 1000, quotaUnit: "credits")
        progress = .init(used: 30, total: 100, expectedUsed: 25)
        #else
        window = SyncRateWindow(
            id: "monthly", label: "Monthly", usedPercent: 30,
            windowMinutes: 43200, period: .monthly,
            resetsAt: self.now.addingTimeInterval(86400 * 4), resetDescription: nil)
        progress = .init(used: 30, total: 100)
        #endif
        let row: SyncProviderDetailSection.Row
        #if NEW_WIRE
        row = .init(
            label: "Usage", value: "30 / 100", progress: progress, severity: .warning,
            expiresAt: self.now.addingTimeInterval(60))
        #else
        row = .init(label: "Usage", value: "30 / 100", progress: progress, severity: .warning)
        #endif
        #if NEW_WIRE
        let provenance: SyncCostProvenance = device == "mac-a" ? .sourceRecorded : .listPriceEstimate
        #else
        let provenance: SyncCostProvenance = .listPriceEstimate
        #endif
        let cost = SyncCostSummary(
            sessionCostUSD: 0, sessionTokens: nil, last30DaysCostUSD: 0, last30DaysTokens: nil,
            daily: [], costProvenance: provenance)
        return ProviderUsageSnapshot(
            providerID: id, providerName: id, primary: window, secondary: nil,
            accountEmail: nil, loginMethod: nil, statusMessage: nil, isError: false,
            lastUpdated: self.now.addingTimeInterval(device == "mac-b" ? 1 : 0),
            costSummary: cost,
            rateWindows: [window],
            accountIdentities: id == "claude" ? ["claude:email:fixture@example.invalid"] : nil,
            accountRecordKey: self.additions.contains(id) ? "device-" + device : nil,
            details: [.init(title: "Quota", rows: [
                row,
            ])])
    }

    static func envelopes(_ directory: String) throws -> [ProviderUsageEnvelope] {
        try self.ids.compactMap { id in
            let path = URL(fileURLWithPath: directory).appendingPathComponent(id + ".json")
            guard FileManager.default.fileExists(atPath: path.path) else { return nil }
            let data = try Data(contentsOf: path)
            let value = try CloudSyncConstants.makeJSONDecoder().decode(ProviderUsageEnvelope.self, from: data)
            let roundtrip = try CloudSyncConstants.makeJSONEncoder().encode(value)
            let restored = try CloudSyncConstants.makeJSONDecoder().decode(ProviderUsageEnvelope.self, from: roundtrip)
            precondition(restored == value)
            precondition(value.provider.primary?.usedPercent == 30)
            let hasRecorded = String(decoding: data, as: UTF8.self).contains("sourceRecorded")
            precondition(value.provider.costSummary?.last30DaysCostUSD == 0)
            #if NEW_WIRE
            precondition(value.provider.costSummary?
                .costProvenance == (hasRecorded ? .sourceRecorded : .listPriceEstimate))
            #else
            precondition(value.provider.costSummary?.costProvenance == (hasRecorded ? .sourceRecorded : .listPriceEstimate))
            #endif
            precondition(value.provider.details.first?.rows.first?.progress?.used == 30)
            precondition(value.provider.details.first?.rows.first?.severity == .warning)
            if self.additions.contains(id) {
                precondition(value.provider.accountRecordKey == "device-" + value.deviceID)
            }
            #if NEW_WIRE
            let hasMetadata = String(decoding: data, as: UTF8.self).contains("quotaLimit")
            precondition(value.provider.primary?.quotaLimit == (hasMetadata ? 1000 : nil))
            precondition(value.provider.primary?.quotaUnit == (hasMetadata ? "credits" : nil))
            precondition(value.provider.details.first?.rows.first?.progress?.expectedUsed == (hasMetadata ? 25 : nil))
            precondition(value.provider.details.first?.rows.first?
                .expiresAt == (hasMetadata ? self.now.addingTimeInterval(60) : nil))
            #endif
            return value
        }
    }

    static func main() throws {
        let args = CommandLine.arguments
        #if NEW_WIRE
        let new = true
        #else
        let new = false
        #endif
        if args[1] == "write" {
            for id in self.ids {
                guard let provider = provider(id, new: new, device: args[3]) else { continue }
                let value = ProviderUsageEnvelope(
                    deviceID: args[3], deviceName: args[3], appVersion: "fixture", mobileVersion: nil,
                    syncTimestamp: provider.lastUpdated ?? self.now, notificationPushEnabled: false, provider: provider)
                let path = URL(fileURLWithPath: args[2]).appendingPathComponent(id + ".json")
                try CloudSyncConstants.makeJSONEncoder().encode(value).write(to: path)
            }
            return
        }
        let catalog = QuotaProviderList.providers.map(\.id)
        precondition(catalog.count == (new ? 95 : 94))
        precondition(Array(catalog.prefix(90).suffix(2)) == ["futureagi", "munito"])
        precondition(catalog.last == (new ? "opendesign" : "chatbox"))
        precondition(QuotaProviderList
            .quotaZoneName(providerID: "claude", state: "depleted") == "Quota-claude-depletedZone")
        let a = try envelopes(args[2])
        if args[1] == "read" {
            precondition(a.allSatisfy { $0.deviceID == args[3] })
            print("PASS independent reader: quota, units, optional pace, identity and roundtrip")
            return
        }
        let b = try envelopes(args[3])
        for id in self.ids {
            let values = (a + b).filter { $0.provider.providerID == id }
            guard !values.isEmpty else { continue }
            let sources = values.map {
                SyncedUsageSnapshot(
                    providers: [$0.provider], syncTimestamp: $0.syncTimestamp,
                    deviceName: $0.deviceName, deviceID: $0.deviceID)
            }
            for ordering in [sources, Array(sources.reversed())] {
                guard let merged = ProviderSnapshotMerger.mergeSnapshots(ordering) else { fatalError("merge failed") }
                let expected = self.additions.contains(id) ? Set(values.map(\.deviceID)).count : 1
                precondition(merged.providers.count == expected, "\(id): account isolation failed")
                precondition(merged.providers.allSatisfy { $0.primary?.usedPercent == 30 })
                if id == "claude" {
                    precondition(merged.providers.first?.lastUpdated == values.compactMap(\.provider.lastUpdated).max())
                    let provenances = values.compactMap { $0.provider.costSummary?.costProvenance }
                    let expectedProvenance: SyncCostProvenance = provenances.contains(.unknown) ? .unknown
                        : (provenances.contains(.sourceRecorded) ? .sourceRecorded : .listPriceEstimate)
                    precondition(merged.providers.first?.costSummary?.costProvenance == expectedProvenance)
                    precondition(merged.providers.first?.costSummary?.last30DaysCostUSD == 0)
                }
            }
        }
        print("PASS two-writer merge in both orders: stable existing account and isolated new provider accounts")
    }
}
