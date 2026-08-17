#!/usr/bin/env node

import fs from "node:fs/promises";
import process from "node:process";

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

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});

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
    const body = buildIssueBody({
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

  return response.json();
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

function buildIssueBody({ release, baseline, syncDate, upstream }) {
  const tag = release.tag_name;
  const releaseDate = release.published_at ? release.published_at.slice(0, 10) : "unknown";
  const releaseUrl = release.html_url || `https://github.com/${upstream}/releases/tag/${tag}`;
  const releaseNotes = (release.body || "").trim() || "_上游未填写 release notes。_";
  const impactRows = inferImpactRows(releaseNotes);

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

*基线以 [\`version.env\`](https://github.com/${repo}/blob/mobile-dev/version.env) 的 \`UPSTREAM_VERSION\` 字段为准*
*Auto-generated by upstream-release-monitor workflow*
`;
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
