#!/usr/bin/env python3
"""Opt-in macOS direct test launch using the selected SwiftPM toolchain helpers.

SwiftPM remains responsible for building and discovery. Each test group retains a fresh
process, contained descendants, deadline, and an isolated home, including on hosted CI.
"""
from __future__ import annotations

import concurrent.futures
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import threading
import time

from ci_swift_test_by_suite import TestSelection, filter_for, run_command
from swift_test_diagnostics import print_crash_reports, redact


class InventoryMismatch(ValueError):
    """Discovery succeeded, but direct execution cannot prove identical coverage."""


def runtime_environment(developer: Path, home: Path) -> dict[str, str]:
    environment = os.environ.copy()
    platform = developer / "Platforms/MacOSX.platform/Developer"
    for key, directory in [("DYLD_FRAMEWORK_PATH", platform / "Library/Frameworks"),
                           ("DYLD_FRAMEWORK_PATH", platform / "Library/PrivateFrameworks"),
                           ("DYLD_LIBRARY_PATH", platform / "usr/lib")]:
        environment[key] = (environment[key] + ":" if environment.get(key) else "") + str(directory)
    environment["CFFIXED_USER_HOME"] = str(home)
    environment["HOME"] = str(home)
    environment["CODEXBAR_TEST_CODEX_FILE_ISOLATION"] = "1"
    environment["CODEXBAR_TEST_SESSION_FILE_ISOLATION"] = "1"
    environment["CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS"] = "1"
    environment.pop("CODEXBAR_ALLOW_TEST_KEYCHAIN_ACCESS", None)
    environment.pop("CODEXBAR_TEST_CODEX_FILE_FIXTURES", None)
    environment["LANG"] = "en_US.UTF-8"
    environment["LC_ALL"] = "en_US.UTF-8"
    return environment


def checked(command: list[str], environment: dict[str, str], timeout: int = 60) -> str:
    started = time.time()
    result = subprocess.run(command, env=environment, text=True, errors="replace", capture_output=True, timeout=timeout)
    if result.returncode != 0:
        helper = Path(command[0]).name
        reason = f"exit {result.returncode}"
        if result.returncode < 0:
            reason += f", {signal.Signals(-result.returncode).name}"
        print(f"Direct probe {helper}: {reason}", file=sys.stderr, flush=True)
        for label, output in [("stdout", result.stdout), ("stderr", result.stderr)]:
            if output:
                print(f"{label}:\n{redact(output, environment)}", file=sys.stderr, flush=True)
        # ReportCrash can lag the child exit. CI may place reports in either home.
        if result.returncode < 0 and (os.environ.get("CI") or os.environ.get("GITHUB_ACTIONS")):
            roots = [Path.home() / "Library/Logs/DiagnosticReports",
                     Path(environment.get("HOME", str(Path.home()))) / "Library/Logs/DiagnosticReports"]
            for attempt in range(6):
                if print_crash_reports(roots, started, (helper,)):
                    break
                if attempt < 5:
                    time.sleep(1)
            else:
                print("No fresh crash report for the failed probe after 5 seconds.", file=sys.stderr, flush=True)
        raise ValueError(f"Direct runtime capability probe {helper} failed ({reason}).")
    return result.stdout


def xctest_inventory(value: dict) -> list[str]:
    result = []
    for suite in value.get("tests", []):
        for test_case in suite.get("tests", []):
            for method in test_case.get("tests", []):
                result.append(test_case["name"] + "/" + method["name"])
    return result


def selected_tests(inventory: list[str], selections: list[dict]) -> list[str]:
    pattern = re.compile(filter_for([TestSelection(**selection) for selection in selections]))
    return [name for name in inventory if pattern.search(name)]


