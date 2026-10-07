#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const rootPath = "Package.resolved";
const widgetPath =
  "WidgetExtension/CodexBarWidgetExtension.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved";
const fixCommand = "xcodebuild -resolvePackageDependencies -project WidgetExtension/CodexBarWidgetExtension.xcodeproj";

function readPins(relativePath) {
  const resolved = JSON.parse(fs.readFileSync(path.join(repoRoot, relativePath), "utf8"));
  if (!Array.isArray(resolved?.pins)) throw new Error(`${relativePath}: pins must be an array`);
  const pins = new Map();
  for (const pin of resolved.pins) {
    if (typeof pin?.identity !== "string" || !pin.identity) {
      throw new Error(`${relativePath}: pin is missing an identity`);
    }
    if (pins.has(pin.identity)) throw new Error(`${relativePath}: duplicate pin ${pin.identity}`);
    const { revision, version } = pin.state ?? {};
    if (typeof revision !== "string" || !revision || (version != null && typeof version !== "string")) {
      throw new Error(`${relativePath}: invalid revision/version for ${pin.identity}`);
    }
    pins.set(pin.identity, { revision, version: version ?? null });
  }
  return pins;
}

function describe(pin) {
  return pin ? `revision=${pin.revision}, version=${pin.version ?? "(none)"}` : "missing";
}

try {
  const root = readPins(rootPath);
  const widget = readPins(widgetPath);
  const differences = [];
  for (const identity of [...new Set([...root.keys(), ...widget.keys()])].sort()) {
    const rootPin = root.get(identity);
    const widgetPin = widget.get(identity);
    if (!rootPin || !widgetPin || rootPin.revision !== widgetPin.revision || rootPin.version !== widgetPin.version) {
      differences.push(`${identity}: root ${describe(rootPin)}; widget ${describe(widgetPin)}`);
    }
  }
  if (differences.length) {
    throw new Error(`pin drift between ${rootPath} and ${widgetPath}:\n${differences.join("\n")}`);
  }
  console.log(`Package.resolved pins OK: ${root.size} packages`);
} catch (error) {
  console.error(`Package.resolved check failed: ${error.message}\nFrom the repository root, run:\n  ${fixCommand}`);
  process.exitCode = 1;
}
