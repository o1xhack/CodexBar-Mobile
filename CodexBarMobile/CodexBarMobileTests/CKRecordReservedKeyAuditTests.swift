import Foundation
import Testing

@testable import CodexBarMobile

/// Source-level audit that prevents anyone from adding a CKRecord
/// subscript assignment that uses one of CloudKit's reserved field
/// names. These names shadow built-in `CKRecord` properties and
/// raise an Objective-C `NSException` from
/// `-[CKRecordValueStore setObject:forKey:]` when assigned — which
/// Swift can't catch, so the app `abort()`s with `SIGABRT`.
///
/// Hit in production on 2026-05-11 (iOS 1.5.3 build 115):
/// `CloudSyncManager.saveProviderAccountLinkage` set
/// `record["recordID"] = linkage.recordID as CKRecordValue`. User
/// tapped "Same account?" → instant crash. Fixed in build 116 by
/// encoding the UUID into the CKRecord's `recordName` instead.
///
/// The reserved names are documented by Apple at:
/// https://developer.apple.com/documentation/cloudkit/ckrecord
///
/// This test scans the SOURCE FILES that write CKRecord fields and
/// fails if any of the reserved names appear as subscript keys.
/// A unit test that "expects a crash" wouldn't work because ObjC
/// exceptions terminate the test runner; static-source check is the
/// portable equivalent.
@Suite("CKRecord reserved field-name source audit")
struct CKRecordReservedKeyAuditTests {

    /// Names that CKRecord reserves. Setting any of these via subscript
    /// on a CKRecord raises an `NSException`.
    static let reservedNames: [String] = [
        "recordID",
        "recordType",
        "recordChangeTag",
        "modificationDate",
        "creationDate",
        "createdByUserRecordID",
        "modifiedByUserRecordID",
    ]

    /// Source files that perform CKRecord subscript assignments.
    /// Discovered by grepping `record\\["` project-wide. New files that
    /// write CKRecord values must be added here so the audit covers
    /// them — failing to do so isn't a security issue (no data
    /// corruption), but it WILL crash production if a reserved key is
    /// accidentally used.
    static let auditedRelativePaths: [String] = [
        "Shared/iCloud/CloudSyncManager.swift",
        "Sources/CodexBar/Sync/CloudSyncEngine.swift",
    ]

    @Test("No source file writes a CKRecord field using a reserved name")
    func reservedNameAssignmentsAbsent() throws {
        for relativePath in Self.auditedRelativePaths {
            let url = Self.sourceFileURL(forRelative: relativePath)
            let source = try String(contentsOf: url, encoding: .utf8)
            for reserved in Self.reservedNames {
                // Match `record["recordID"] = ...` style only — we don't
                // care about substring-style false positives (e.g. a
                // comment mentioning recordID as a concept). Two quote
                // characters bracket the literal.
                let pattern = "record\\[\"\(reserved)\"\\]\\s*="
                let regex = try NSRegularExpression(pattern: pattern)
                let range = NSRange(source.startIndex..<source.endIndex, in: source)
                let matches = regex.numberOfMatches(in: source, options: [], range: range)
                if matches > 0 {
                    print(
                        "[CKRecordReservedKeyAudit] FOUND CKRecord reserved-name assignment in \(relativePath): " +
                        "`record[\"\(reserved)\"] = ...` raises an ObjC NSException at runtime. " +
                        "Use a non-reserved field name, or encode the value in the CKRecord's `recordName` instead. " +
                        "See feedback_ckrecord_reserved_field_names.md.")
                }
                #expect(matches == 0)
            }
        }
    }

    @Test("All known CKRecord-writing files are listed in the audit")
    func auditCoverageCompletes() throws {
        // Grep the project root for all `record["..."] = ...` WRITE sites
        // (not reads) and assert that every file containing such writes is
        // listed in `auditedRelativePaths`. If a new file starts writing
        // CKRecord fields and isn't added here, the test fails — forcing
        // the developer to add it (or explain why this audit doesn't
        // apply).
        let projectRoot = Self.projectRoot()
        let auditedAbsolute = Set(Self.auditedRelativePaths.map {
            Self.sourceFileURL(forRelative: $0).resolvingSymlinksInPath().path
        })

        // `record["foo"] = ...` style only. Reads (`record["foo"] as? T`)
        // are safe regardless of field name and don't need coverage.
        let writePattern = try NSRegularExpression(
            pattern: "record\\[\"[^\"]+\"\\]\\s*=")

        var foundFiles = Set<String>()
        let enumerator = FileManager.default.enumerator(
            at: projectRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles])
        while let url = enumerator?.nextObject() as? URL {
            // Skip non-Swift files, test files (they're allowed to
            // exercise CKRecord directly), and the .build directory.
            let pathLower = url.path.lowercased()
            guard url.pathExtension == "swift" else { continue }
            guard !pathLower.contains("/tests/"),
                  !pathLower.contains("/.build/"),
                  !pathLower.contains("/codexbarmobiletests/"),
                  !pathLower.contains("/codexbarmobileuitests/")
            else { continue }
            guard let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            if writePattern.numberOfMatches(in: source, options: [], range: range) > 0 {
                foundFiles.insert(url.resolvingSymlinksInPath().path)
            }
        }

        let missing = foundFiles.subtracting(auditedAbsolute)
        // Build the diagnostic eagerly so the failure message lists the
        // offending files. Swift Testing's `#expect` Comment param only
        // accepts compile-time-known string literals, hence the
        // print-then-assert split.
        if !missing.isEmpty {
            print(
                "[CKRecordReservedKeyAudit] These source files write CKRecord fields but are NOT in `auditedRelativePaths`. " +
                "Add them to the audit so reserved-name violations are caught:\n" +
                missing.sorted().joined(separator: "\n"))
        }
        #expect(missing.isEmpty)
    }

    // MARK: - Helpers

    /// Resolve a path relative to the project root.
    static func sourceFileURL(forRelative path: String) -> URL {
        Self.projectRoot().appendingPathComponent(path)
    }

    /// Walks up from this test file's location to the project root
    /// (the parent of `CodexBarMobile/`). Test bundles run inside
    /// `Build/Products/...`, so we use `#filePath` to anchor on the
    /// source tree instead.
    static func projectRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        // `#filePath` =
        // .../CodexBar/CodexBarMobile/CodexBarMobileTests/CKRecordReservedKeyAuditTests.swift
        // Walk up 3 dirs to land at `.../CodexBar/`.
        url.deleteLastPathComponent()  // remove file
        url.deleteLastPathComponent()  // remove CodexBarMobileTests
        url.deleteLastPathComponent()  // remove CodexBarMobile
        return url
    }
}
