#!/usr/bin/env python3
"""Bounded, redacted diagnostics for macOS test helper failures."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import sys


TEST_PROCESSES = ("swiftpm-xctest-helper", "swiftpm-testing-helper", "xctest", "CodexBarPackageTests")


def redact(text: str, environment: dict[str, str]) -> str:
    values = set()
    for name, value in environment.items():
        if name in {"CODEXBAR_ALLOW_TEST_KEYCHAIN_ACCESS", "CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS",
                    "CODEXBAR_DISABLE_KEYCHAIN_ACCESS", "CODEXBAR_USE_LOCAL_SWEETCOOKIEKIT",
                    "LD_LIBRARY_PATH", "DYLD_LIBRARY_PATH", "DYLD_FRAMEWORK_PATH", "LIBRARY_PATH", "PKG_CONFIG_PATH"}:
            continue
        if value and re.search(r"token|key|secret|password|passwd|webhook|credential|cookie|private|_pat", name, re.I):
            values.update([value, json.dumps(value)[1:-1], repr(value)[1:-1]])
    for value in sorted(values, key=len, reverse=True):
        text = text.replace(value, "<redacted>")
    # Keep path suffixes useful for dyld diagnostics without publishing local identities.
    return re.sub(r"/Users/[^/\s\"']+", "/Users/<user>", text)


def print_crash_reports(roots: list[Path], since: float,
                        processes: tuple[str, ...] = TEST_PROCESSES) -> int:
    reports = set()
    for root in roots:
        if not root.is_dir():
            continue
        for path in root.iterdir():
            try:
                if (path.suffix in {".ips", ".crash"} and path.stat().st_mtime >= since
                        and any(path.name.startswith(name + "-") for name in processes)):
                    reports.add(path)
            except OSError:
                continue
    count = 0
    for path in sorted(reports, reverse=True)[:5]:
        try:
            report = path.read_text(errors="replace")
        except OSError:
            continue
        print(f"Crash report: {path.name}\n{redact(report, os.environ)}", file=sys.stderr, flush=True)
        count += 1
    return count


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--since", type=Path, required=True, help="test-start timestamp file")
    args = parser.parse_args()
    if not print_crash_reports([Path.home() / "Library/Logs/DiagnosticReports"], args.since.stat().st_mtime):
        print("No fresh test crash reports in ~/Library/Logs/DiagnosticReports.")
