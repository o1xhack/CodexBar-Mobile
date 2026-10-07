import CodexBarSync
import Foundation
import SwiftData
import Testing
@testable import CodexBarMobile

@Suite("v0.72 provider presentation")
struct V072ProviderPresentationTests {
    private let observed = Date(timeIntervalSince1970: 1_791_500_000)

    private func cloudCreditsRow(
        value: String = "$7.50 of $10.00 remaining",
        expiry: Date?,
        expiredPrefix: Bool = false,
        progress: SyncProviderDetailSection.Row.Progress? = .init(used: 2.5, total: 10),
        usageValue: Double? = 7.5,
        id: String? = ProviderDetailRowPresentation.claudeCloudCreditsRowID) -> SyncProviderDetailSection.Row
    {
        SyncProviderDetailSection.Row(
            id: id,
            label: "Cloud credits",
            value: value,
            secondaryValue: expiry.map { "\(expiredPrefix ? "Expired" : "Expires") \($0.ISO8601Format())" },
            progress: progress,
            usageValue: usageValue)
    }

    @Test func `Claude cloud credits render remaining of total with a bar before expiry`() {
        let expiry = self.observed.addingTimeInterval(86400)
        let presentation = ProviderDetailRowPresentation(
            providerID: "claude",
            row: self.cloudCreditsRow(expiry: expiry),
            sectionTitle: "Cloud credits",
            now: self.observed,
            locale: Locale(identifier: "en"))
        #expect(presentation.value == "$7.50 of $10.00 remaining")
        #expect(presentation.progressFraction == 0.25)
        #expect(presentation.isExpired == false)
        #expect(presentation.secondaryValue?.hasPrefix("Expires ") == true)
    }

    @Test func `Claude cloud credits become expired once the observed expiry passes`() {
        let expiry = self.observed.addingTimeInterval(60)
        let presentation = ProviderDetailRowPresentation(
            providerID: "claude",
            row: self.cloudCreditsRow(expiry: expiry),
            sectionTitle: "Cloud credits",
            now: expiry.addingTimeInterval(1),
            locale: Locale(identifier: "en"))
        #expect(presentation.value == "Expired")
        #expect(presentation.progressFraction == nil)
        #expect(presentation.isExpired)
        #expect(presentation.secondaryValue?.hasPrefix("Expired ") == true)
    }

    @Test func `Mac reported expired and unavailable cloud credits keep their state`() {
        let expiry = self.observed.addingTimeInterval(-60)
        let expired = ProviderDetailRowPresentation(
            providerID: "claude",
            row: self.cloudCreditsRow(
                value: "Expired", expiry: expiry, expiredPrefix: true, progress: nil, usageValue: nil),
            sectionTitle: "Cloud credits",
            now: self.observed,
            locale: Locale(identifier: "en"))
        #expect(expired.isExpired)
        let unavailable = ProviderDetailRowPresentation(
            providerID: "claude",
            row: self.cloudCreditsRow(value: "Unavailable", expiry: nil, progress: nil, usageValue: nil),
            sectionTitle: "Cloud credits",
            now: self.observed,
            locale: Locale(identifier: "en"))
        #expect(unavailable.value == "Unavailable")
        #expect(unavailable.progressFraction == nil)
        #expect(unavailable.secondaryValue == nil)
    }

    @Test func `Old Mac cloud credit rows without an id stay verbatim`() {
        let row = self.cloudCreditsRow(
            expiry: self.observed.addingTimeInterval(-60),
            progress: nil,
            usageValue: nil,
            id: nil)
        let presentation = ProviderDetailRowPresentation(
            providerID: "claude",
            row: row,
            sectionTitle: "Cloud credits",
            now: self.observed,
            locale: Locale(identifier: "en"))
        #expect(presentation.value == row.value)
        #expect(presentation.secondaryValue == row.secondaryValue)
        #expect(presentation.isExpired == false)
    }

