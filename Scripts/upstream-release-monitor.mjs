#!/usr/bin/env node

import fs from "node:fs/promises";
import process from "node:process";
import { pathToFileURL } from "node:url";

const DEFAULT_REPO = process.env.GITHUB_REPOSITORY || "o1xhack/CodexBar-Mobile";
const DEFAULT_UPSTREAM = "steipete/CodexBar";
const DEFAULT_VERSION_ENV = "version.env";
const GENERIC_ISSUE_TITLE = "🔄 Upstream Changes Available for Review";

const args = parseArgs(process.argv.slice(2));
const repo = args.repo || DEFAULT_REPO;
const upstream = args.upstream || DEFAULT_UPSTREAM;
const versionEnvPath = args.versionEnv || DEFAULT_VERSION_ENV;
const apply = Boolean(args.apply);
const dryRun = !apply || Boolean(args.dryRun);
const token = process.env.GITHUB_TOKEN || process.env.GH_TOKEN || "";

const entryPoint = process.argv[1] ? pathToFileURL(process.argv[1]).href : "";
if (import.meta.url === entryPoint) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  });
}

function parseArgs(argv) {
  const parsed = {};
  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === "--apply") {
      parsed.apply = true;
    } else if (value === "--dry-run") {
      parsed.dryRun = true;
    } else if (value.startsWith("--repo=")) {
      parsed.repo = value.slice("--repo=".length);
    } else if (value === "--repo") {
      parsed.repo = argv[++index];
    } else if (value.startsWith("--upstream=")) {
      parsed.upstream = value.slice("--upstream=".length);
    } else if (value === "--upstream") {
      parsed.upstream = argv[++index];
    } else if (value.startsWith("--version-env=")) {
      parsed.versionEnv = value.slice("--version-env=".length);
    } else if (value === "--version-env") {
      parsed.versionEnv = argv[++index];
    } else {
      throw new Error(`Unknown argument: ${value}`);
    }
  }
  return parsed;
}

async function main() {
  const versionEnv = await readVersionEnv(versionEnvPath);
  const baseline = versionEnv.UPSTREAM_VERSION;
  const syncDate = versionEnv.UPSTREAM_SYNC_DATE || "unknown";

  if (!baseline) {
    throw new Error(`${versionEnvPath} is missing UPSTREAM_VERSION`);
  }

  console.log(`Repository: ${repo}`);
  console.log(`Upstream: ${upstream}`);
  console.log(`Current baseline: ${baseline} (${syncDate})`);

  const releases = await fetchReleases(upstream);
  const newReleases = releases
    .filter((release) => isTrackableRelease(release))
    .filter((release) => compareTags(release.tag_name, baseline) > 0)
    .sort((left, right) => compareTags(left.tag_name, right.tag_name));

  if (newReleases.length === 0) {
    console.log("No new upstream releases detected.");
    return;
  }

  console.log(`New releases: ${newReleases.map((release) => release.tag_name).join(", ")}`);

  const trackedIssues = await fetchTrackedIssues(repo);
  let reusableGenericIssue = trackedIssues.find((issue) => {
    return (
      issue.state === "open" &&
      (issue.title === GENERIC_ISSUE_TITLE || issue.body?.includes("## 🔄 Upstream Changes Detected"))
    );
  });

  for (const release of newReleases) {
    const existing = trackedIssues.find((issue) => {
      return issue.title.includes(release.tag_name) || issue.body?.includes(`/releases/tag/${release.tag_name}`);
    });

    if (existing) {
      console.log(`Issue already exists for ${release.tag_name}: #${existing.number}`);
      continue;
    }

    const title = buildIssueTitle(release.tag_name, baseline);
    const body = await buildIssueBody({
      release,
      baseline,
      syncDate,
      upstream,
    });

    if (reusableGenericIssue) {
      console.log(
        `${dryRun ? "Would update" : "Updating"} generic issue #${reusableGenericIssue.number} for ${release.tag_name}`,
      );
      if (!dryRun) {
        await updateIssue(repo, reusableGenericIssue.number, {
          title,
          body,
          labels: ["upstream-sync"],
        });
      }
      reusableGenericIssue = null;
    } else {
      console.log(`${dryRun ? "Would create" : "Creating"} issue for ${release.tag_name}`);
      if (!dryRun) {
        const created = await createIssue(repo, {
          title,
          body,
          labels: ["upstream-sync"],
        });
        console.log(`Created #${created.number}: ${created.html_url}`);
      }
    }
  }
}

