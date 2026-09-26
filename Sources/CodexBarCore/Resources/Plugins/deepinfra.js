defineProvider({
  id: "deepinfra",
  name: "DeepInfra",
  endpoints: ["https://api.deepinfra.com"],
  auth: { type: "bearer", secret: "DEEPINFRA_API_KEY" },
  settings: [{ key: "DEEPINFRA_API_KEY", title: "API key", type: "secure" }],
  capabilities: ["http-status"],
  async fetchUsage(ctx) {
    async function get(path) {
      let response;
      try {
        response = await ctx.http.get(`https://api.deepinfra.com/payment/${path}`, {
          timeoutSeconds: 30,
          retryPolicy: "transientIdempotent",
        });
      } catch (error) {
        if (error.transportClass === "cancelled") throw error;
        throw ctx.fail.networkFailure(`DeepInfra network error: ${error.message}`);
      }
      if (response.status === 401)
        throw ctx.fail.authenticationExpired("DeepInfra API error: API key rejected (HTTP 401).");
      if (response.status === 403)
        throw ctx.fail.permissionDenied("DeepInfra API error: API key cannot access billing data (HTTP 403).");
      if (response.status !== 200) throw ctx.fail.apiFailure(`DeepInfra API error: HTTP ${response.status}`);
      return response.bodyText;
    }
    function fail() {
      throw ctx.fail.parseFailure("Failed to parse DeepInfra response: invalid billing data.");
    }
    const number = (value) => {
      if (typeof value !== "number" || !Number.isFinite(value)) return fail();
      return value;
    };
    const optional = (value, type) => {
      if (value != null && typeof value !== type) fail();
    };
    const checklistText = await get("checklist?compute_owed=true");
    const usageText = await get("usage?from=current");
    let checklist, usage;
    try {
      checklist = JSON.parse(checklistText);
      usage = JSON.parse(usageText);
    } catch {
      return fail();
    }
    if (!checklist || !usage || !Array.isArray(usage.months)) return fail();
    const recent = Math.max(0, number(checklist.recent));
    const balance = number(checklist.stripe_balance) + recent;
    if (!Number.isFinite(balance)) return fail();
    if (checklist.limit != null) number(checklist.limit);
    optional(checklist.suspended, "boolean");
    optional(checklist.suspend_reason, "string");
    optional(usage.initial_month, "string");
    for (const month of usage.months) {
      if (!month || typeof month.period !== "string") return fail();
      number(month.total_cost);
    }
    // Checklist amounts are USD; the usage endpoint's total_cost is cents.
    const monthCost = usage.months.length ? Math.max(0, usage.months.at(-1).total_cost / 100) : recent;
    const usd = (value) => {
      if (value >= 1e21) return `$${BigInt(value)}.00`;
      const fixed = value.toFixed(2);
      // Native printf rounds exact binary half-cent ties to even; toFixed rounds them upward.
      const rounded =
        Number.isInteger(value * 8) && (value * 8) % 4 === 1 ? fixed.slice(0, -1) + (Number(fixed.at(-1)) - 1) : fixed;
      return `$${rounded}`;
    };
    const balanceText = balance > 0 ? `${usd(balance)} owed` : `${usd(Math.max(0, -balance))} available`;
    const reason = checklist.suspend_reason?.trim();
    const suspension = checklist.suspended ? (reason ? `Suspended: ${reason} · ` : "Suspended · ") : "";
    return {
      primary: {
        usedPercent: checklist.suspended || balance >= 0 ? 100 : 0,
        resetDescription: `${suspension}${balanceText} · ${usd(monthCost)} spent this month`,
      },
      cost:
        checklist.limit > 0
          ? { used: recent, limit: checklist.limit, currency: "USD", period: "Billing cycle" }
          : undefined,
      identity: {},
      dataConfidence: "exact",
    };
  },
});
