#!/usr/bin/env node

import assert from "node:assert/strict";

import { buildIssueBody, neutralizeImportedMarkdownMentions } from "./upstream-release-monitor.mjs";

const inertMention = (handle) => `@\u2060${handle}`;

const sourceMarkdown = [
  "### Fixed",
  "",
  "- Thanks @octocat and @example-org/release.",
  "- Email dev@example.com and keep https://github.com/@path intact.",
  "- Keep [an ordinary link](https://example.com/@path) intact.",
  "- Keep [a query link](https://example.com/?assignee=@octocat) intact.",
  "- Keep [a relative link](/issues?q=assignee:@octocat) intact.",
  "- Keep [a balanced link](https://example.com/a(b)?assignee=@octocat) intact.",
  '- Keep [a titled link](https://example.com/@octocat "title (") intact.',
  "- Keep <//example.com/@octocat> intact.",
  "- Encoded attribution: &#64;encoded-user.",
  "- Inline code: `@inline-user`.",
  "",
  "> [!NOTE]",
  "> Alert attribution @alert-user.",
  "",
  "```text",
  "@fenced-user",
  "```",
  "",
  "[^1]: Footnote attribution @footnote-user.",
].join("\n");

const expectedMarkdown = [
  "### Fixed",
  "",
  `- Thanks ${inertMention("octocat")} and ${inertMention("example-org/release")}.`,
  "- Email dev@example.com and keep https://github.com/@path intact.",
  "- Keep [an ordinary link](https://example.com/@path) intact.",
  "- Keep [a query link](https://example.com/?assignee=@octocat) intact.",
  "- Keep [a relative link](/issues?q=assignee:@octocat) intact.",
  "- Keep [a balanced link](https://example.com/a(b)?assignee=@octocat) intact.",
  '- Keep [a titled link](https://example.com/@octocat "title (") intact.',
  "- Keep <//example.com/@octocat> intact.",
  "- Encoded attribution: &#64;\u2060encoded-user.",
  "- Inline code: `@inline-user`.",
  "",
  "> [!NOTE]",
  `> Alert attribution ${inertMention("alert-user")}.`,
  "",
  "```text",
  "@fenced-user",
  "```",
  "",
  `[^1]: Footnote attribution ${inertMention("footnote-user")}.`,
].join("\n");

assert.equal(neutralizeImportedMarkdownMentions(sourceMarkdown), expectedMarkdown);
assert.equal(neutralizeImportedMarkdownMentions(expectedMarkdown), expectedMarkdown);

for (const codeBlock of [
  "> ~~~sh\n> npm install @scope/pkg\n> ~~~",
  "- ~~~sh\n  npm install @scope/pkg\n  ~~~",
  "> ```sh\n> npm install @scope/pkg\n> ````",
  "    npm install @scope/pkg",
  ">     npm install @scope/pkg",
  "- item\n\n      npm install @scope/pkg",
  "> paragraph\n>\n>     npm install @scope/pkg",
  "    npm install @scope/pkg\n\nThanks @octocat",
]) {
  const expected = codeBlock.endsWith("Thanks @octocat")
    ? codeBlock.replace("Thanks @octocat", `Thanks ${inertMention("octocat")}`)
    : codeBlock;
  assert.equal(neutralizeImportedMarkdownMentions(codeBlock), expected);
}

for (const listContinuation of [
  "- item\n    Thanks @octocat",
  "> item\n    Thanks @octocat",
  "1. item\n    Thanks @octocat",
  "- item\n\n    Thanks @octocat",
]) {
  assert.ok(neutralizeImportedMarkdownMentions(listContinuation).includes(inertMention("octocat")));
}

assert.equal(
  neutralizeImportedMarkdownMentions("~~~text\r\n@inline-code\r\n~~~\r\nThanks @octocat\r\n"),
  `~~~text\r\n@inline-code\r\n~~~\r\nThanks ${inertMention("octocat")}\r\n`,
);
assert.equal(
  neutralizeImportedMarkdownMentions("cc:@octocat foo/@octocat foo+@octocat"),
  `cc:${inertMention("octocat")} foo/${inertMention("octocat")} foo+${inertMention("octocat")}`,
);

const renderCalls = [];
const body = await buildIssueBody({
  release: {
    tag_name: "v9.9.9",
    published_at: "2026-08-20T12:00:00Z",
    html_url: "https://github.com/example/project/releases/tag/v9.9.9",
    body: sourceMarkdown,
  },
  baseline: "v9.9.8",
  syncDate: "2026-08-19",
  upstream: "example/project",
  issueRepo: "example/fork",
  renderMarkdown: async (markdown, context) => {
    renderCalls.push({ markdown, context });
    return "<h3>Fixed</h3><p>No live mentions</p>";
  },
});

assert.deepEqual(renderCalls, [
  {
    markdown: expectedMarkdown,
    context: "example/fork",
  },
]);
assert.ok(body.includes(expectedMarkdown));
assert.ok(!body.includes(sourceMarkdown));
assert.match(body, /https:\/\/github\.com\/example\/project\/releases\/tag\/v9\.9\.9/);
assert.match(body, /https:\/\/github\.com\/example\/fork\/blob\/mobile-dev\/version\.env/);

await assert.rejects(
  buildIssueBody({
    release: {
      tag_name: "v9.9.10",
      published_at: "2026-08-20T13:00:00Z",
      body: "@&#111;ctocat",
    },
    baseline: "v9.9.8",
    syncDate: "2026-08-19",
    upstream: "example/project",
    issueRepo: "example/fork",
    renderMarkdown: async () => '<p><a class="user-mention" href="https://github.com/octocat">@octocat</a></p>',
  }),
  /still contain a live GitHub mention/,
);

const safeObfuscatedBody = await buildIssueBody({
  release: {
    tag_name: "v9.9.11",
    published_at: "2026-08-20T14:00:00Z",
    body: "@<!-- -->octocat",
  },
  baseline: "v9.9.8",
  syncDate: "2026-08-19",
  upstream: "example/project",
  issueRepo: "example/fork",
  renderMarkdown: async () => "<p>@octocat</p>",
});

assert.ok(safeObfuscatedBody.includes("@<!-- -->octocat"));
console.log("upstream release monitor mention tests passed");
