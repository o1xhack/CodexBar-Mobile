"""Build an isolated, non-shipping full-settings proof bundle; restore app sources on exit."""
from pathlib import Path
import hashlib
import json
import plistlib
import shutil
import subprocess
import sys

root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd()
artifacts = Path(__file__).resolve().parent
output = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else root / ".build/spend-dashboard-app-proof"
output.mkdir(parents=True, exist_ok=True)
entry = root / "Sources/CodexBar/CodexbarApp.swift"
helper = root / "Sources/CodexBar/SpendDashboardAppProof.swift"
original = entry.read_bytes()
assert not helper.exists(), "Do not overwrite existing work"
try:
    shutil.copyfile(artifacts / helper.name, helper)
    anchor = "        #if DEBUG\n        if MenuBarLayoutNativeProof.runIfRequested() {"
    assert anchor in original.decode()
    entry.write_text(original.decode().replace(
        anchor, "        #if DEBUG\n        if SpendDashboardAppProof.runIfRequested() { return }\n"
        "        if MenuBarLayoutNativeProof.runIfRequested() {", 1))
    subprocess.run(["swift", "build", "--product", "CodexBar"], cwd=root, check=True)
    binary_dir = root / ".build/debug"
    bundle = output / "SpendDashboardAppProof.app"
    executable = bundle / "Contents/MacOS/SpendDashboardAppProof"
    executable.parent.mkdir(parents=True, exist_ok=True)
    resources = bundle / "Contents/Resources"
    resources.mkdir(parents=True, exist_ok=True)
    frameworks = bundle / "Contents/Frameworks"
    frameworks.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(binary_dir / "CodexBar", executable)
    executable.chmod(0o755)
    for resource in binary_dir.glob("*.bundle"):
        subprocess.run(["ditto", str(resource), str(resources / resource.name)], check=True)
    sparkle = next((root / ".build/artifacts").rglob("Sparkle.framework"))
    subprocess.run(["ditto", str(sparkle), str(frameworks / "Sparkle.framework")], check=True)
    with (bundle / "Contents/Info.plist").open("wb") as file:
        plistlib.dump({
            "CFBundleName": "CodexBar Synthetic Proof",
            "CFBundleDisplayName": "CodexBar Synthetic Proof",
            "CFBundleIdentifier": "local.codexbar.spend-dashboard-app-proof",
            "CFBundleExecutable": executable.name,
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1",
            "CFBundleShortVersionString": "1.0",
            "NSHighResolutionCapable": True,
        }, file)
    subprocess.run(["install_name_tool", "-add_rpath", "@executable_path/../Frameworks", str(executable)], check=True)
    subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(bundle)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(bundle)], check=True)
    receipt = {
        "kind": "non-shipping full production settings UI with synthetic loader",
        "base_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
        "executable_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
        "fixture_source_sha256": hashlib.sha256(helper.read_bytes()).hexdigest(),
        "launch_argument": "--spend-dashboard-app-proof",
        "route": ["SettingsWindowController", "PreferencesView", "Usage & Spend sidebar", "SpendDashboardPane",
                  "UsageStore.sharedSpendDashboardController", "SpendDashboardTrendPanel"],
        "providers": "synthetic Codex A, Codex B, Cursor, Antigravity",
        "live_provider_requests": False,
        "real_accounts_or_history": False,
        "production_entrypoint_instrumentation": "Temporary DEBUG guard; normal provider startup bypassed",
        "production_source_sha256": {
            path: hashlib.sha256((root / path).read_bytes()).hexdigest()
            for path in ["Sources/CodexBar/SpendDashboardTrendPanel.swift",
                         "Sources/CodexBar/SpendDashboardProviderBreakdown.swift",
                         "Sources/CodexBar/ProviderBrandIcon.swift",
                         "Sources/CodexBar/SpendTrendChartModel.swift",
                         "Tests/CodexBarTests/SpendTrendChartTests.swift"]
        },
    }
    (output / "build-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
finally:
    entry.write_bytes(original)
    helper.unlink(missing_ok=True)
