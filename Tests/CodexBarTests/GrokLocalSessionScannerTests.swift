import Foundation
import Testing
@testable import CodexBarCore

struct GrokLocalSessionScannerTests {
    @Test
    func `day keys remain Gregorian under a Buddhist calendar`() throws {
        var calendar = Calendar(identifier: .buddhist)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Bangkok"))
        let date = try #require(ISO8601DateFormatter().date(from: "2026-08-22T12:00:00Z"))

        #expect(GrokLocalSessionScanner.dayKey(for: date, calendar: calendar) == "2026-08-22")
    }

    @Test
    func `daily buckets stay local and never invent dollars`() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok-session-scan-\(UUID().uuidString)", isDirectory: true)
        let cwd = root.appendingPathComponent("sessions/%2Ftmp%2Fdemo", isDirectory: true)
        let first = cwd.appendingPathComponent("session-a", isDirectory: true)
        let second = cwd.appendingPathComponent("session-b", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        let calendar = Calendar.current
        let newer = Date(timeIntervalSince1970: 1_787_079_600)
        let older = try #require(calendar.date(byAdding: .day, value: -1, to: newer))
        try self.writeSignals(
            at: first.appendingPathComponent("signals.json"),
            tokens: 100,
            model: "grok-4.6",
            date: older)
        try self.writeSignals(
            at: second.appendingPathComponent("signals.json"),
            tokens: 250,
            model: "grok-4.6",
            date: newer)

        let summary = GrokLocalSessionScanner.summarize(
            env: ["GROK_HOME": root.path],
            lookbackDays: 7,
            now: newer)
        #expect(summary.sessionCount == 2)
        #expect(summary.totalTokens == 350)
        #expect(summary.daily.map(\.totalTokens) == [100, 250])
        #expect(summary.daily.map(\.sessionCount) == [1, 1])
        #expect(Set(summary.daily.map(\.date)).count == 2)

        let snapshot = try #require(summary.toCostUsageTokenSnapshot(historyDays: 7))
        #expect(snapshot.last30DaysTokens == 350)
        #expect(snapshot.last30DaysCostUSD == nil)
        #expect(snapshot.daily.allSatisfy { $0.costUSD == nil })
        #expect(snapshot.costProvenance == .unknown)
        #expect(snapshot.sessionTokens == 250)
    }

    @Test
    func `idle days do not reuse yesterday as today`() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok-session-idle-\(UUID().uuidString)", isDirectory: true)
        let session = root.appendingPathComponent("sessions/%2Ftmp%2Fdemo/session-a", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let calendar = Calendar.current
        let yesterday = Date(timeIntervalSince1970: 1_787_079_600)
        let today = try #require(calendar.date(byAdding: .day, value: 1, to: yesterday))
        try self.writeSignals(
            at: session.appendingPathComponent("signals.json"),
            tokens: 100,
            model: "grok-4.6",
            date: yesterday)
        let summary = GrokLocalSessionScanner.summarize(
            env: ["GROK_HOME": root.path],
            lookbackDays: 7,
            now: today)
        let snapshot = try #require(summary.toCostUsageTokenSnapshot(historyDays: 7))
        #expect(snapshot.last30DaysTokens == 100)
        #expect(snapshot.sessionTokens == nil)
    }