def prepare_runtime(swift_command: list[str], groups: list[list[dict]], expected: list[str], directory: Path) -> dict:
    if sys.platform != "darwin":
        raise ValueError("Direct test groups require macOS.")
    if len(swift_command) != 1:
        raise ValueError("Direct launch does not support Swift command prefix arguments.")
    developer = Path(checked(["xcode-select", "-p"], os.environ.copy()).strip())
    swift = Path(checked(["xcrun", "--find", "swift"], os.environ.copy()).strip())
    # Build-option wrappers are supported only for the selected compiler/runtime.
    selected_info = json.loads(checked([str(swift), "-print-target-info"], os.environ.copy()))
    command_info = json.loads(checked([*swift_command, "-print-target-info"], os.environ.copy()))
    if command_info != selected_info:
        raise ValueError("Direct launch requires a wrapper using the selected Swift toolchain and target.")
    helper_root = swift.parent.parent / "libexec/swift/pm"
    testing_helper = helper_root / "swiftpm-testing-helper"
    xctest_helper = helper_root / "swiftpm-xctest-helper"
    xctest = Path(checked(["xcrun", "--find", "xctest"], os.environ.copy()).strip())
    frameworks = developer / "Platforms/MacOSX.platform/Developer/Library/Frameworks"
    if not all(path.exists() for path in [testing_helper, xctest_helper, xctest, frameworks]):
        raise ValueError("The selected toolchain lacks the direct macOS test runtime.")
    bin_path = Path(checked([*swift_command, "build", "--show-bin-path"], os.environ.copy()).strip())
    bundles = sorted(bin_path.glob("*.xctest"))
    if not bundles:
        raise ValueError("No prebuilt test bundles found.")
    home = directory / "probe-home"
    home.mkdir()
    environment = runtime_environment(developer, home)
    products = []
    all_names = []
    for index, bundle in enumerate(bundles):
        binary = bundle / "Contents/MacOS" / bundle.stem
        if not binary.is_file():
            raise ValueError("Unsupported test bundle layout.")
        output = directory / f"xctest-{index}.json"
        environment["SWIFT_TESTING_ENABLED"] = "0"
        checked([str(xctest_helper), str(bundle), str(output)], environment)
        xctests = xctest_inventory(json.loads(output.read_text()))
        environment["SWIFT_TESTING_ENABLED"] = "1"
        swift_tests = checked([str(testing_helper), "--test-bundle-path", str(binary),
                               "--list-tests", "--testing-library", "swift-testing"], environment).splitlines()
        all_names.extend(xctests + swift_tests)
        products.append({"bundle": str(bundle), "binary": str(binary), "xctest": xctests, "swift": swift_tests})
    if (len(all_names) != len(set(all_names)) or len(expected) != len(set(expected))
            or set(all_names) != set(expected)):
        raise InventoryMismatch("Direct runtime inventory differs from SwiftPM discovery.")
    for group in groups:
        if not selected_tests(all_names, group):
            raise ValueError("A selected group is absent from direct runtime discovery.")
    return {"developer": str(developer), "testing_helper": str(testing_helper), "xctest": str(xctest),
            "products": products}


def run_worker(manifest: dict, index: int) -> int:
    with tempfile.TemporaryDirectory(prefix=f"codexbar-direct-group-{index}-") as directory:
        environment = runtime_environment(Path(manifest["runtime"]["developer"]), Path(directory))
        os.environ.clear()
        os.environ.update(environment)
        group = manifest["groups"][index]
        timeout = manifest["timeout"]
        commands = []
        runtime = manifest["runtime"]
        for product in runtime["products"]:
            xctests = selected_tests(product["xctest"], group)
            swift_tests = selected_tests(product["swift"], group)
            if xctests:
                commands.append([runtime["xctest"], "-XCTest", ",".join(xctests), product["bundle"]])
            if swift_tests:
                commands.append([runtime["testing_helper"], "--test-bundle-path", product["binary"],
                                 "--filter", filter_for([TestSelection(**selection) for selection in group]),
                                 "--no-parallel", "--testing-library", "swift-testing"])
        if not commands:
            return 2
        started = time.monotonic()
        failure = 0
        # The parent deadline bounds the whole group, including all test products and cleanup.
        for command in commands:
            remaining = timeout - (time.monotonic() - started)
            if remaining <= 0:
                return 124
            os.environ["SWIFT_TESTING_ENABLED"] = "0" if command[0] == runtime["xctest"] else "1"
            result = run_command(command, remaining)
            if result == 124:
                return 124
            if failure == 0:
                failure = result
        return failure


