import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct CostUsageStoreWriteAmplificationTests {
    @Test(arguments: [2, 16], [false, true])
    func `refresh writes do not scale with unchanged retained files`(fileCount: Int, metadataOnly: Bool) async throws {
        let fixture = try ReadWorkFixture(fileCount: fileCount, rowsPerFile: 4)
        defer { fixture.remove() }
        var expected = fixture.canonical
        let changedPath = try #require(expected.files.keys.min())

        for cycle in 1...3 {
            let loaded = fixture.store.syncLoadCodexScan(calendar: fixture.calendar)
            defer { loaded.release() }
            var candidate = loaded.cache
            candidate.lastScanUnixMs += 1000
            expected.lastScanUnixMs = candidate.lastScanUnixMs
            if metadataOnly {
                candidate.codexProjectMetadataVersion = cycle + 100
                expected.codexProjectMetadataVersion = candidate.codexProjectMetadataVersion
            } else {
                candidate.files[changedPath]?.lastModel = "fixture-model-\(cycle)"
                expected.files[changedPath]?.lastModel = "fixture-model-\(cycle)"
            }
            let before = await fixture.store.persistenceWriteMetricsForTesting()
            let result = fixture.save(candidate, load: loaded)
            let after = await fixture.store.persistenceWriteMetricsForTesting()
            let writes = after.rows - before.rows
            #expect(!result.catchUpRequired)
            #expect(writes <= (metadataOnly ? 4 : 9))
            #expect(fixture.store.syncLoadCodexCache(calendar: fixture.calendar) == expected)
            print("[cost-write-amplification] files=\(fileCount) metadata_only=\(metadataOnly) " +
                "cycle=\(cycle) rows=\(writes) pages=\(after.pages - before.pages)")
        }
    }
}