    @Test
    func `thirty day scan includes exactly thirty local calendar days`() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok-session-window-\(UUID().uuidString)", isDirectory: true)
        let included = root.appendingPathComponent("sessions/%2Ftmp%2Fdemo/included", isDirectory: true)
        let excluded = root.appendingPathComponent("sessions/%2Ftmp%2Fdemo/excluded", isDirectory: true)
        try FileManager.default.createDirectory(at: included, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: excluded, withIntermediateDirectories: true)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = try #require(ISO8601DateFormatter().date(from: "2026-08-22T22:00:00Z"))
        let startOfToday = calendar.startOfDay(for: now)
        let oldestIncludedDay = try #require(calendar.date(byAdding: .day, value: -29, to: startOfToday))
        let oldRollingCutoff = try #require(calendar.date(byAdding: .day, value: -30, to: now))
        let previousDayAfterOldCutoff = try #require(calendar.date(
            byAdding: .hour,
            value: 1,
            to: oldRollingCutoff))
        try self.writeSignals(
            at: included.appendingPathComponent("signals.json"),
            tokens: 100,
            model: "grok-4.6",
            date: oldestIncludedDay)
        try self.writeSignals(
            at: excluded.appendingPathComponent("signals.json"),
            tokens: 900,
            model: "grok-4.6",
            date: previousDayAfterOldCutoff)

        let summary = GrokLocalSessionScanner.summarize(
            env: ["GROK_HOME": root.path],
            lookbackDays: 30,
            now: now)

        #expect(summary.sessionCount == 1)
        #expect(summary.totalTokens == 100)
        #expect(try summary.daily.map(\.date) == [
            #require(GrokLocalSessionScanner.dayKey(for: oldestIncludedDay, calendar: calendar)),
        ])
    }

    @Test
    func `empty homes do not publish a spend snapshot`() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok-session-empty-\(UUID().uuidString)", isDirectory: true)
        let summary = GrokLocalSessionScanner.summarize(
            env: ["GROK_HOME": root.path],
            lookbackDays: 7,
            now: Date())
        #expect(summary.toCostUsageTokenSnapshot(historyDays: 7) == nil)
    }

    @Test
    func `local scan clock wins over a stale remote snapshot`() throws {
        let calendar = Calendar.current
        let staleRemoteTime = Date(timeIntervalSince1970: 1_787_079_600)
        let localScanTime = try #require(calendar.date(byAdding: .day, value: 1, to: staleRemoteTime))
        let localDay = try #require(GrokLocalSessionScanner.dayKey(for: localScanTime, calendar: calendar))
        let summary = GrokLocalSessionSummary(
            sessionCount: 1,
            totalTokens: 250,
            lastSessionAt: localScanTime,
            primaryModel: "grok-4.6",
            models: ["grok-4.6"],
            daily: [GrokLocalDailyBucket(
                date: localDay,
                totalTokens: 250,
                sessionCount: 1,
                models: ["grok-4.6"])],
            scannedAt: localScanTime)
        let remote = GrokUsageSnapshot(
            billing: nil,
            credentials: nil,
            localSummary: summary,
            cliVersion: nil,
            updatedAt: staleRemoteTime)

        let snapshot = try #require(remote.toUsageSnapshot().costUsage)
        #expect(snapshot.sessionTokens == 250)
        #expect(snapshot.updatedAt == localScanTime)
    }

    @Test
    func `projection preserves the timezone that produced existing day buckets`() throws {
        let capturedTimeZone = try #require(TimeZone(identifier: "Pacific/Kiritimati"))
        var capturedCalendar = Calendar(identifier: .gregorian)
        capturedCalendar.timeZone = capturedTimeZone
        let scannedAt = try #require(ISO8601DateFormatter().date(from: "2026-08-22T12:30:00Z"))
        let capturedDay = try #require(GrokLocalSessionScanner.dayKey(
            for: scannedAt,
            calendar: capturedCalendar))
        let summary = GrokLocalSessionSummary(
            sessionCount: 1,
            totalTokens: 250,
            lastSessionAt: scannedAt,
            primaryModel: "grok-4.6",
            models: ["grok-4.6"],
            daily: [GrokLocalDailyBucket(
                date: capturedDay,
                totalTokens: 250,
                sessionCount: 1,
                models: ["grok-4.6"])],
            bucketTimeZoneIdentifier: capturedTimeZone.identifier,
            scannedAt: scannedAt)

        let snapshot = try #require(summary.toCostUsageTokenSnapshot(historyDays: 7))
        #expect(snapshot.sessionTokens == 250)
        #expect(snapshot.bucketTimeZoneIdentifier == capturedTimeZone.identifier)
        #expect(snapshot.daily.first?.date == capturedDay)
    }

    private func writeSignals(at url: URL, tokens: Int, model: String, date: Date) throws {
        let payload: [String: Any] = [
            "contextTokensUsed": tokens,
            "totalTokensBeforeCompaction": 0,
            "primaryModelId": model,
            "modelsUsed": [model],
        ]
        try JSONSerialization.data(withJSONObject: payload).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }
}