    @Test func `Cloud credits localize in four languages`() {
        let expiry = self.observed.addingTimeInterval(86400)
        for (language, fragment) in [("en", "remaining"), ("zh-Hans", "剩余"), ("zh-Hant", "剩餘"), ("ja", "残り")] {
            let presentation = ProviderDetailRowPresentation(
                providerID: "claude",
                row: self.cloudCreditsRow(expiry: expiry),
                sectionTitle: "Cloud credits",
                now: self.observed,
                locale: Locale(identifier: language))
            #expect(presentation.value.contains(fragment), "\(language): \(presentation.value)")
        }
    }

    @Test func `Generic progress rows draw a clamped bar and other providers ignore the cloud row id`() {
        let over = SyncProviderDetailSection.Row(
            label: "Additional tokens", value: "1.2B tokens left", progress: .init(used: 12, total: 10))
        let presentation = ProviderDetailRowPresentation(
            providerID: "museai", row: over, sectionTitle: nil, now: self.observed, locale: Locale(identifier: "en"))
        #expect(presentation.progressFraction == 1)
        let foreign = self.cloudCreditsRow(expiry: self.observed.addingTimeInterval(-60))
        let plugin = ProviderDetailRowPresentation(
            providerID: "custom-plugin",
            row: foreign,
            sectionTitle: "Cloud credits",
            now: self.observed,
            locale: Locale(identifier: "en"))
        #expect(plugin.value == foreign.value)
        #expect(plugin.isExpired == false)
        #expect(plugin.progressFraction == 0.25)
    }