async function readVersionEnv(filePath) {
  const contents = await fs.readFile(filePath, "utf8");
  const result = {};
  for (const line of contents.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) {
      continue;
    }
    const separator = trimmed.indexOf("=");
    if (separator === -1) {
      continue;
    }
    result[trimmed.slice(0, separator)] = trimmed.slice(separator + 1);
  }
  return result;
}

async function fetchReleases(fullName) {
  const releases = [];
  for (let page = 1; page <= 5; page += 1) {
    const chunk = await request("GET", `/repos/${fullName}/releases?per_page=100&page=${page}`);
    releases.push(...chunk);
    if (chunk.length < 100) {
      break;
    }
  }
  return releases;
}

async function fetchTrackedIssues(fullName) {
  const issues = [];
  for (let page = 1; page <= 5; page += 1) {
    const chunk = await request(
      "GET",
      `/repos/${fullName}/issues?state=all&labels=upstream-sync&per_page=100&page=${page}`,
    );
    issues.push(...chunk.filter((issue) => !issue.pull_request));
    if (chunk.length < 100) {
      break;
    }
  }
  return issues;
}

async function createIssue(fullName, payload) {
  return request("POST", `/repos/${fullName}/issues`, { body: payload });
}

async function updateIssue(fullName, number, payload) {
  return request("PATCH", `/repos/${fullName}/issues/${number}`, { body: payload });
}

async function request(method, path, options = {}) {
  if (!dryRun && !token) {
    throw new Error("GITHUB_TOKEN or GH_TOKEN is required when using --apply");
  }

  const headers = {
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
  };

  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }

  if (options.body) {
    headers["Content-Type"] = "application/json";
  }

  const requestOptions = {
    method,
    headers,
  };
  if (method !== "GET" && options.body) {
    requestOptions.body = JSON.stringify(options.body);
  }

  const response = await fetch(`https://api.github.com${path}`, requestOptions);

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`${method} ${path} failed: ${response.status} ${text.slice(0, 500)}`);
  }

  if (response.status === 204) {
    return null;
  }

  const contentType = response.headers.get("content-type") || "";
  return contentType.includes("json") ? response.json() : response.text();
}

function isTrackableRelease(release) {
  return !release.draft && !release.prerelease && Boolean(parseTag(release.tag_name));
}

function parseTag(tag) {
  const match = /^v(\d+)\.(\d+)(?:\.(\d+))?$/.exec(tag);
  if (!match) {
    return null;
  }
  return [Number(match[1]), Number(match[2]), Number(match[3] || 0)];
}

function compareTags(left, right) {
  const leftParts = parseTag(left);
  const rightParts = parseTag(right);
  if (!leftParts || !rightParts) {
    throw new Error(`Cannot compare non-release tags: ${left}, ${right}`);
  }
  for (let index = 0; index < leftParts.length; index += 1) {
    if (leftParts[index] !== rightParts[index]) {
      return leftParts[index] - rightParts[index];
    }
  }
  return 0;
}

function buildIssueTitle(tag, baseline) {
  return `上游同步：steipete/CodexBar 已发布 ${tag}（当前基线 ${baseline}）`;
}

export async function buildIssueBody({
  release,
  baseline,
  syncDate,
  upstream,
  issueRepo = repo,
  renderMarkdown = renderGitHubMarkdown,
}) {
  const tag = release.tag_name;
  const releaseDate = release.published_at ? release.published_at.slice(0, 10) : "unknown";
  const releaseUrl = release.html_url || `https://github.com/${upstream}/releases/tag/${tag}`;
  const rawReleaseNotes = (release.body || "").trim() || "_上游未填写 release notes。_";
  const releaseNotes = neutralizeImportedMarkdownMentions(rawReleaseNotes);
  const renderedReleaseNotes = await renderMarkdown(releaseNotes, issueRepo);
  if (hasRenderedGitHubMentionAnchors(renderedReleaseNotes)) {
    throw new Error(`Imported release notes for ${tag} still contain a live GitHub mention after neutralization`);
  }
  const impactRows = inferImpactRows(rawReleaseNotes);

  return `## 概述

上游仓库 [${upstream}](https://github.com/${upstream}) 于 ${releaseDate} 发布了 **${tag}**，比我们当前基线 \`UPSTREAM_VERSION=${baseline}\` 更新。

> **当前基线**（\`version.env\` -> \`UPSTREAM_VERSION\`）：\`${baseline}\`（UPSTREAM_SYNC_DATE: ${syncDate}）
> **本 issue 涵盖版本**：[${tag}](${releaseUrl})（${releaseDate}）

---

## ${tag} 完整 Release Notes（上游原文，${releaseDate}）

${releaseNotes}

---

## iOS 影响初筛（自动生成）

| 变更项 | iOS 相关性 | 优先级 |
|--------|-----------|--------|
${impactRows.map((row) => `| ${row.change} | ${row.relevance} | ${row.priority} |`).join("\n")}

---

## 下一步

- [ ] 人工复核上游 release notes，必要时补充中文摘要与 iOS 影响评估
- [ ] 评估 \`CodexBarMobile/Shared/\` 和 iOS 用量卡片是否需要同步修正
- [ ] 完成同步并实际发布后更新 \`version.env\`：\`UPSTREAM_VERSION=${tag}\`，\`UPSTREAM_SYNC_DATE=${releaseDate}\`

---

**上游 Release 链接：** ${releaseUrl}

*基线以 [\`version.env\`](https://github.com/${issueRepo}/blob/mobile-dev/version.env) 的 \`UPSTREAM_VERSION\` 字段为准*
*Auto-generated by upstream-release-monitor workflow*
`;
}

