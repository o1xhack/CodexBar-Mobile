type GitKrakenQuota = { used: number; limit: number };

defineProvider({
  id: "gitkraken",
  name: "GitKraken AI",
  endpoints: ["https://api.gitkraken.dev"],
  auth: { type: "bearer", secret: "GITKRAKEN_API_TOKEN" },
  settings: [
    { key: "GITKRAKEN_API_TOKEN", title: "GitKraken access token", type: "secure" },
    { key: "GITKRAKEN_ORG_ID", title: "API organization ID", type: "plain" },
    { key: "CLIENT_VERSION", title: "Client version", type: "plain" },
  ],
  capabilities: ["http-status"],
  async fetchUsage(ctx) {
    const token = ctx.settings.getSecret("GITKRAKEN_API_TOKEN");
    if (!token) throw ctx.fail.missingCredential("Set a GitKraken access token in Settings or GITKRAKEN_API_TOKEN.");
    if (!/^[\x21-\x7e]{1,16384}$/.test(token)) {
      throw ctx.fail.authenticationExpired("Invalid GitKraken token. Paste only the value after Bearer.");
    }
    const organization = ctx.settings.get("GITKRAKEN_ORG_ID")?.trim();
    if (organization && !/^[\x21-\x7e]{1,256}$/.test(organization)) {
      throw ctx.fail.permissionDenied("Invalid GitKraken organization ID. Enter a single ID without whitespace.");
    }
    const headers: Record<string, string> = {
      "Client-Name": "CodexBar",
      "Client-Version": ctx.settings.get("CLIENT_VERSION") || "0.0.0",
      "User-Agent": "CodexBar",
    };
    if (organization) headers["gk-org-id"] = organization;
    const response = await ctx.http.get("https://api.gitkraken.dev/v1/ai-tasks/usage", { headers });
    if (response.status === 401)
      throw ctx.fail.authenticationExpired("GitKraken access token expired or was rejected.");
    if (response.status === 403)
      throw ctx.fail.permissionDenied("GitKraken denied access to this account or organization.");
    if (response.status === 429) {
      const delay = Number(response.headers["retry-after"] ?? 1);
      throw ctx.fail.rateLimited("GitKraken rate limited usage requests.", {
        retryAfterSeconds: Number.isFinite(delay) && delay >= 0 ? Math.min(delay, 10) : 1,
      });
    }
    if (response.status >= 500) throw ctx.fail.providerUnavailable("GitKraken usage is temporarily unavailable.");
    if (response.status !== 200) throw ctx.fail.apiFailure(`GitKraken returned HTTP ${response.status}.`);

    function fail(): never {
      throw ctx.fail.parseFailure("GitKraken returned an unrecognized usage response.");
    }
    function quota(value: unknown): GitKrakenQuota | null {
      if (!value || typeof value !== "object" || Array.isArray(value)) return null;
      const { used, limit } = value as GitKrakenQuota;
      if (
        typeof used !== "number" ||
        !Number.isFinite(used) ||
        used < 0 ||
        typeof limit !== "number" ||
        !Number.isFinite(limit) ||
        (limit < 0 && limit !== -1) ||
        (limit > 0 && !Number.isFinite((used / limit) * 100))
      )
        return null;
      return { used, limit };
    }
    let body;
    try {
      body = JSON.parse(response.bodyText);
    } catch (error) {
      void error;
      return fail();
    }
    const data = body?.data;
    const personal = quota(data);
    if (body?.error != null || !personal) return fail();
    if (
      typeof data.resetsOn !== "string" ||
      !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.test(data.resetsOn)
    )
      return fail();
    const resetsAt = new Date(data.resetsOn);
    if (!Number.isFinite(resetsAt.getTime())) return fail();
    const pool = quota(data.organization);
    const number = (value: number) => ctx.format.number(value, { maximumFractionDigits: 2 });
    function description(value: GitKrakenQuota): string {
      if (value.limit <= 0)
        return `${number(value.used)} credits used · ${value.limit === -1 ? "Unlimited" : "No allowance"}`;
      return `${number(value.used)} / ${number(value.limit)} credits used`;
    }
    const rows = [{ label: "Personal", value: description(personal) }];
    if (pool) {
      rows.push({ label: "Shared pool", value: description(pool) });
      // sharedUsed is a slice of the pool, never additional personal usage.
      const shared = data.sharedUsed;
      if (typeof shared === "number" && Number.isFinite(shared) && shared >= 0 && shared <= pool.used) {
        rows.push({ label: "Your shared usage", value: `${number(shared)} credits` });
        rows.push({ label: "Rest of organization", value: `${number(pool.used - shared)} credits` });
      }
    }
    if (personal.limit <= 0 && (!pool || pool.limit <= 0)) {
      rows.push({ label: "Reset", value: resetsAt.toISOString() });
    }
    function window(value: GitKrakenQuota | null) {
      return value && value.limit > 0
        ? { usedPercent: ctx.pct(value.used, value.limit), windowMinutes: 10080, resetsAt }
        : null;
    }
    return {
      primary: window(personal),
      secondary: window(pool),
      details: [{ title: "Weekly usage", rows }],
      identity: { loginMethod: "API" },
      dataConfidence: "exact",
    };
  },
});
