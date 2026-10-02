#!/usr/bin/env python3
"""本轮冻结Shared源码的序列化兼容验证；不是完整设备矩阵。"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--old-ref", required=True)
parser.add_argument("--scratch", type=Path, required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[4]
volume = plistlib.loads(subprocess.check_output(["diskutil", "info", "-plist", "/Volumes/StudioSSD"]))
if (volume.get("MountPoint") != "/Volumes/StudioSSD"
        or not os.path.ismount("/Volumes/StudioSSD")
        or volume.get("VolumeUUID") != "9D5FE511-B66C-4765-BB8F-61E5ACB3969D"):
    raise SystemExit("StudioSSD mount or UUID validation failed")
if not repo.is_relative_to(Path("/Volumes/StudioSSD")) or not os.access(repo, os.W_OK):
    raise SystemExit("Repository must be writable on StudioSSD")
root = args.scratch.resolve()
if not root.is_relative_to(Path("/Volumes/StudioSSD/Developer/BuildScratch")):
    raise SystemExit("Scratch path must resolve under StudioSSD BuildScratch")
root.mkdir(parents=True, exist_ok=True)
if not os.access(root, os.W_OK):
    raise SystemExit("Scratch path must be writable")
(root / "tmp").mkdir(exist_ok=True)
(root / "module-cache").mkdir(exist_ok=True)
env = dict(os.environ, TMPDIR=str(root / "tmp"))


def git(*items):
    return subprocess.check_output(["git", *items], cwd=repo)


paths = git("ls-tree", "-r", "--name-only", args.old_ref, "Shared").decode().splitlines()
paths = [p for p in paths if p.endswith(".swift") and (
    p.startswith("Shared/Models/") or p in [
        "Shared/iCloud/CloudConstants.swift", "Shared/iCloud/AccountIdentityNormalize.swift",
        "Shared/Utilities/EmailRedaction.swift"])]
paths.append("CodexBarMobile/CodexBarWidgetShared/ProviderSnapshotMerger.swift")
manifest = {
    "oldRef": args.old_ref,
    "oldCommit": git("rev-parse", args.old_ref + "^{commit}").decode().strip(),
    "newCommit": git("rev-parse", "HEAD").decode().strip(),
    "files": [],
}
for path in paths:
    old = git("show", args.old_ref + ":" + path)
    new = (repo / path).read_bytes()
    for kind, data in [("old", old), ("new", new)]:
        output = root / kind / path
        output.parent.mkdir(parents=True, exist_ok=True)
        # Compile model and consumer sources in one synthetic module. Removing
        # the self-import changes module wiring only, not merge implementation.
        compiled_data = data.replace(b"import CodexBarSync\n", b"")
        output.write_bytes(compiled_data)
    manifest["files"].append({
        "path": path, "oldSHA256": hashlib.sha256(old).hexdigest(),
        "newSHA256": hashlib.sha256(new).hexdigest()})
(root / "source-manifest.json").write_text(json.dumps(manifest, indent=2))
harness = Path(__file__).with_name("FrozenWireHarness.swift")
manifest["harnessSHA256"] = hashlib.sha256(harness.read_bytes()).hexdigest()
(root / "source-manifest.json").write_text(json.dumps(manifest, indent=2))
for kind in ["old", "new"]:
    files = [str(root / kind / path) for path in paths]
    command = ["swiftc", "-swift-version", "6", "-parse-as-library", "-module-name", "CodexBarSync",
               "-module-cache-path", str(root / "module-cache")]
    if kind == "new":
        command += ["-D", "NEW_WIRE"]
    command += files + [str(harness), "-o", str(root / (kind + "-wire"))]
    result = subprocess.run(command, capture_output=True, text=True, env=env)
    (root / (kind + "-build.log")).write_text(result.stdout + result.stderr)
    if result.returncode:
        raise SystemExit(f"{kind} compile failed; see {root / (kind + '-build.log')}")
    for device in ["mac-a", "mac-b"]:
        subprocess.run([str(root / (kind + "-wire")), "write",
                        str(root / (kind + "-" + device + ".json")), device], check=True, env=env)

cases = []
lines = []
for mask in range(16):
    versions = ["new" if mask & (1 << bit) else "old" for bit in [3, 2, 1, 0]]
    operations = []
    for phone, reader in zip(["phone-a", "phone-b"], versions[2:]):
        for device, writer in zip(["mac-a", "mac-b"], versions[:2]):
            command = [str(root / (reader + "-wire")), "read",
                       str(root / (writer + "-" + device + ".json")), device]
            result = subprocess.run(command, capture_output=True, text=True, env=env)
            lines.append(f"mask={mask} {phone} {reader}-reader <- {writer}-{device}: "
                         f"exit={result.returncode}\n{result.stdout}{result.stderr}")
            operations.append({"phone": phone, "reader": reader, "device": device,
                               "writer": writer, "exitCode": result.returncode})
            if result.returncode:
                (root / "matrix-wire.log").write_text("\n".join(lines))
                raise SystemExit(result.returncode)
        command = [str(root / (reader + "-wire")), "merge",
                   str(root / (versions[0] + "-mac-a.json")),
                   str(root / (versions[1] + "-mac-b.json"))]
        result = subprocess.run(command, capture_output=True, text=True, env=env)
        lines.append(f"mask={mask} {phone} {reader}-reader two-writer merge: "
                     f"exit={result.returncode}\n{result.stdout}{result.stderr}")
        operations.append({"phone": phone, "reader": reader, "operation": "two-writer-merge",
                           "exitCode": result.returncode})
        if result.returncode:
            (root / "matrix-wire.log").write_text("\n".join(lines))
            raise SystemExit(result.returncode)
    cases.append({"case": mask + 1, "mask": mask, "versions": versions,
                  "stage": "frozen-shared-wire-and-consumer-merge", "readOperations": operations, "result": "pass"})
(root / "matrix-wire.log").write_text("\n".join(lines))
(root / "matrix-wire.json").write_text(json.dumps({
    "scope": "serialization and real old/new pure consumer merge; no SwiftData, UI, CloudKit, APNs or physical device evidence",
    "cases": cases}, indent=2))
print("PASS: 16 masks, 64 wire reads and 32 real old/new consumer merge processes")
