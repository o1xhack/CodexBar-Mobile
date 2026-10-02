#!/usr/bin/env python3
"""用当前真实源码执行两项磁盘测试；macOS 证据不替代 iOS runtime gate。"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--scratch", type=Path, required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[4]
volume = plistlib.loads(subprocess.check_output(["diskutil", "info", "-plist", "/Volumes/StudioSSD"]))
if (volume.get("MountPoint") != "/Volumes/StudioSSD"
        or volume.get("VolumeUUID") != "9D5FE511-B66C-4765-BB8F-61E5ACB3969D"
        or not os.path.ismount("/Volumes/StudioSSD")):
    raise SystemExit("StudioSSD validation failed")
root = args.scratch.resolve()
if not root.is_relative_to(Path("/Volumes/StudioSSD/Developer/BuildScratch")):
    raise SystemExit("Scratch must resolve under StudioSSD BuildScratch")
if not repo.is_relative_to(Path("/Volumes/StudioSSD")) or not os.access(repo, os.W_OK):
    raise SystemExit("Repository must be writable on StudioSSD")
root.mkdir(parents=True, exist_ok=False)
(root / "tmp").mkdir()

test_path = "CodexBarMobile/CodexBarMobileTests/V070ConsumerDataTests.swift"
tests = (repo / test_path).read_text()
names = [
    "Pre-v070 disk schema migrates model observations without losing ledger rows",
    "Provider publication authority survives disk reopening with opposing device clocks",
]
methods = []
for index, name in enumerate(names):
    start = tests.index("    func `" + name + "`")
    end = tests.index("\n    @Test", start) if index == 0 else tests.index("\n}\n\n/// Frozen", start)
    method = tests[start:end].replace("func `" + name + "`()", "func run" + str(index) + "()")
    methods.append(method.replace("#expect(", "precondition(").replace("#require(", "require("))
legacy = tests[tests.index("private enum LegacyV230Ledger"):]
harness = (
    "import Foundation\nimport SwiftData\n"
    "func require<T>(_ value: T?) throws -> T { guard let value else { "
    "throw NSError(domain: \"SyntheticMigrationHarness\", code: 1) }; return value }\n"
    "@main @MainActor struct DiskHarness {\n"
    "private let captured = Date(timeIntervalSince1970: 1_791_000_000)\n"
    "static func main() throws { try Self().run0(); try Self().run1(); "
    "print(\"PASS: full legacy schema migration and publication disk reopening\") }\n"
    + "\n".join(methods) + "\n}\n" + legacy
)
(root / "DiskHarness.swift").write_text(harness)
paths = sorted(repo.glob("Shared/Models/*.swift"))
paths += [repo / p for p in [
    "Shared/iCloud/CloudConstants.swift", "Shared/iCloud/AccountIdentityNormalize.swift",
    "Shared/Utilities/EmailRedaction.swift",
    *["CodexBarMobile/CodexBarMobile/Storage/" + name + ".swift" for name in [
        "SwiftDataSchema", "CostLedgerModels", "ModelContainerFactory", "SwiftDataBridge", "CostLedgerService"]],
    *["CodexBarMobile/CodexBarMobile/Models/" + name + ".swift" for name in [
        "MobileDisplayPreferences", "TokenActivity", "ProviderUsageSnapshot+Identity"]],
    "CodexBarMobile/CodexBarWidgetShared/ProviderSnapshotMerger.swift",
]]
manifest = {"platform": "macOS", "testSourceSHA256": hashlib.sha256(tests.encode()).hexdigest(),
            "harnessSHA256": hashlib.sha256(harness.encode()).hexdigest(), "methods": names, "sources": []}
files = []
for path in paths:
    original = path.read_bytes()
    target = root / "sources" / path.relative_to(repo)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(original.decode().replace("import CodexBarSync\n", ""))
    files.append(str(target))
    manifest["sources"].append({"path": str(path.relative_to(repo)),
                                "sha256": hashlib.sha256(original).hexdigest()})
(root / "manifest.json").write_text(json.dumps(manifest, indent=2))
command = ["swiftc", "-swift-version", "6", "-parse-as-library", "-module-name", "CodexBarSync",
           "-module-cache-path", str(root / "module-cache"), *files,
           str(root / "DiskHarness.swift"), "-o", str(root / "disk-harness")]
(root / "compile-command.json").write_text(json.dumps(command, indent=2))
env = dict(os.environ, TMPDIR=str(root / "tmp"))
for command, log_name in [(command, "build.log"), ([str(root / "disk-harness")], "run.log")]:
    with (root / log_name).open("w") as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, env=env)
    print(log_name + ": exit=" + str(result.returncode))
    if result.returncode:
        raise SystemExit(result.returncode)
print((root / "run.log").read_text())
