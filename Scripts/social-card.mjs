#!/usr/bin/env node
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { inflateSync } from "node:zlib";

const htmlPath = "docs/social.html";
const imagePath = "docs/social.png";
const receiptPath = "docs/social-card.json";
const regenerationHint =
  "Render docs/social.html again, then run node Scripts/social-card.mjs --update <rendered.png>.";

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

const crcTable = Uint32Array.from({ length: 256 }, (_, value) => {
  for (let bit = 0; bit < 8; bit++) value = (value >>> 1) ^ (value & 1 ? 0xedb88320 : 0);
  return value >>> 0;
});

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) crc = (crc >>> 8) ^ crcTable[(crc ^ byte) & 0xff];
  return (crc ^ 0xffffffff) >>> 0;
}

function imageDimensions(png) {
  assert(
    png.length >= 33 &&
      png.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) &&
      png.readUInt32BE(8) === 13 &&
      png.toString("ascii", 12, 16) === "IHDR",
    "Social card must be a PNG image.",
  );
  const dimensions = { width: png.readUInt32BE(16), height: png.readUInt32BE(20) };
  assert.deepEqual(dimensions, { width: 1200, height: 630 }, "Social card must be exactly 1200 × 630 pixels.");
  assert(
    png[24] === 8 && [2, 6].includes(png[25]) && png[26] === 0 && png[27] === 0 && png[28] === 0,
    "Social card must use an 8-bit, noninterlaced RGB or RGBA PNG screenshot.",
  );
  assert(png.length <= 16 * 1024 * 1024, "Social card PNG exceeds the 16 MiB screenshot limit.");

  const dataChunks = [];
  let dataEnded = false;
  let paletteSeen = false;
  let endSeen = false;
  for (let offset = 8; offset < png.length;) {
    assert(offset + 12 <= png.length, "Social card PNG has a truncated chunk.");
    const length = png.readUInt32BE(offset);
    const end = offset + length + 12;
    assert(end <= png.length, "Social card PNG has a truncated chunk.");
    const type = png.toString("latin1", offset + 4, offset + 8);
    assert(/^[A-Za-z]{2}[A-Z][A-Za-z]$/.test(type), "Social card PNG has an invalid chunk type.");
    assert.equal(
      crc32(png.subarray(offset + 4, end - 4)),
      png.readUInt32BE(end - 4),
      `Social card PNG has an invalid ${type} chunk CRC.`,
    );
    const data = png.subarray(offset + 8, end - 4);
    if (type === "IDAT") {
      assert(!dataEnded, "Social card PNG must have consecutive IDAT chunks.");
      dataChunks.push(data);
    } else {
      if (dataChunks.length > 0) dataEnded = true;
      if (type === "IHDR") {
        assert(offset === 8 && length === 13, "Social card PNG must have one initial IHDR chunk.");
      } else if (type === "IEND") {
        assert(
          dataChunks.length > 0 && length === 0 && end === png.length,
          "Social card PNG must end with IEND after its image data.",
        );
        endSeen = true;
      } else if (type === "PLTE") {
        assert(
          !paletteSeen && dataChunks.length === 0 && length > 0 && length <= 768 && length % 3 === 0,
          "Social card PNG has an invalid optional palette.",
        );
        paletteSeen = true;
      } else {
        assert(/^[a-z]/.test(type), `Social card PNG has an unsupported critical chunk: ${type}.`);
      }
    }
    offset = end;
  }
  assert(endSeen, "Social card PNG is missing its complete image data or IEND chunk.");

  const compressed = Buffer.concat(dataChunks);
  const stride = 1 + dimensions.width * (png[25] === 2 ? 3 : 4);
  const expectedLength = stride * dimensions.height;
  let inflated;
  try {
    inflated = inflateSync(compressed, { maxOutputLength: expectedLength, info: true });
  } catch {
    assert.fail("Social card PNG has invalid or oversized compressed image data.");
  }
  assert.equal(inflated.engine.bytesWritten, compressed.length, "Social card PNG has extra compressed image data.");
  assert.equal(inflated.buffer.length, expectedLength, "Social card PNG has incomplete pixel scanlines.");
  for (let row = 0; row < dimensions.height; row++) {
    assert(inflated.buffer[row * stride] <= 4, "Social card PNG has an invalid scanline filter.");
  }
  return dimensions;
}

function attributes(tag) {
  return Object.fromEntries(
    [...tag.matchAll(/\b([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))/g)].map((match) => [
      match[1].toLowerCase(),
      match[2] ?? match[3] ?? match[4],
    ]),
  );
}

