#!/usr/bin/env python3
"""Exercise promotion through the debug CLI using only isolated synthetic files."""
import base64
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import uuid


def auth(email, workspace):
    def encoded(value):
        return base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip("=")
    claims = {"email": email, "https://api.openai.com/auth": {"chatgpt_plan_type": "pro"}}
    if workspace:
        claims["https://api.openai.com/auth"]["chatgpt_account_id"] = workspace
    tokens = {"accessToken": "synthetic-access", "refreshToken": "synthetic-refresh",
              "idToken": encoded({"alg": "none"}) + "." + encoded(claims) + "."}
    if workspace:
        tokens["accountId"] = workspace
    return json.dumps({"tokens": tokens}, sort_keys=True).encode()


def verify(binary, mode):
    with tempfile.TemporaryDirectory(prefix="codex-promotion-proof-") as directory:
        root = Path(directory)
        app = root / "Library/Application Support/CodexBar"
        homes = app / "managed-codex-homes"
        live = root / ".codex/auth.json"
        live.parent.mkdir(parents=True)
        config = root / "config.json"
        config.write_text('{"version":1,"providers":[]}')
        records = []

        def account(email, workspace, data):
            identifier = str(uuid.uuid4())
            home = homes / identifier
            home.mkdir(parents=True)
            if data is not None:
                (home / "auth.json").write_bytes(data)
            record = dict(id=identifier, email=email, managedHomePath=str(home), createdAt=1, updatedAt=1)
            if workspace:
                record.update(providerAccountID=workspace, workspaceAccountID=workspace)
            records.append(record)
            return record

        target_data = auth("target@example.com", "workspace-target")
        target = account("target@example.com", "workspace-target", target_data)
        displaced_data = auth("prior@example.com", None if mode == "conflict-email" else "workspace-prior")
        live.write_bytes(displaced_data)
        foreign_file = None
        if mode.startswith("conflict"):
            account("prior@example.com", None, auth("prior@example.com", "workspace-foreign"))
        elif mode == "provider-repair-with-legacy-conflict":
            account("prior@example.com", "workspace-prior", None)
            foreign = account("prior@example.com", None, auth("prior@example.com", "workspace-foreign"))
            foreign_file = Path(foreign["managedHomePath"]) / "auth.json"
        elif mode == "legacy-repair":
            account("prior@example.com", None, None)
        elif mode == "refresh":
            account("prior@example.com", "workspace-prior", displaced_data + b"\n")
        metadata = app / "managed-codex-accounts.json"
        metadata.write_text(json.dumps(dict(version=3, accounts=records)))
        tracked = [live, metadata, config, *homes.glob("*/auth.json")]
        before = {path: hashlib.sha256(path.read_bytes()).digest() for path in tracked}
        environment = {
            "HOME": str(root), "CFFIXED_USER_HOME": str(root), "CODEX_HOME": str(live.parent),
            "CODEXBAR_CONFIG": str(config), "PATH": "/usr/bin:/bin",
            "CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS": "1", "CODEXBAR_DISABLE_KEYCHAIN_ACCESS": "1",
            "CODEXBAR_TEST_CODEX_FILE_ISOLATION": "1", "CODEXBAR_TEST_SESSION_FILE_ISOLATION": "1",
            "CODEXBAR_TEST_CODEX_FILE_FIXTURES": json.dumps({"grants": [
                {"url": root.as_uri(), "resolvedURL": root.as_uri(), "isRoot": True}]}),
        }
        result = subprocess.run([binary, "codex-accounts", "promote", target["id"], "--json"],
                                env=environment, capture_output=True, timeout=90)
        if mode.startswith("conflict"):
            passed = result.returncode != 0 and b"Conflicting managed accounts" in result.stdout + result.stderr
            passed = passed and all(path.exists() and hashlib.sha256(path.read_bytes()).digest() == digest
                                    for path, digest in before.items())
            detail = "rejected; auth and metadata hashes unchanged" if passed else (
                f"exit={result.returncode}; live unchanged={live.read_bytes() == displaced_data}; "
                f"metadata unchanged={hashlib.sha256(metadata.read_bytes()).digest() == before[metadata]}")
        else:
            saved = json.loads(metadata.read_text())["accounts"]
            preserved = [row for row in saved if row["email"] == "prior@example.com"
                         and row.get("providerAccountID") == "workspace-prior"]
            passed = result.returncode == 0 and live.read_bytes() == target_data and len(preserved) == 1
            passed = passed and (Path(preserved[0]["managedHomePath"]) / "auth.json").read_bytes() == displaced_data
            passed = passed and (Path(target["managedHomePath"]) / "auth.json").read_bytes() == target_data
            if foreign_file is not None:
                passed = passed and hashlib.sha256(foreign_file.read_bytes()).digest() == before[foreign_file]
            detail = "promoted; displaced bytes preserved; target unchanged"
        print(f"{'PASS' if passed else 'FAIL'} {mode}: {detail if passed or mode.startswith('conflict') else 'contract not met (raw output withheld)'}")
        return passed


if __name__ == "__main__":
    executable = str(Path(sys.argv[1] if len(sys.argv) > 1 else ".build/debug/CodexBarCLI").resolve())
    results = [verify(executable, mode) for mode in
               ["conflict-email", "conflict-provider", "import", "legacy-repair", "refresh",
                "provider-repair-with-legacy-conflict"]]
    print(f"{sum(results)}/{len(results)} CLI scenarios passed")
    sys.exit(0 if all(results) else 1)