def pool_timeout(groups: list[list[dict]], timeout: int, retry_non_timeout_failures: bool, product_count: int) -> int:
    # Sum the serial worst case even for a parallel pool. Each product may launch both
    # frameworks; allow bounded descendant drain plus fresh worker startup per attempt.
    attempt_budget = timeout + 30 + 10 * max(1, 2 * product_count)
    attempts = 0
    for group in groups:
        attempts += 1
        if len(group) > 1:
            attempts += len(group)
            if retry_non_timeout_failures:
                attempts += 1
    return 30 + attempts * attempt_budget


def run_pool(manifest_path: Path) -> int:
    manifest = json.loads(manifest_path.read_text())
    script = Path(__file__).resolve()
    stopped = threading.Event()
    def launch(index: int) -> dict | None:
        if stopped.is_set():
            return None
        log = manifest_path.parent / f"group-{index}.log"
        with log.open("w") as output:
            result = subprocess.run([sys.executable, str(script), "--worker", str(manifest_path), str(index)],
                                    stdout=output, stderr=subprocess.STDOUT)
        code = result.returncode
        first_code = code
        timed_out = code == 124
        full_retries = 0
        isolated_retries = 0
        if code != 0 and code != 124 and manifest["retry_non_timeout_failures"] and len(manifest["groups"][index]) > 1:
            full_retries += 1
            with log.open("a") as output:
                output.write("Retrying failed group once in a fresh process.\n")
                output.flush()
                code = subprocess.run([sys.executable, str(script), "--worker", str(manifest_path), str(index)],
                                      stdout=output, stderr=subprocess.STDOUT).returncode
            timed_out |= code == 124
        if code == 124 and len(manifest["groups"][index]) > 1:
            for selection in manifest["groups"][index]:
                isolated_retries += 1
                isolated = dict(manifest)
                isolated["groups"] = [[selection]]
                retry_manifest = manifest_path.parent / f"retry-{index}.json"
                retry_manifest.write_text(json.dumps(isolated))
                with log.open("a") as output:
                    code = subprocess.run([sys.executable, str(script), "--worker", str(retry_manifest), "0"],
                                          stdout=output, stderr=subprocess.STDOUT).returncode
                timed_out |= code == 124
                if code != 0:
                    break
        if code != 0:
            stopped.set()
        return {"code": code, "first_code": first_code, "full_retries": full_retries,
                "isolated_retries": isolated_retries, "timed_out": timed_out}
    failure_code = 0
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=manifest["workers"]) as pool:
        futures = {pool.submit(launch, index): index for index in range(len(manifest["groups"]))}
        for future in concurrent.futures.as_completed(futures):
            index = futures[future]
            record = future.result()
            if record is None:
                continue
            results.append(record)
            code = record["code"]
            print(f"::group::Direct Swift test group {index + 1}/{len(futures)}", flush=True)
            print((manifest_path.parent / f"group-{index}.log").read_text(errors="replace"), flush=True)
            print("::endgroup::", flush=True)
            if failure_code == 0 and code != 0:
                failure_code = code
    (manifest_path.parent / "results.json").write_text(json.dumps(results))
    return failure_code


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--worker":
        raise SystemExit(run_worker(json.loads(Path(sys.argv[2]).read_text()), int(sys.argv[3])))
    if len(sys.argv) == 2:
        raise SystemExit(run_pool(Path(sys.argv[1])))
    raise SystemExit(2)