function sourceHashes(repoRoot) {
  const html = fs.readFileSync(path.join(repoRoot, htmlPath), "utf8");
  const references = [
    ...[...html.matchAll(/<img\b[^>]*>/gi)].map((match) => attributes(match[0]).src).filter(Boolean),
    ...[...html.matchAll(/url\(\s*(?:"([^"]*)"|'([^']*)'|([^)]*?))\s*\)/gi)].map(
      (match) => match[1] ?? match[2] ?? match[3],
    ),
  ];
  const sourcePaths = new Set([htmlPath]);
  for (const reference of references) {
    const value = reference.trim();
    if (!value || value.startsWith("#") || /^data:/i.test(value)) continue;
    const url = new URL(value, "https://social-card.invalid/docs/social.html");
    assert.equal(url.origin, "https://social-card.invalid", `Social card assets must be local: ${value}`);
    const relativePath = decodeURIComponent(url.pathname).slice(1);
    const absolutePath = path.resolve(repoRoot, relativePath);
    assert(
      absolutePath.startsWith(`${path.resolve(repoRoot)}${path.sep}`),
      `Social card asset escapes the repository: ${value}`,
    );
    sourcePaths.add(path.relative(repoRoot, absolutePath).split(path.sep).join("/"));
  }
  return Object.fromEntries(
    [...sourcePaths]
      .sort()
      .map((relativePath) => [relativePath, sha256(fs.readFileSync(path.join(repoRoot, relativePath)))]),
  );
}

function renderReceipt(repoRoot, png) {
  return {
    sources: sourceHashes(repoRoot),
    image: { path: imagePath, sha256: sha256(png), ...imageDimensions(png) },
  };
}

function replaceTagAttribute(source, tagName, matches, attribute, value, label) {
  const tags = [...source.matchAll(new RegExp(`<${tagName}\\b[^>]*>`, "gi"))].filter((match) =>
    matches(attributes(match[0])),
  );
  assert.equal(tags.length, 1, `Expected exactly one ${label}.`);
  const tag = tags[0];
  const attributePattern = new RegExp(`\\s${attribute}\\s*=\\s*(?:"[^"]*"|'[^']*'|[^\\s"'=<>\x60]+)`, "i");
  assert(attributePattern.test(tag[0]), `Missing ${attribute} on ${label}.`);
  const updatedTag = tag[0].replace(attributePattern, ` ${attribute}="${value}"`);
  return source.slice(0, tag.index) + updatedTag + source.slice(tag.index + tag[0].length);
}

function imageReferences(repoRoot, imageHash) {
  const query = `?v=${imageHash.slice(0, 16)}`;
  const imageURL = `https://codexbar.app/social.png${query}`;
  let index = fs.readFileSync(path.join(repoRoot, "docs/index.html"), "utf8");
  for (const [attribute, name] of [
    ["property", "og:image"],
    ["name", "twitter:image"],
  ]) {
    index = replaceTagAttribute(index, "meta", (attrs) => attrs[attribute] === name, "content", imageURL, name);
  }
  const readme = replaceTagAttribute(
    fs.readFileSync(path.join(repoRoot, "README.md"), "utf8"),
    "img",
    (attrs) => /^docs\/social\.png(?:[?#]|$)/.test(attrs.src ?? ""),
    "src",
    `${imagePath}${query}`,
    "README social card",
  );
  return { "docs/index.html": index, "README.md": readme };
}

export function checkSocialCard(repoRoot) {
  assert(fs.existsSync(path.join(repoRoot, receiptPath)), `Missing ${receiptPath}. ${regenerationHint}`);
  const png = fs.readFileSync(path.join(repoRoot, imagePath));
  const receipt = JSON.parse(fs.readFileSync(path.join(repoRoot, receiptPath), "utf8"));
  assert.deepEqual(receipt, renderReceipt(repoRoot, png), `Social card render is stale. ${regenerationHint}`);
  for (const [relativePath, expected] of Object.entries(imageReferences(repoRoot, receipt.image.sha256))) {
    assert.equal(
      fs.readFileSync(path.join(repoRoot, relativePath), "utf8"),
      expected,
      `${relativePath} must use the social image content hash in its cache token. ${regenerationHint}`,
    );
  }
}

export function updateSocialCard(repoRoot, renderedImagePath) {
  const png = fs.readFileSync(renderedImagePath);
  const receipt = renderReceipt(repoRoot, png);
  const references = imageReferences(repoRoot, receipt.image.sha256);
  // Validate all inputs and reference locations before replacing the published card.
  fs.writeFileSync(path.join(repoRoot, imagePath), png);
  fs.writeFileSync(path.join(repoRoot, receiptPath), `${JSON.stringify(receipt, null, 2)}\n`);
  for (const [relativePath, contents] of Object.entries(references)) {
    fs.writeFileSync(path.join(repoRoot, relativePath), contents);
  }
  checkSocialCard(repoRoot);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
  const args = process.argv.slice(2);
  if (args.length === 1 && args[0] === "--check") {
    checkSocialCard(repoRoot);
    console.log("Social card source, assets, image, and cache tokens are current.");
  } else if (args.length === 2 && args[0] === "--update") {
    updateSocialCard(repoRoot, path.resolve(args[1]));
    console.log("Updated social card image, render receipt, and cache tokens.");
  } else {
    console.error("Usage: node Scripts/social-card.mjs --check | --update <rendered.png>");
    process.exitCode = 1;
  }
}