async function renderGitHubMarkdown(markdown, context) {
  return request("POST", "/markdown", {
    body: {
      text: markdown,
      mode: "gfm",
      context,
    },
  });
}

export function neutralizeImportedMarkdownMentions(markdown) {
  const lines = markdown.match(/[^\n]*(?:\n|$)/g) || [];
  const output = [];
  let prose = "";
  let fence = null;
  let previousLineBlank = true;
  let indentedCode = false;
  let listContentIndent = null;

  const flushProse = () => {
    output.push(neutralizeInlineMarkdownMentions(prose));
    prose = "";
  };

  for (const line of lines) {
    if (!line) {
      continue;
    }

    if (fence) {
      output.push(line);
      if (isClosingFence(line, fence)) {
        fence = null;
      }
      previousLineBlank = false;
      continue;
    }

    const openingFence = parseOpeningFence(line);
    if (openingFence) {
      flushProse();
      output.push(line);
      fence = openingFence;
      const openingListIndent = parseListContentIndent(line);
      if (openingListIndent !== null) {
        listContentIndent = openingListIndent;
      }
      previousLineBlank = false;
      indentedCode = false;
      continue;
    }

    const currentListIndent = parseListContentIndent(line);
    if (currentListIndent !== null) {
      listContentIndent = currentListIndent;
    }

    const codeIndent = indentedCodeWidth(line);
    const startsIndentedCode =
      codeIndent >= 4 && previousLineBlank && (listContentIndent === null || codeIndent >= listContentIndent + 4);
    if (codeIndent >= 4 && (indentedCode || startsIndentedCode)) {
      flushProse();
      output.push(line);
      previousLineBlank = false;
      indentedCode = true;
      continue;
    }

    prose += line;
    if (isBlankMarkdownLine(line)) {
      previousLineBlank = true;
    } else {
      previousLineBlank = false;
      indentedCode = false;
      if (currentListIndent === null && codeIndent === 0 && !/^(?: {0,3}>[ \t]?)/.test(line)) {
        listContentIndent = null;
      }
    }
  }

  flushProse();
  return output.join("");
}

function neutralizeInlineMarkdownMentions(markdown) {
  let output = "";
  let proseStart = 0;
  let index = 0;

  while (index < markdown.length) {
    if (markdown[index] !== "`") {
      index += 1;
      continue;
    }

    const delimiterLength = countRun(markdown, index, "`");
    const closingIndex = findMatchingBacktickRun(markdown, index + delimiterLength, delimiterLength);
    if (closingIndex === -1) {
      index += delimiterLength;
      continue;
    }

    output += neutralizeProseMentionTokens(markdown.slice(proseStart, index));
    const codeEnd = closingIndex + delimiterLength;
    output += markdown.slice(index, codeEnd);
    proseStart = codeEnd;
    index = codeEnd;
  }

  output += neutralizeProseMentionTokens(markdown.slice(proseStart));
  return output;
}

function neutralizeProseMentionTokens(markdown) {
  const linkDestinations = findMarkdownLinkDestinationSpans(markdown);
  let output = "";
  let proseStart = 0;

  for (const span of linkDestinations) {
    output += neutralizeProseMentionsOutsideLinkDestinations(markdown.slice(proseStart, span.start));
    output += markdown.slice(span.start, span.end);
    proseStart = span.end;
  }

  output += neutralizeProseMentionsOutsideLinkDestinations(markdown.slice(proseStart));
  return output;
}

