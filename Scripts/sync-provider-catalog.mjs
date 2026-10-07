#!/usr/bin/env node
// Keep derived counts and existing catalog labels in sync without replacing curated provider descriptions.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");
const update = (file, transform) => {
  const before = read(file);
  const after = transform(before);
  if (before !== after) fs.writeFileSync(path.join(root, file), after);
};
const enumBody = read("Sources/CodexBarCore/Providers/Providers.swift").match(
  /public enum UsageProvider:[^{]+\{([\s\S]*?)\n\}/,
)[1];
const ids = [...enumBody.matchAll(/^\s*case (\w+)$/gm)].map((match) => match[1]);
const count = ids.length;
const selected = process.argv.slice(2);
if (selected.some((id) => !ids.includes(id))) throw new Error("Pass registered provider IDs to synchronize labels");
if (!count) throw new Error("No registered providers");
const counts = [
  ["README.md", /(?<=alt="CodexBar — every AI coding limit in your menu bar\. )\d+(?= providers\.")/g],
  ["docs/providers.md", /(?<=CodexBar currently registers )\d+(?= provider IDs)/g],
  ["docs/social.html", /(?<=<strong>)\d+(?= providers<\/strong>)/g],
  ["docs/index.html", /(?<=across )\d+(?= (?:AI coding )?providers)/g],
  ["docs/index.html", /(?<=>)\d+(?= providers,\{mobileBreak\})/g],
];
for (const [file, pattern] of counts) update(file, (text) => text.replace(pattern, String(count)));
update("docs/site-locales.mjs", (text) =>
  text.replace(
    /("(?:meta.description|meta.ogDescription|providers.title)": ")([^"\n]*)/g,
    (_, prefix, value) => prefix + value.replace(/\b\d+\b/, String(count)),
  ),
);

// Names are owned by descriptors; documentation keeps its existing links and prose.
const directory = "Sources/CodexBarCore/Providers";
for (const entry of fs.readdirSync(path.join(root, directory), { recursive: true })) {
  if (!entry.endsWith("ProviderDescriptor.swift")) continue;
  const source = read(`${directory}/${entry}`);
  const id = source.match(/\bid: \.(\w+),/)?.[1];
  const name = source.match(/\bdisplayName: "([^"]+)"/)?.[1];
  if (!selected.includes(id) || !name) continue;
  const link = new RegExp(`\\[[^\\]\\n]+\\]\\(((?:docs/)?${id}\\.md)\\)`, "g");
  for (const file of ["README.md", "docs/providers.md", "docs/plugins.md"]) {
    update(file, (text) => text.replace(link, (_, url) => `[${name}](${url})`));
  }
  update("docs/index.html", (text) =>
    text.replace(
      new RegExp(`(data-provider="${id}"[^\\n]*?<strong>)[^<]*(</strong>)`),
      (_, prefix, suffix) => prefix + name + suffix,
    ),
  );
}

update("docs/plugin-conversion-matrix.md", (text) => {
  const rows = (section) => [...section.matchAll(/^\| (\w+) \| `/gm)].map((match) => match[1]);
  const [before, additional] = text.split("## Additional plugin-first providers");
  const audited = rows(before.split("## Matrix")[1]);
  const pluginFirst = rows(additional);
  const classified = new Set([...audited, ...pluginFirst]);
  if ([...classified].some((id) => !ids.includes(id))) throw new Error("Matrix contains an unregistered provider");
  return text
    .replace(/registry now contains \d+ providers/, `registry now contains ${count} providers`)
    .replace(
      /\d+ audit rows, \d+ additional plugin-first rows, and \d+ providers not yet classified/,
      `${audited.length} audit rows, ${pluginFirst.length} additional plugin-first rows, and ${count - classified.size} providers not yet classified`,
    );
});
console.log(`Provider catalog synchronized (${count} providers). Run generate-llms.mjs and social-card.mjs afterward.`);
