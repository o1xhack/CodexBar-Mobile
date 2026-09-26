defineProvider({
  id: "fireworks",
  name: "Fireworks",
  endpoints: ["https://api.fireworks.ai"],
  auth: { type: "bearer", secret: "FIREWORKS_API_KEY" },
  settings: [
    { key: "FIREWORKS_API_KEY", title: "API key", type: "secure" },
    { key: "ACCOUNT_SLUG", title: "Account slug", type: "plain" },
  ],
  async fetchUsage(ctx) {
    function fail(kind, message) {
      throw ctx.fail[kind.replace(/-([a-z])/g, (_, letter) => letter.toUpperCase())](message);
    }
    const validSlug = (slug) => /^[A-Za-z0-9._-]+$/.test(slug) && slug !== "." && slug !== ".." && slug.length <= 256;
    const parse = (message) => fail("parse-failure", `Could not parse Fireworks usage: ${message}`);
    const object = (value) => value && typeof value === "object" && !Array.isArray(value);
    async function get(path) {
      const response = await ctx.http.get(`https://api.fireworks.ai/v1/accounts${path}`, { timeoutSeconds: 15 });
      if (response.status === 401 || response.status === 403) {
        fail(
          "authentication-expired",
          "Fireworks rejected the API key. Create a new key at app.fireworks.ai and update Settings.",
        );
      }
      if (response.status === 429)
        fail("rate-limited", "Fireworks rate limit exceeded. Usage will refresh on the next cycle.");
      if (response.status !== 200 && response.status !== 404)
        fail("api-failure", `Fireworks billing API returned HTTP ${response.status}.`);
      if (response.status === 200) {
        try {
          response.json = JSON.parse(response.bodyText);
        } catch {
          parse("invalid billing JSON");
        }
      }
      return response;
    }
    async function accounts() {
      const slugs = new Set();
      const seen = new Set();
      let token = "";
      for (let page = 0; page < 100; page += 1) {
        const response = await get(token ? `?pageToken=${encodeURIComponent(token)}` : "");
        if (response.status !== 200) fail("api-failure", `Fireworks billing API returned HTTP ${response.status}.`);
        const body = response.json;
        if (!object(body) || (body.accounts != null && !Array.isArray(body.accounts)))
          parse("invalid accounts response");
        for (const account of body.accounts || []) {
          if (!object(account)) parse("invalid account");
          for (const key of ["accountId", "id", "name"]) {
            if (account[key] != null && typeof account[key] !== "string") parse("invalid account name");
          }
          const name = [account.accountId, account.id, account.name].find((value) => value && value.trim());
          const slug = name && name.trim().split("/").filter(Boolean).pop();
          if (slug && validSlug(slug)) slugs.add(slug);
        }
        if (body.nextPageToken != null && typeof body.nextPageToken !== "string") parse("invalid page token");
        token = (body.nextPageToken || "").trim();
        if (!token) return Array.from(slugs).sort();
        if (seen.has(token)) parse("repeated accounts page token");
        seen.add(token);
      }
      parse("accounts pagination exceeded 100 pages");
    }
    function choose(slugs, configured) {
      if (!slugs.length) {
        fail(
          "api-failure",
          configured
            ? `Fireworks account slug '${configured}' not found for this API key. Leave the slug blank to auto-discover it, choose it in the app.fireworks.ai account switcher, or run 'firectl whoami'.`
            : "No Fireworks accounts are visible to this API key. Check the key in app.fireworks.ai or run 'firectl whoami'.",
        );
      }
      if (slugs.length !== 1) {
        fail(
          "api-failure",
          `This Fireworks API key can access multiple accounts: ${slugs.join(", ")}. Set the account slug in Settings or FIREWORKS_ACCOUNT_SLUG; find it in the app.fireworks.ai account switcher or with 'firectl whoami'.`,
        );
      }
      return slugs[0];
    }
    async function summary(slug) {
      const end = ctx.date.now();
      const start = new Date(end.getTime() - 30 * 86400000);
      const iso = (date) => date.toISOString().replace(/\.\d{3}Z$/, "Z");
      const response = await get(
        `/${slug}/billing/summary?startTime=${encodeURIComponent(iso(start))}&endTime=${encodeURIComponent(iso(end))}`,
      );
      if (response.status === 404) return null;
      const body = response.json;
      if (!object(body) || (body.lineItems != null && !Array.isArray(body.lineItems))) parse("invalid billing summary");
      let currency = null;
      let total = 0;
      for (const item of body.lineItems || []) {
        if (!object(item)) parse("invalid line item");
        const cost = item.totalCost;
        if (cost == null) continue;
        if (
          !object(cost) ||
          (cost.units != null && typeof cost.units !== "string") ||
          (cost.nanos != null && !Number.isSafeInteger(cost.nanos)) ||
          (cost.currencyCode != null && typeof cost.currencyCode !== "string")
        )
          parse("invalid rated cost");
        if (cost.units == null || !cost.units.trim() || cost.nanos == null || !cost.currencyCode?.trim()) continue;
        const units = Number(cost.units);
        if (!Number.isFinite(units)) continue;
        const code = cost.currencyCode.trim();
        if (currency === null) currency = code;
        if (code === currency) total += units + cost.nanos / 1e9;
      }
      if (!Number.isFinite(total)) parse("nonfinite spend");
      return currency === null ? { empty: true } : { cost: { used: total, currency, period: "Last 30 days" } };
    }
    const configured = (ctx.settings.get("ACCOUNT_SLUG") || "").trim();
    if (configured && !validSlug(configured)) {
      fail(
        "api-failure",
        `Invalid Fireworks account slug '${configured}'. Please double-check the account slug in Settings.`,
      );
    }
    let slug = configured || choose(await accounts(), "");
    let usage = await summary(slug);
    if (usage === null && configured) {
      slug = choose(await accounts(), configured);
      usage = await summary(slug);
    } else if (usage?.empty && configured && !(await accounts()).includes(slug)) {
      choose([], configured);
    }
    if (usage === null) fail("api-failure", "Fireworks billing API returned HTTP 404.");
    const discovered = slug !== configured;
    return {
      usage,
      sourceLabel: `api · ${slug}${discovered ? " (auto-discovered)" : ""}`,
      ...(discovered ? { persist: { ACCOUNT_SLUG: slug } } : {}),
    };
  },
});