function neutralizeProseMentionsOutsideLinkDestinations(markdown) {
  const protectedSyntax = new RegExp(
    [
      String.raw`^[ \t]{0,3}\[[^\]\r\n]+\]:[ \t]*(?:<[^>\r\n]*>|[^\s]+)`,
      String.raw`<!--[^\r\n]*-->|<\/?[A-Za-z][^>\r\n]*>`,
    ].join("|"),
    "gim",
  );
  const protectedSpans = findStandaloneUrlSpans(markdown);

  for (const match of markdown.matchAll(protectedSyntax)) {
    protectedSpans.push({ start: match.index, end: match.index + match[0].length });
  }

  protectedSpans.sort((left, right) => left.start - right.start || right.end - left.end);
  let output = "";
  let proseStart = 0;

  for (const span of protectedSpans) {
    if (span.end <= proseStart) {
      continue;
    }
    if (span.start <= proseStart) {
      output += markdown.slice(proseStart, span.end);
      proseStart = span.end;
      continue;
    }
    output += neutralizeNonUrlMentionTokens(markdown.slice(proseStart, span.start));
    output += markdown.slice(span.start, span.end);
    proseStart = span.end;
  }

  output += neutralizeNonUrlMentionTokens(markdown.slice(proseStart));
  return output;
}

function findStandaloneUrlSpans(markdown) {
  const spans = [];
  const urlStart = /(?:(?:https?|ftp):\/\/|\/\/|\bwww\.)/gim;

  for (const match of markdown.matchAll(urlStart)) {
    const start = match.index;
    let cursor = start + match[0].length;
    const openingParentheses = [];

    while (cursor < markdown.length && !/[\s<>"']/.test(markdown[cursor])) {
      if (markdown[cursor] === "\\") {
        cursor += 2;
        continue;
      }
      if (markdown[cursor] === "(") {
        openingParentheses.push(cursor);
      } else if (markdown[cursor] === ")") {
        if (openingParentheses.length === 0) {
          break;
        }
        openingParentheses.pop();
      }
      cursor += 1;
    }

    if (openingParentheses.length > 0) {
      cursor = openingParentheses[0];
    }
    spans.push({ start, end: cursor });
  }

  return spans;
}

function findMarkdownLinkDestinationSpans(markdown) {
  const spans = [];

  for (let index = 0; index < markdown.length - 1; index += 1) {
    if (markdown[index] !== "]" || markdown[index + 1] !== "(") {
      continue;
    }

    let depth = 1;
    let cursor = index + 2;
    while (cursor < markdown.length) {
      const character = markdown[cursor];
      if (character === "\\") {
        cursor += 2;
        continue;
      }
      if ((character === '"' || character === "'") && depth === 1 && /\s/.test(markdown[cursor - 1] || "")) {
        cursor = skipQuotedMarkdownText(markdown, cursor, character);
        continue;
      }
      if (character === "(") {
        depth += 1;
      } else if (character === ")") {
        depth -= 1;
        if (depth === 0) {
          spans.push({ start: index, end: cursor + 1 });
          index = cursor;
          break;
        }
      }
      cursor += 1;
    }
  }

  return spans;
}

function skipQuotedMarkdownText(markdown, openingIndex, quote) {
  let cursor = openingIndex + 1;
  while (cursor < markdown.length) {
    if (markdown[cursor] === "\\") {
      cursor += 2;
      continue;
    }
    if (markdown[cursor] === quote) {
      return cursor + 1;
    }
    cursor += 1;
  }
  return cursor;
}

function neutralizeNonUrlMentionTokens(markdown) {
  const handle = String.raw`[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})`;
  const suffix = String.raw`(?=${handle}(?:/${handle})?(?![A-Za-z0-9-]))`;
  const boundary = String.raw`(^|[^\p{L}\p{N}_])`;
  const plainMention = new RegExp(`${boundary}@${suffix}`, "gu");
  const encodedMention = new RegExp(`${boundary}(&#0*64;|&#x0*40;|&commat;)${suffix}`, "giu");

  return markdown.replace(plainMention, "$1@\u2060").replace(encodedMention, "$1$2\u2060");
}

function parseOpeningFence(line) {
  const match = /^[ \t>+*.)0-9-]*(`{3,}|~{3,})([^\r\n]*)(?:\r?\n|$)/.exec(line);
  if (!match || (match[1][0] === "`" && match[2].includes("`"))) {
    return null;
  }
  return { character: match[1][0], length: match[1].length };
}

function isClosingFence(line, fence) {
  const character = fence.character === "`" ? "`" : "~";
  return new RegExp(`^[ \\t>+*.)0-9-]*${character}{${fence.length},}[ \\t]*(?:\\r?\\n|$)`).test(line);
}

function parseListContentIndent(line) {
  const content = line.replace(/^(?: {0,3}>[ \t]?)*/, "");
  const match = /^( *)(?:[-+*]|\d{1,9}[.)])([ \t]+)/.exec(content);
  return match ? match[0].length : null;
}

function indentedCodeWidth(line) {
  const content = line.replace(/^(?: {0,3}>[ \t]?)*/, "");
  if (content.startsWith("\t")) {
    return 4;
  }
  return /^( *)/.exec(content)[1].length;
}

function isBlankMarkdownLine(line) {
  const content = line.replace(/^(?: {0,3}>[ \t]?)*/, "");
  return /^[ \t]*(?:\r?\n)?$/.test(content);
}

function countRun(text, start, character) {
  let end = start;
  while (text[end] === character) {
    end += 1;
  }
  return end - start;
}

function findMatchingBacktickRun(markdown, start, delimiterLength) {
  let index = start;
  while (index < markdown.length) {
    if (markdown[index] !== "`") {
      index += 1;
      continue;
    }
    const runLength = countRun(markdown, index, "`");
    if (runLength === delimiterLength) {
      return index;
    }
    index += runLength;
  }
  return -1;
}