    @Test func `New provider labels and values localize while unknown text stays verbatim`() {
        let zh = Locale(identifier: "zh-Hans")
        #expect(ProviderDetailLocalization.localized("Payment card", providerID: "lithosai", locale: zh) == "付款卡")
        #expect(ProviderDetailLocalization.localized("Today (UTC)", providerID: "lithosai", locale: zh) == "今天（UTC）")
        #expect(ProviderDetailLocalization.localized("Total", providerID: "workbuddy", locale: zh) == "总计")
        #expect(ProviderDetailLocalization.localizedValue(
            "Added", providerID: "lithosai", rowLabel: "Payment card", locale: zh) == "已添加")
        #expect(ProviderDetailLocalization.localizedValue(
            "On hold", providerID: "lithosai", rowLabel: "Account status", locale: zh) == "已暂停")
        #expect(ProviderDetailLocalization.localizedValue(
            "1,200 / 5,000 credits left", providerID: "workbuddy", locale: zh) == "剩余 1,200 / 5,000 积分")
        #expect(ProviderDetailLocalization.localizedValue(
            "2.8B tokens left", providerID: "museai", locale: zh) == "剩余 2.8B Token")
        #expect(ProviderDetailLocalization.localizedValue(
            "2.8B tokens left", providerID: "muse", locale: zh) == "2.8B tokens left")
        #expect(ProviderDetailLocalization.localized("Total", providerID: "custom-plugin", locale: zh) == "Total")
        #expect(ProviderDetailLocalization.localizedValue(
            "Pro plan, 3 seats", providerID: "workbuddy", locale: zh) == "Pro plan, 3 seats")
    }

    @Test func `LithosAI prepaid credits period localizes`() {
        #expect(ProviderAmountCard.localizedPeriod("Prepaid credits").isEmpty == false)
        #expect(ProviderAmountCard.localizedPeriod("Custom period") == "Custom period")
    }

    @Test @MainActor
    func `v0.72 optional metadata survives disk reopening and multi Mac merge`() throws {
        let base = URL(fileURLWithPath: "/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/upstream-v072")
        guard FileManager.default.fileExists(atPath: base.path),
              FileManager.default.isWritableFile(atPath: base.path),
              base.resolvingSymlinksInPath().path.hasPrefix("/Volumes/StudioSSD/")
        else { throw CocoaError(.fileNoSuchFile) }
        let root = base.appendingPathComponent("v072-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("Store.sqlite")
        func source(device: String, newWriter: Bool, sync: Double) -> SyncedUsageSnapshot {
            let window = SyncRateWindow(
                id: "primary", label: "Monthly", usedPercent: 24, windowMinutes: 43200,
                resetsAt: self.observed.addingTimeInterval(86400), resetDescription: "3,800 / 5,000 credits left",
                balanceDescription: newWriter ? "3,800 / 5,000 credits left" : nil)
            let row = newWriter
                ? SyncProviderDetailSection.Row(
                    id: "credits-left", label: "Credits", value: "3,800",
                    progress: .init(used: 1200, total: 5000), usageValue: 3800)
                : SyncProviderDetailSection.Row(label: "Credits", value: "3,800")
            let provider = ProviderUsageSnapshot(
                providerID: "workbuddy",
                providerName: "Fixture WorkBuddy",
                primary: window,
                secondary: nil,
                accountEmail: nil,
                loginMethod: "Pro",
                statusMessage: nil,
                isError: false,
                lastUpdated: self.observed.addingTimeInterval(sync),
                rateWindows: [window],
                providerAmount: .init(
                    kind: "balance", amount: 42.5, currencyCode: "USD", period: "Prepaid credits", isEstimated: false),
                details: [.init(title: "Credits", rows: [row])])
            return SyncedUsageSnapshot(
                providers: [provider],
                syncTimestamp: self.observed.addingTimeInterval(sync),
                deviceName: device,
                deviceID: device)
        }
        let sources = [
            source(device: "fixture-old", newWriter: false, sync: 0),
            source(device: "fixture-new", newWriter: true, sync: 60),
        ]
        do {
            let opened = ModelContainerFactory.openContainer(at: store)
            #expect(opened.isPersistent)
            try SwiftDataBridge.upsert(deviceSnapshots: sources, into: ModelContext(opened.container))
        }
        let opened = ModelContainerFactory.openContainer(at: store)
        #expect(opened.isPersistent)
        let restored = try SwiftDataBridge.readAllDeviceSnapshots(from: ModelContext(opened.container))
        let newProvider = try #require(restored.first { $0.deviceID == "fixture-new" }?.providers.first)
        #expect(newProvider.primary?.balanceDescription == "3,800 / 5,000 credits left")
        #expect(newProvider.details.first?.rows.first?.progress?.total == 5000)
        #expect(newProvider.details.first?.rows.first?.id == "credits-left")
        let oldProvider = try #require(restored.first { $0.deviceID == "fixture-old" }?.providers.first)
        #expect(oldProvider.primary?.balanceDescription == nil)
        #expect(oldProvider.details.first?.rows.first?.progress == nil)
        for ordered in [restored, Array(restored.reversed())] {
            let merged = try #require(ProviderSnapshotMerger.mergeSnapshots(ordered)?.providers.first)
            // The newer Mac observation wins and keeps its complete metadata.
            #expect(merged.primary?.balanceDescription == "3,800 / 5,000 credits left")
            #expect(merged.details.first?.rows.first?.usageValue == 3800)
            #expect(merged.providerAmount?.amount == 42.5)
        }
    }

    @Test func `Every localized semantic detail label has four translations`() throws {
        var root = URL(fileURLWithPath: #filePath)
        root.deleteLastPathComponent()
        root.deleteLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("CodexBarWidgetShared/ProviderDetailLocalization.swift"),
            encoding: .utf8)
        let start = try #require(source.range(of: "private static let semanticLabels: Set<String> = ["))
        let end = try #require(source.range(of: "\n    ]", range: start.upperBound..<source.endIndex))
        let block = source[start.upperBound..<end.lowerBound]
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        let regex = try NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*)""#)
        let labels = regex.matches(in: block, range: NSRange(block.startIndex..., in: block)).compactMap {
            Range($0.range(at: 1), in: block).map { String(block[$0]) }
        }
        #expect(labels.count > 150)
        let catalog = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: root
                .appendingPathComponent("CodexBarMobile/Localizable.xcstrings"))) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: Any])
        for label in labels {
            let localizations = (strings[label] as? [String: Any])?["localizations"] as? [String: Any]
            for language in ["en", "zh-Hans", "zh-Hant", "ja"] {
                let unit = (localizations?[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                #expect(unit?["state"] as? String == "translated", "\(label) [\(language)]")
            }
        }
    }
}
