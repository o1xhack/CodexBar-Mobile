#!/usr/bin/env node

import assert from "node:assert/strict";

import { buildIssueBody, neutralizeImportedMarkdownMentions } from "./upstream-release-monitor.mjs";

const wordJoiner = "\u2060";
const inertMention = (handle) => `@${wordJoiner}${handle}`;

function renderedFixture(mentionCount, links = ["/kept"]) {
  const mentions = Array.from(
    { length: mentionCount },
    (_, index) => `<a class="user-mention notranslate" href="/user-${index}">@user-${index}</a>`,
  ).join("");
  const ordinaryLinks = links.map((href) => `<a href="${href}">link</a>`).join("");
  return `<p>${mentions}${ordinaryLinks}</p>`;
}

function expectedInsertionPositions(source, expected) {
  const positions = [];
  let sourceIndex = 0;

  for (const character of expected) {
    if (character === wordJoiner) {
      positions.push(sourceIndex);
      continue;
    }
    assert.equal(character, source[sourceIndex]);
    sourceIndex += 1;
  }

  assert.equal(sourceIndex, source.length);
  return positions;
}

function makeFixtureRenderer(source, expected, contexts) {
  const acceptedPositions = expectedInsertionPositions(source, expected);

  return async (markdown, context) => {
    contexts.push(context);
    const trialPositions = [];
    let withoutJoiners = "";
    for (const character of markdown) {
      if (character === wordJoiner) {
        trialPositions.push(withoutJoiners.length);
      } else {
        withoutJoiners += character;
      }
    }
    assert.equal(withoutJoiners, source);
    const removedMentionCount = trialPositions.filter((position) => acceptedPositions.includes(position)).length;
    return renderedFixture(acceptedPositions.length - removedMentionCount);
  };
}

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
  "- Escaped literal backticks: \\`Thanks @escaped-user\\`.",
  '- HTML code: <code data-owner="@octocat">npm install @scope/pkg</code>.',
  "<pre>",
  "npm install @pre-scope/pkg",
  "</pre>",
  "",
  "    npm install @indented/pkg",
  "",
  "[@reference-user]: https://example.com/profile",
  "[query-reference]: /issues?q=assignee:@octocat",
  "[balanced-reference]: /issues(a)?assignee=@octocat",
  "[next-line-reference]:",
  "  /users/@octocat",
  "Thanks [@reference-user], [query-reference], [balanced-reference], and [next-line-reference].",
  "",
  "> [quoted-reference]: /users/@octocat",
  "> See [quoted-reference].",
  "",
  "> [!NOTE]",
  "> Alert attribution @alert-user.",
  "",
  "- item",
  "    Thanks @list-user.",
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
  "- Escaped literal backticks: \\`Thanks @escaped-user\\`.",
  '- HTML code: <code data-owner="@octocat">npm install @scope/pkg</code>.',
  "<pre>",
  "npm install @pre-scope/pkg",
  "</pre>",
  "",
  "    npm install @indented/pkg",
  "",
  "[@reference-user]: https://example.com/profile",
  "[query-reference]: /issues?q=assignee:@octocat",
  "[balanced-reference]: /issues(a)?assignee=@octocat",
  "[next-line-reference]:",
  "  /users/@octocat",
  "Thanks [@reference-user], [query-reference], [balanced-reference], and [next-line-reference].",
  "",
  "> [quoted-reference]: /users/@octocat",
  "> See [quoted-reference].",
  "",
  "> [!NOTE]",
  `> Alert attribution ${inertMention("alert-user")}.`,
  "",
  "- item",
  `    Thanks ${inertMention("list-user")}.`,
  "",
  "```text",
  "@fenced-user",
  "```",
  "",
  `[^1]: Footnote attribution ${inertMention("footnote-user")}.`,
].join("\n");

const fixtureContexts = [];
const neutralizedFixture = await neutralizeImportedMarkdownMentions(sourceMarkdown, {
  context: "example/fork",
  renderMarkdown: makeFixtureRenderer(sourceMarkdown, expectedMarkdown, fixtureContexts),
});
assert.equal(neutralizedFixture.markdown, expectedMarkdown);
assert.equal(neutralizedFixture.linkDriftDetected, false);
assert.equal(neutralizedFixture.classificationIncomplete, false);
assert.ok(fixtureContexts.every((context) => context === "example/fork"));

