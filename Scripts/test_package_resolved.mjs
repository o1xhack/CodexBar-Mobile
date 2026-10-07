#!/usr/bin/env node
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const checker = fileURLToPath(new URL("./check-package-resolved.mjs", import.meta.url));
const widgetPath =
  "WidgetExtension/CodexBarWidgetExtension.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved";
const fixCommand = "xcodebuild -resolvePackageDependencies -project WidgetExtension/CodexBarWidgetExtension.xcodeproj";

function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "codexbar-resolved-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const script = path.join(root, "Scripts", path.basename(checker));
  fs.mkdirSync(path.dirname(script), { recursive: true });
  fs.copyFileSync(checker, script);
  const pins = [
    { identity: "sweetcookiekit", state: { revision: "new-revision", version: "0.5.4" } },
    { identity: "revision-only", state: { revision: "fixed-revision" } },
  ];
  const rootResolved = { version: 3, originHash: "root-hash", pins };
  const widgetResolved = { version: 3, originHash: "widget-hash", pins: structuredClone(pins).reverse() };
  const write = (relativePath, value) => {
    const target = path.join(root, relativePath);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, JSON.stringify(value));
  };
  return {
    rootResolved,
    widgetResolved,
    run() {
      write("Package.resolved", rootResolved);
      write(widgetPath, widgetResolved);
      const before = ["Package.resolved", widgetPath].map((file) => fs.readFileSync(path.join(root, file), "utf8"));
      const result = spawnSync(process.execPath, [script], { cwd: os.tmpdir(), encoding: "utf8" });
      assert.ifError(result.error);
      assert.deepEqual(
        ["Package.resolved", widgetPath].map((file) => fs.readFileSync(path.join(root, file), "utf8")),
        before,
        "the check must not rewrite pins",
      );
      return result;
    },
  };
}

test("matching pins pass regardless of order, origin hash, or absent versions", (t) => {
  const result = fixture(t).run();
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Package.resolved pins OK: 2 packages/);
});

for (const [name, mutate] of [
  [
    "SweetCookieKit 0.5.2 incident",
    (f) => Object.assign(f.widgetResolved.pins[1].state, { revision: "old-revision", version: "0.5.2" }),
  ],
  [
    "revision drift",
    (f) => {
      f.widgetResolved.pins[1].state.revision = "old-revision";
    },
  ],
  [
    "version drift",
    (f) => {
      f.widgetResolved.pins[1].state.version = "0.5.2";
    },
  ],
  [
    "missing version",
    (f) => {
      delete f.widgetResolved.pins[1].state.version;
    },
  ],
  [
    "missing widget pin",
    (f) => {
      f.widgetResolved.pins.pop();
    },
  ],
  [
    "missing root pin",
    (f) => {
      f.rootResolved.pins.shift();
    },
  ],
  [
    "identity drift",
    (f) => {
      f.widgetResolved.pins[1].identity = "different-package";
    },
  ],
]) {
  test(`rejects ${name} with the package name and repair command`, (t) => {
    const f = fixture(t);
    mutate(f);
    const result = f.run();
    assert.equal(result.status, 1);
    assert.match(result.stderr, /sweetcookiekit/);
    assert(result.stderr.includes(fixCommand), result.stderr);
  });
}

for (const side of ["rootResolved", "widgetResolved"]) {
  test(`rejects duplicate identities in ${side}`, (t) => {
    const f = fixture(t);
    f[side].pins.push(structuredClone(f[side].pins.find((pin) => pin.identity === "sweetcookiekit")));
    const result = f.run();
    assert.equal(result.status, 1);
    assert.match(result.stderr, /duplicate.*sweetcookiekit/);
  });

  test(`rejects malformed pins in ${side}`, (t) => {
    const f = fixture(t);
    f[side].pins = {};
    const result = f.run();
    assert.equal(result.status, 1);
    assert.match(result.stderr, /pins must be an array/);
  });
}