function hasRenderedGitHubMentionAnchors(html) {
  const anchor = /<a\b([^>]*)>[\s\S]*?<\/a>/gi;
  return [...html.matchAll(anchor)].some((match) => hasGitHubMentionClass(match[1]));
}

function hasGitHubMentionClass(attributes) {
  const classAttribute = /\bclass=(["'])(.*?)\1/i.exec(attributes);
  const classes = classAttribute?.[2].split(/\s+/) || [];
  return classes.includes("user-mention") || classes.includes("team-mention");
}

function inferImpactRows(body) {
  const rows = [];

  addIf(
    rows,
    /Localization: add .*selectable app language/i.test(body),
    "新增可选 App 语言",
    "✅ iOS 本地化语言覆盖需评估是否跟随上游扩展",
    "P1",
  );
  addIf(
    rows,
    /Codex: .*reset.*timestamps|Codex: .*window metadata/i.test(body),
    "Codex reset timestamp / window metadata 修正",
    "✅ iOS Codex 用量卡片需确认同步数据是否能展示正确 reset 信息",
    "P2",
  );
  addIf(
    rows,
    /Cursor: .*deficit|Cursor: .*run-out/i.test(body),
    "Cursor deficit / run-out pace 明细",
    "✅ iOS Cursor 用量展示需确认是否需要展示相同明细",
    "P2",
  );
  addIf(
    rows,
    /Codex Spark: .*deficit|Codex Spark: .*run-out/i.test(body),
    "Codex Spark deficit / run-out pace 明细",
    "✅ iOS Codex Spark 配额 lane 需确认是否同步",
    "P2",
  );
  addIf(
    rows,
    /Antigravity/i.test(body),
    "Antigravity quota / CLI 检测修正",
    "✅ iOS Antigravity 用量卡片需确认汇总口径是否同步",
    "P2",
  );
  addIf(
    rows,
    /models\.dev|cost catalog|Codex history scans/i.test(body),
    "models.dev cost catalog / Codex history 扫描性能",
    "⚠️ Shared 成本扫描或缓存逻辑是否受影响需评估",
    "P2",
  );
  addIf(
    rows,
    /Claude: .*pace|Claude: .*reserve/i.test(body),
    "Claude pace / reserve 口径修正",
    "✅ iOS Claude 用量卡片需确认窗口口径是否一致",
    "P2",
  );
  addIf(rows, /Kiro:/i.test(body), "Kiro CLI discovery 修正", "❌ macOS CLI 环境检测专属，iOS 通常不适用", "-");
  addIf(
    rows,
    /Menu bar|AppKit|status menu|dropdown|submenu|status icons/i.test(body),
    "Menu bar / AppKit 菜单性能与交互修正",
    "❌ macOS 菜单栏专属，iOS 通常不适用",
    "-",
  );

  if (rows.length === 0) {
    rows.push({
      change: "上游 release notes 未命中自动规则",
      relevance: "⚠️ 需要人工判断是否影响 iOS Shared 层或用量卡片",
      priority: "P3",
    });
  }

  return rows;
}

function addIf(rows, condition, change, relevance, priority) {
  if (!condition) {
    return;
  }
  rows.push({ change, relevance, priority });
}