const idempotentFixture = await neutralizeImportedMarkdownMentions(expectedMarkdown, {
  context: "example/fork",
  renderMarkdown: async () => renderedFixture(0),
});
assert.equal(idempotentFixture.markdown, expectedMarkdown);

const crlfSource = "Thanks @octocat\r\n";
const crlfExpected = `Thanks ${inertMention("octocat")}\r\n`;
const crlfFixture = await neutralizeImportedMarkdownMentions(crlfSource, {
  context: "example/fork",
  renderMarkdown: makeFixtureRenderer(crlfSource, crlfExpected, []),
});
assert.equal(crlfFixture.markdown, crlfExpected);

const boundedTokens = Array.from({ length: 128 }, (_, index) => `@user-${index}`);
const boundedSource = boundedTokens.join(" ");
const boundedExpected = boundedTokens
  .map((token, index) => (index % 2 === 0 ? token.replace("@", `@${wordJoiner}`) : token))
  .join(" ");
const boundedContexts = [];
const boundedFixture = await neutralizeImportedMarkdownMentions(boundedSource, {
  context: "example/fork",
  renderMarkdown: makeFixtureRenderer(boundedSource, boundedExpected, boundedContexts),
});
assert.equal(boundedFixture.classificationIncomplete, true);
assert.equal(boundedFixture.markdown, boundedSource);
assert.ok(boundedFixture.renderCount <= 64);
assert.equal(boundedContexts.length, boundedFixture.renderCount);

const simpleSource = "Thanks @octocat.";
const simpleExpected = `Thanks ${inertMention("octocat")}.`;
const buildRenderCalls = [];
const body = await buildIssueBody({
  release: {
    tag_name: "v9.9.9",
    published_at: "2026-08-20T12:00:00Z",
    html_url: "https://github.com/example/project/releases/tag/v9.9.9",
    body: simpleSource,
  },
  baseline: "v9.9.8",
  syncDate: "2026-08-19",
  upstream: "example/project",
  issueRepo: "example/fork",
  renderMarkdown: async (markdown, context) => {
    buildRenderCalls.push({ markdown, context });
    return markdown === simpleSource ? renderedFixture(1) : renderedFixture(0);
  },
});

assert.equal(buildRenderCalls.length, 3);
assert.ok(buildRenderCalls.every((call) => call.context === "example/fork"));
assert.ok(body.includes(simpleExpected));
assert.ok(!body.includes(simpleSource));
assert.match(body, /https:\/\/github\.com\/example\/project\/releases\/tag\/v9\.9\.9/);
assert.match(body, /https:\/\/github\.com\/example\/fork\/blob\/mobile-dev\/version\.env/);

await assert.rejects(
  buildIssueBody({
    release: {
      tag_name: "v9.9.10",
      published_at: "2026-08-20T13:00:00Z",
      body: "@<!-- -->octocat",
    },
    baseline: "v9.9.8",
    syncDate: "2026-08-19",
    upstream: "example/project",
    issueRepo: "example/fork",
    renderMarkdown: async () => renderedFixture(1, []),
  }),
  /still contain a live GitHub mention/,
);

await assert.rejects(
  buildIssueBody({
    release: {
      tag_name: "v9.9.11",
      published_at: "2026-08-20T13:00:00Z",
      body: simpleSource,
    },
    baseline: "v9.9.8",
    syncDate: "2026-08-19",
    upstream: "example/project",
    issueRepo: "example/fork",
    renderMarkdown: async (markdown) =>
      markdown === simpleSource ? renderedFixture(1, ["/kept"]) : renderedFixture(0, ["/broken"]),
  }),
  /changed non-mention link targets/,
);

const safeObfuscatedBody = await buildIssueBody({
  release: {
    tag_name: "v9.9.12",
    published_at: "2026-08-20T14:00:00Z",
    body: "@<!-- -->octocat",
  },
  baseline: "v9.9.8",
  syncDate: "2026-08-19",
  upstream: "example/project",
  issueRepo: "example/fork",
  renderMarkdown: async () => renderedFixture(0, []),
});

assert.ok(safeObfuscatedBody.includes("@<!-- -->octocat"));
console.log("upstream release monitor mention tests passed");
