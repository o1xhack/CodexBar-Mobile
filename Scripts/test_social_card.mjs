#!/usr/bin/env node
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { deflateSync } from "node:zlib";

import { checkSocialCard, updateSocialCard } from "./social-card.mjs";

function pngChunk(type, data) {
  const chunk = Buffer.alloc(data.length + 12);
  chunk.writeUInt32BE(data.length);
  chunk.write(type, 4);
  data.copy(chunk, 8);
  let crc = 0xffffffff;
  for (const byte of chunk.subarray(4, -4)) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0);
  }
  chunk.writeUInt32BE((crc ^ 0xffffffff) >>> 0, chunk.length - 4);
  return chunk;
}

const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
const header = Buffer.alloc(13);
header.writeUInt32BE(1200, 0);
header.writeUInt32BE(630, 4);
header[8] = 8;
header[9] = 2;
const scanlines = Buffer.alloc((1200 * 3 + 1) * 630);
const compressed = deflateSync(scanlines);
const endChunk = pngChunk("IEND", Buffer.alloc(0));
function pngImage(data = compressed, ihdr = header) {
  return Buffer.concat([signature, pngChunk("IHDR", ihdr), pngChunk("IDAT", data), endChunk]);
}
const pngFixture = pngImage();

function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "codexbar-social-card-"));
  t.after(() => fs.rmSync(root, { recursive: true }));
  fs.mkdirSync(path.join(root, "docs/logos"), { recursive: true });
  const write = (relativePath, value) => fs.writeFileSync(path.join(root, relativePath), value);
  const read = (relativePath) => fs.readFileSync(path.join(root, relativePath), "utf8");
  write(
    "docs/social.html",
    `<style>.mask { mask-image: url('./logos/provider.svg?version=1'); }
    .noise { background-image: url("data:image/svg+xml,<svg></svg>"); }</style>
    <img src="./icon.png?v=2"><strong>80 providers</strong>`,
  );
  write("docs/icon.png", "synthetic icon asset");
  write("docs/logos/provider.svg", '<svg xmlns="http://www.w3.org/2000/svg"></svg>');
  write(
    "docs/index.html",
    `<meta content="old" property="og:image"><meta name="twitter:image" content="old">
    <meta property="og:description" content="Keep this description">`,
  );
  write("README.md", '<img src="docs/social.png" alt="Social preview"><img src="unrelated.png" alt="Keep this">');
  write("rendered.png", pngFixture);
  write("docs/social.png", "previous image");
  return { root, write, read, update: () => updateSocialCard(root, path.join(root, "rendered.png")) };
}

test("updater records all rendered inputs and updates the three image references", (t) => {
  const f = fixture(t);
  f.update();
  checkSocialCard(f.root);
  const receipt = JSON.parse(f.read("docs/social-card.json"));
  assert.deepEqual(Object.keys(receipt.sources), ["docs/icon.png", "docs/logos/provider.svg", "docs/social.html"]);
  const hash = createHash("sha256").update(pngFixture).digest("hex");
  assert.equal(receipt.image.sha256, hash);
  assert.deepEqual([receipt.image.width, receipt.image.height], [1200, 630]);
  assert(fs.readFileSync(path.join(f.root, "docs/social.png")).equals(pngFixture));
  const url = `https://codexbar.app/social.png?v=${hash.slice(0, 16)}`;
  assert.equal(f.read("docs/index.html").split(url).length - 1, 2);
  assert(f.read("README.md").includes(`src="docs/social.png?v=${hash.slice(0, 16)}"`));
  assert(f.read("docs/index.html").includes('content="Keep this description"'));
  assert(f.read("README.md").includes('<img src="unrelated.png" alt="Keep this">'));
});

for (const [name, relativePath, mutate] of [
  ["provider-count source", "docs/social.html", (text) => text.replace("80 providers", "81 providers")],
  ["CSS mask asset", "docs/logos/provider.svg", (text) => text.replace("</svg>", "<path/></svg>")],
  ["img source asset", "docs/icon.png", (text) => `${text} changed`],
]) {
  test(`check rejects ${name} changes without a new render`, (t) => {
    const f = fixture(t);
    f.update();
    f.write(relativePath, mutate(f.read(relativePath)));
    assert.throws(() => checkSocialCard(f.root), /Social card render is stale/);
  });
}

