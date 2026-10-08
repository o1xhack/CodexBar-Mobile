#!/usr/bin/env python3
"""Synthetic CLI/HTTP dashboard regression; requires a local debug CodexBarCLI build."""

import json
import pathlib
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request


def account_data(result):
    # Pace is derived at collection time; compare the persisted account data.
    return [
        {key: value for key, value in account.items() if key != "pace"}
        for account in result["providers"][0].get("accounts", [])
    ]


def verify(binary, root):
    app = root / "Library/Application Support/CodexBar"
    app.mkdir(parents=True)
    first = "9e122a52-b3db-4a7e-a7a7-c3b8fc9d01e9"
    second = "a1c82a14-9250-4a32-b9f6-1de9b69f865a"
    accounts = [
        dict(id=account_id, email=email, workspaceAccountID=workspace, workspaceLabel=label,
             managedHomePath=str(root / account_id), createdAt=1000, updatedAt=1000)
        for account_id, email, workspace, label in [
            (first, "owner@example.com", "workspace-first", "Work"),
            (second, "other@example.net", "workspace-second", "Personal"),
        ]
    ]
    (app / "managed-codex-accounts.json").write_text(json.dumps(dict(version=3, accounts=accounts)))
    # Swift JSONEncoder's default Date encoding uses seconds since 2001-01-01.
    timestamp = int(time.time()) - 978307200
    snapshot = dict(
        primary=dict(usedPercent=40, windowMinutes=300, resetsAt=timestamp + 3600),
        updatedAt=timestamp,
        identity=dict(providerID="codex", accountEmail="owner@example.com", loginMethod="plus"),
    )
    records = [dict(
        id="owner@example.com",
        accountIdentity=dict(normalizedEmail="owner@example.com",
                             workspaceAccountID="workspace-first", storedAccountID=first),
        snapshot=snapshot,
    )]
    (app / "codex-account-snapshots.json").write_text(json.dumps(dict(version=1, records=records)))
    config = root / "config.json"
    config.write_text(json.dumps(dict(version=1, providers=[dict(id="codex", enabled=True, source="oauth")])))
    environment = {
        "HOME": str(root),
        "CFFIXED_USER_HOME": str(root),
        "CODEX_HOME": str(root / ".codex"),
        "CODEXBAR_CONFIG": str(config),
        "PATH": "/usr/bin:/bin",
        "CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS": "1",
        "CODEXBAR_DISABLE_KEYCHAIN_ACCESS": "1",
        "CODEXBAR_TEST_CODEX_FILE_ISOLATION": "1",
        "CODEXBAR_TEST_SESSION_FILE_ISOLATION": "1",
        "CODEXBAR_TEST_CODEX_FILE_FIXTURES": json.dumps({"grants": [
            {"url": root.as_uri(), "resolvedURL": root.as_uri(), "isRoot": True},
        ]}),
    }
    command = subprocess.run(
        [binary, "dashboard", "--identity", "redacted", "--timeout", "60"],
        env=environment, capture_output=True, timeout=90,
    )
    assert command.returncode == 0, "dashboard command failed (diagnostics withheld)"
    cli = json.loads(command.stdout)
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    server = subprocess.Popen(
        [binary, "serve", "--port", str(port), "--identity", "redacted",
         "--dashboard-token", "synthetic-test-token", "--request-timeout", "60"],
        env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
    )
    try:
        line = server.stderr.readline()
        assert b"listening" in line, "serve did not announce readiness (diagnostics withheld)"
        request = urllib.request.Request(
            f"http://127.0.0.1:{port}/dashboard/v1/snapshot",
            headers={"Authorization": "Bearer synthetic-test-token"},
        )
        with urllib.request.urlopen(request, timeout=90) as response:
            assert response.status == 200
            assert response.headers["Cache-Control"] == "no-store"
            http = json.load(response)
    finally:
        server.terminate()
        try:
            server.wait(timeout=30)
        except subprocess.TimeoutExpired:
            server.kill()
            server.wait()
    failures = 0
    for name, result in [("CLI JSON", cli), ("HTTP endpoint", http)]:
        row = next(provider for provider in result["providers"] if provider["id"] == "codex")
        rows = row.get("accounts")
        if not rows:
            print(f"FAIL {name}: managed Codex accounts absent")
            failures += 1
            continue
        assert result["schemaVersion"] == 1
        assert [account["id"] for account in rows] == ["codex-managed:" + first, "codex-managed:" + second]
        assert rows[0]["identity"] == {"accountEmail": "redacted@example.com", "plan": "Plus"}
        assert rows[0]["label"] == "redacted@example.com — Work"
        assert rows[0]["windows"][0]["usedPercent"] == 40
        assert rows[0]["pace"]["primary"] is not None
        assert rows[0]["updatedAt"] is not None
        assert rows[0]["error"] is None
        assert rows[1]["windows"] == [] and rows[1]["error"] is not None
        assert not any(account["active"] for account in rows)
        assert "owner@" not in json.dumps(rows) and "other@" not in json.dumps(rows)
        assert str(root) not in json.dumps(rows)
        print(f"PASS {name}: schema-v1, 2 stable accounts, scoped usage, redaction, independent error")
    assert account_data(cli) == account_data(http)
    return 1 if failures else 0


def main():
    binaries = list(pathlib.Path(".build").glob("*/debug/CodexBarCLI"))
    if len(binaries) != 1:
        raise SystemExit("Expected one local debug CodexBarCLI build.")
    with tempfile.TemporaryDirectory(prefix="codex-dashboard-fixture-") as folder:
        # Keep Foundation's /var spelling; its fixture grants compare normalized URL paths.
        return verify(str(binaries[0].resolve()), pathlib.Path(folder))


if __name__ == "__main__":
    sys.exit(main())
