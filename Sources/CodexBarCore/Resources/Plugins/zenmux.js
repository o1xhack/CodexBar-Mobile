defineProvider({
  id: "zenmux",
  name: "ZenMux",
  endpoints: ["https://zenmux.ai"],
  auth: { type: "bearer", secret: "ZENMUX_MANAGEMENT_API_KEY" },
  settings: [
    { key: "ZENMUX_MANAGEMENT_API_KEY", title: "Management API key", type: "secure" },
    { key: "INCLUDE_PAYG", title: "Include PAYG balance", type: "plain" },
  ],
  capabilities: ["http-status"],
  async fetchUsage(ctx) {
    const authenticationRejected = ctx.fail.authenticationExpired(
      "ZenMux rejected the Management API key. Standard inference API keys are not supported.",
    );
    async function get(path) {
      const response = await ctx.http.get(`https://zenmux.ai/api/v1/management/${path}`);
      if (response.status === 401 || response.status === 403) throw authenticationRejected;
      if (response.status < 200 || response.status >= 300)
        throw ctx.fail.apiFailure(`ZenMux Management API returned HTTP ${response.status}.`);
      let envelope;
      try {
        envelope = JSON.parse(response.bodyText);
      } catch {
        return fail();
      }
      if (envelope?.success !== true || !envelope.data) return fail();
      return envelope.data;
    }
    function fail() {
      throw ctx.fail.parseFailure("Could not parse ZenMux usage: invalid Management API response.");
    }
    const date = (value) => {
      if (value == null) return undefined;
      if (typeof value !== "string") return fail();
      if (
        !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?(?:Z|[+-]\d\d:\d\d)$/u.test(value) ||
        !Number.isFinite(Date.parse(value))
      )
        return undefined;
      return ctx.date.iso(value);
    };
    const amount = (value) => {
      if (Object.is(value, -0)) return "-0";
      if (Math.abs(value) >= 1e21) return String(BigInt(value));
      const fixed = value.toFixed(Number.isInteger(value) ? 0 : 2);
      // Preserve native printf's ties-to-even rounding for exact binary half-cent values.
      return Number.isInteger(value * 8) && Math.abs(value * 8) % 4 === 1
        ? fixed.slice(0, -1) + (Number(fixed.at(-1)) - 1)
        : fixed;
    };
    const window = (quota, minutes) => {
      if (!quota) return fail();
      for (const key of ["usage_percentage", "max_flows", "used_flows", "remaining_flows"])
        if (typeof quota[key] !== "number" || !Number.isFinite(quota[key])) return fail();
      return {
        usedPercent: Math.max(0, Math.min(100, quota.usage_percentage * 100)),
        windowMinutes: minutes,
        resetsAt: date(quota.resets_at),
        resetDescription: `${amount(quota.used_flows)} / ${amount(quota.max_flows)} flows`,
      };
    };
    const data = await get("subscription/detail");
    if (typeof data.plan?.tier !== "string" || typeof data.account_status !== "string") return fail();
    const capitalize = (value) => value.toLowerCase().replace(/\b\p{L}/gu, (letter) => letter.toUpperCase());
    const tier = data.plan.tier.trim();
    const status = data.account_status.trim();
    const plan = tier ? `${capitalize(tier)} plan` : undefined;
    const usage = {
      primary: window(data.quota_5_hour, 300),
      secondary: window(data.quota_7_day, 10080),
      subscriptionExpiresAt: date(data.plan.expires_at),
      identity: {
        loginMethod:
          !status || status.toLowerCase() === "healthy" ? plan : [plan, capitalize(status)].filter(Boolean).join(" · "),
      },
      dataConfidence: "exact",
    };
    if (ctx.settings.get("INCLUDE_PAYG") === "1") {
      try {
        const balance = await get("payg/balance");
        if (
          typeof balance.currency !== "string" ||
          balance.currency.trim().toLowerCase() !== "usd" ||
          typeof balance.total_credits !== "number" ||
          !Number.isFinite(balance.total_credits)
        )
          return usage;
        usage.cost = { used: balance.total_credits, currency: "USD", period: "ZenMux PAYG balance" };
      } catch (error) {
        if (error.transportClass === "cancelled" || error === authenticationRejected) throw error;
      }
    }
    return usage;
  },
});