test("check rejects a replaced PNG even when HTML and cache tokens are unchanged", (t) => {
  const f = fixture(t);
  f.update();
  const changedPixels = Buffer.from(scanlines);
  changedPixels[1] = 255;
  f.write("docs/social.png", pngImage(deflateSync(changedPixels)));
  assert.throws(() => checkSocialCard(f.root), /Social card render is stale/);
});

for (const relativePath of ["docs/index.html", "README.md"]) {
  test(`check rejects stale image cache tokens in ${relativePath}`, (t) => {
    const f = fixture(t);
    f.update();
    f.write(relativePath, f.read(relativePath).replace(/\?v=[0-9a-f]+/, "?v=old"));
    assert.throws(() => checkSocialCard(f.root), /must use the social image content hash/);
  });
}

const wrongSizeHeader = Buffer.from(header);
wrongSizeHeader.writeUInt32BE(2400, 0);
const unsupportedHeader = Buffer.from(header);
unsupportedHeader[8] = 16;
const badCRC = Buffer.from(pngFixture);
badCRC[29] ^= 1;
const badFilter = Buffer.from(scanlines);
badFilter[0] = 5;
for (const [name, png] of [
  ["non-PNG", Buffer.from("not an image")],
  ["wrong size", pngImage(compressed, wrongSizeHeader)],
  ["unsupported encoding", pngImage(compressed, unsupportedHeader)],
  ["header-only PNG", pngFixture.subarray(0, 33)],
  ["truncated chunk", pngFixture.subarray(0, -3)],
  ["bad chunk CRC", badCRC],
  ["CRC-valid invalid zlib data", pngImage(Buffer.from("not compressed pixels"))],
  ["CRC-valid truncated zlib stream", pngImage(compressed.subarray(0, -2))],
  ["extra compressed bytes", pngImage(Buffer.concat([compressed, Buffer.from([0])]))],
  ["short scanlines", pngImage(deflateSync(Buffer.alloc(16)))],
  ["oversized inflated data", pngImage(deflateSync(Buffer.alloc(scanlines.length + 1)))],
  ["invalid scanline filter", pngImage(deflateSync(badFilter))],
  ["missing IDAT", Buffer.concat([signature, pngChunk("IHDR", header), endChunk])],
  ["duplicate IHDR", Buffer.concat([pngFixture.subarray(0, 33), pngFixture.subarray(8)])],
  [
    "unknown critical chunk",
    Buffer.concat([pngFixture.subarray(0, 33), pngChunk("TEST", Buffer.alloc(0)), pngFixture.subarray(33)]),
  ],
  [
    "nonconsecutive IDAT",
    Buffer.concat([
      pngFixture.subarray(0, 33),
      pngChunk("IDAT", compressed.subarray(0, 12)),
      pngChunk("tEXt", Buffer.from("Software\0synthetic screenshot")),
      pngChunk("IDAT", compressed.subarray(12)),
      endChunk,
    ]),
  ],
  ["extra trailing bytes", Buffer.concat([pngFixture, Buffer.from([0])])],
]) {
  test(`updater rejects ${name} before changing published files`, (t) => {
    const f = fixture(t);
    f.write("rendered.png", png);
    assert.throws(f.update, /Social card/);
    assert.equal(f.read("docs/social.png"), "previous image");
    assert.equal(fs.existsSync(path.join(f.root, "docs/social-card.json")), false);
    assert(f.read("docs/index.html").includes('content="old"'));
  });
}

test("updater accepts RGBA screenshots with ancillary chunks and consecutive IDAT chunks", (t) => {
  const f = fixture(t);
  const rgbaHeader = Buffer.from(header);
  rgbaHeader[9] = 6;
  const rgbaPixels = deflateSync(Buffer.alloc((1200 * 4 + 1) * 630));
  f.write(
    "rendered.png",
    Buffer.concat([
      signature,
      pngChunk("IHDR", rgbaHeader),
      pngChunk("tEXt", Buffer.from("Software\0synthetic screenshot")),
      pngChunk("IDAT", rgbaPixels.subarray(0, 12)),
      pngChunk("IDAT", rgbaPixels.subarray(12)),
      endChunk,
    ]),
  );
  f.update();
  checkSocialCard(f.root);
});

test("updater rejects missing image metadata before changing published files", (t) => {
  const f = fixture(t);
  f.write("docs/index.html", '<meta property="og:image" content="old">');
  assert.throws(f.update, /exactly one twitter:image/);
  assert.equal(f.read("docs/social.png"), "previous image");
  assert.equal(fs.existsSync(path.join(f.root, "docs/social-card.json")), false);
});
