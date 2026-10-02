import Foundation
import SwiftData

@main @MainActor
struct FrozenCacheHarness {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count >= 5 else { fatalError("phase, store, writer A, writer B required") }
        print("OS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        let phase = args[1]
        let store = URL(fileURLWithPath: args[2])
        precondition(store.resolvingSymlinksInPath().path.hasPrefix(
            "/Volumes/StudioSSD/Developer/BuildScratch/"))
        let envelopes = try args[3...4].map {
            try CloudSyncConstants.makeJSONDecoder().decode(
                ProviderUsageEnvelope.self, from: Data(contentsOf: URL(fileURLWithPath: $0)))
        }
        precondition(envelopes.map(\.deviceID) == ["mac-a", "mac-b"])
        let sources = envelopes.map { envelope in
            let tokens = ProviderUsageSnapshot(
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
                providers: [envelope.provider, tokens],
                syncTimestamp: envelope.syncTimestamp,
                deviceName: envelope.deviceName,
                deviceID: envelope.deviceID)
        }
        let opened = ModelContainerFactory.openContainer(at: store)
        precondition(opened.isPersistent, "Never substitute in-memory storage for a disk test")
        let context = ModelContext(opened.container)
        if phase == "write" {
            try SwiftDataBridge.upsert(deviceSnapshots: sources, into: context)
            print("PASS write: independent device/provider cache persisted")
            return
        }
        let expectedSources = phase == "read-retained" ? [sources[0]] : sources
        let restored = try SwiftDataBridge.readAllDeviceSnapshots(from: context)
        precondition(Set(restored.compactMap(\.deviceID)) == Set(expectedSources.compactMap(\.deviceID)))
        precondition(restored.count == expectedSources.count)
        for source in expectedSources {
            let disk = restored.first { $0.deviceID == source.deviceID }!
            precondition(disk.deviceName == source.deviceName)
            precondition(disk.providers.count == 2)
            for provider in source.providers {
                let cached = disk.providers.first { $0.providerID == provider.providerID }!
                precondition(cached.primary == provider.primary)
                precondition(cached.rateWindows == provider.rateWindows)
                precondition(cached.lastUpdated == provider.lastUpdated)
                precondition(cached.costSummary == provider.costSummary)
            }
        }
        let live = ProviderSnapshotMerger.mergeSnapshots(expectedSources)!
        for order in [restored, Array(restored.reversed())] {
            let cold = ProviderSnapshotMerger.mergeSnapshots(order)!
            precondition(cold.providers == live.providers, "Cold/live visible provider projection must agree")
            let kimi = cold.providers.first { $0.providerID == "kimi" }!
            let codex = cold.providers.first { $0.providerID == "codex" }!
            precondition(cold.providers.count == 2)
            precondition(kimi.costSummary?.daily.first?.totalTokens == 12)
            precondition(kimi.costSummary?.daily.first?.costIsKnown == false)
            precondition(codex.costSummary?.daily.first?.totalTokens == expectedSources.count * 12)
            precondition(codex.costSummary?.daily.first?.costIsKnown == false)
            let winnerIndex = expectedSources.count - 1
            let winnerIsNew = URL(fileURLWithPath: args[3 + winnerIndex]).lastPathComponent.hasPrefix("new-")
            let capture = Date(timeIntervalSince1970: 1_790_913_600)
            precondition(kimi.primary?.usedPercent == (winnerIsNew ? 100 : 25))
            precondition(kimi.primary?.resetsAt == capture.addingTimeInterval(86400 * (winnerIsNew ? 20 : 1)))
            #if NEW_CACHE
            precondition(kimi.primary?.blockingQuota?.windowID == (winnerIsNew ? "kimi-monthly" : nil))
            precondition(kimi.primary?.blockingQuota?.rawUsedPercent == (winnerIsNew ? 25 : nil))
            precondition(kimi.primary?.blockingQuota?.rawResetsAt ==
                (winnerIsNew ? capture.addingTimeInterval(86400) : nil))
            let anyNew = (0..<expectedSources.count).contains {
                URL(fileURLWithPath: args[3 + $0]).lastPathComponent.hasPrefix("new-")
            }
            precondition(codex.costSummary?.daily.first?.modelsUsed ==
                (anyNew ? ["Observed Fictitious Model"] : nil))
            #endif
        }
        if phase == "read-prune" {
            try SwiftDataBridge.upsert(deviceSnapshots: [sources[0]], into: context)
            let devices = try context.fetch(FetchDescriptor<DeviceRecord>())
            let providers = try context.fetch(FetchDescriptor<ProviderSnapshotModel>())
            precondition(devices.count == 1)
            precondition(providers.count == 2)
            print("PASS cold read + merge: original old/new cache; removed writer pruned")
        } else {
            precondition(phase == "read-retained")
            print("PASS reopened after prune: removed writer does not reappear")
        }
    }
}
