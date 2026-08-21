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
  "- Keep https://example.com/a(b)?assignee=@octocat intact.",
  "- Keep ftp://example.com/a((b))?assignee=@octocat intact.",
  "- Keep //example.com/a(b)?assignee=@octocat intact.",
  "- Keep www.example.com/a(b)?assignee=@octocat intact.",
  "- Keep <//example.com/@octocat> intact.",
  "- Encoded attribution: &#64;encoded-user.",
  "- Inline code: `@inline-user`.",
  '- HTML code: <code data-owner="@octocat">npm install @scope/pkg</code>.',
  "<pre>",
  "npm install @pre-scope/pkg",
  "</pre>",
  "",
  "[@reference-user]: https://example.com/profile",
  "[query-reference]: /issues?q=assignee:@octocat",
  "[balanced-reference]: /issues(a)?assignee=@octocat",
  "[next-line-reference]:",
  "  /users/@octocat",
  "Thanks [@reference-user], [query-reference], [balanced-reference], and [next-line-reference].",
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
  "- Keep https://example.com/a(b)?assignee=@octocat intact.",
  "- Keep ftp://example.com/a((b))?assignee=@octocat intact.",
  "- Keep //example.com/a(b)?assignee=@octocat intact.",
  "- Keep www.example.com/a(b)?assignee=@octocat intact.",
  "- Keep <//example.com/@octocat> intact.",
  "- Encoded attribution: &#64;\u2060encoded-user.",
  "- Inline code: `@inline-user`.",
  '- HTML code: <code data-owner="@octocat">npm install @scope/pkg</code>.',
  "<pre>",
  "npm install @pre-scope/pkg",
  "</pre>",
  "",
  `[${inertMention("reference-user")}]: https://example.com/profile`,
  "[query-reference]: /issues?q=assignee:@octocat",
  "[balanced-reference]: /issues(a)?assignee=@octocat",
  "[next-line-reference]:",
  "  /users/@octocat",
  `Thanks [${inertMention("reference-user")}], [query-reference], [balanced-reference], and [next-line-reference].`,
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
assert.equal(
  neutralizeImportedMarkdownMentions("https://example.com/a)@octocat"),
  `https://example.com/a)${inertMention("octocat")}`,
);
assert.equal(neutralizeImportedMarkdownMentions("<pre>\nnpm install @scope/pkg"), "<pre>\nnpm install @scope/pkg");

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
    return markdown === sourceMarkdown
      ? '<h3>Fixed</h3><p><a class="user-mention" href="/octocat">@octocat</a><a href="/kept">link</a></p>'
      : '<h3>Fixed</h3><p>No live mentions<a href="/kept">link</a></p>';
  },
});

assert.deepEqual(renderCalls, [
  {
    markdown: sourceMarkdown,
    context: "example/fork",
  },
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

await assert.rejects(
  buildIssueBody({
    release: {
      tag_name: "v9.9.10",
      published_at: "2026-08-20T13:00:00Z",
      body: "Thanks @octocat; keep https://example.com/@path intact.",
    },
    baseline: "v9.9.8",
    syncDate: "2026-08-19",
    upstream: "example/project",
    issueRepo: "example/fork",
    renderMarkdown: async (markdown) =>
      markdown.includes("\u2060")
        ? '<p>Thanks @octocat; keep <a href="https://example.com/@broken">link</a>.</p>'
        : '<p>Thanks <a class="user-mention" href="/octocat">@octocat</a>; keep <a href="https://example.com/@path">link</a>.</p>',
  }),
  /changed non-mention link targets/,
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
