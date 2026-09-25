---
summary: "llmman provider notes: local daemon address, optional API key, and loaded-model memory usage."
read_when:
  - Adding or modifying the llmman provider
  - Debugging llmman daemon reachability or API-key rejection
  - Adjusting llmman menu labels or memory mapping
---

# llmman Provider

[llmman](https://github.com/llmmanorg/llmman) runs models locally (and routes to hosted providers) behind an
OpenAI- and Anthropic-compatible daemon, `llmman serve`. CodexBar reads that daemon's own node report to show
how much of its model memory the loaded models occupy.

## Features

- **Memory bar**: loaded model weights as a share of the daemon's model memory (for example, `10.0 GB of 40.0 GB`).
  Memory frees as idle models unload after their `keep_alive`; there is no quota reset.
- **Loaded models**: each loaded model with its weight size, largest first.
- **Store summary**: loaded and stored model counts and total sizes, plus the daemon version.
- **Optional API key**: only needed when the daemon requires keys (`LLMMAN_API_KEYS`).

## Setup

1. Start the daemon: `llmman serve` (any `llmman run` or `llmman launch` also starts it).
2. Open **Settings → Providers** and enable **llmman**.
3. The default address is `http://127.0.0.1:17434`. Set **Base URL** (or `LLMMAN_HOST`) for another port or host.
4. If the daemon requires keys, paste one into **API key** or set `LLMMAN_API_KEY`.

From the CLI:

```sh
codexbar usage --provider llmman
```

## How it works

- The bundled TypeScript plugin fetches `GET /llmman/node` (`memory`, `loaded`, `stored`, all in bytes) and,
  best effort, `GET /api/version`. Both are `llmman serve`'s own routes; no inference is run.
- The key, when set, is sent as `Authorization: Bearer <key>`, the header the `llmman` CLI itself uses.
- Like `LLMMAN_HOST`, a scheme-less host uses HTTP and defaults to port 17434; an explicit port is preserved.
  For example, `localhost` becomes `http://localhost:17434`, and `0.0.0.0:18000` connects to
  `http://127.0.0.1:18000`. Explicit `http://` and `https://` URLs retain their standard port defaults.
- HTTP is limited to loopback, private-network and `.local` hosts; public hosts need HTTPS. Embedded credentials,
  query strings (including `?probe=1`), and fragments (including `#x`) are rejected before fetching. Trailing slashes
  are removed, and an OpenAI-style `/v1` suffix is ignored when constructing daemon requests.
- A daemon that reports no model memory omits the bar but still lists its models.
- Sizes use decimal units, as `llmman list` and `llmman ps` print them.

## Troubleshooting

### “llmman is not reachable at …”

The daemon is not running at that address. Run `llmman serve`, or fix **Base URL**.

### “llmman requires an API key”

The daemon was started with `LLMMAN_API_KEYS`. Set one of those keys in **API key** or `LLMMAN_API_KEY`.

### “… is not an llmman daemon”

The address answered, but not with `/llmman/node`: it is another server or an older llmman.
