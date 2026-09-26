defineProvider({
  id: "devpass",
  name: "DevPass",
  endpoints: ["https://api.llmgateway.io"],
  auth: { type: "bearer", secret: "DEVPASS_API_KEY" },
  settings: [{ key: "DEVPASS_API_KEY", title: "DevPass API key", type: "secure" }],
  capabilities: ["http-status"],
  async fetchUsage(ctx) {
    const response = await ctx.http.get("https://api.llmgateway.io/v1/key");
    if (response.status === 401) throw ctx.fail.authenticationExpired("DevPass API key was rejected or is inactive.");
    if (response.status === 403) throw ctx.fail.permissionDenied("DevPass requires a regular gateway API key.");
    if (response.status === 429) {
      const delay = Number(response.headers["retry-after"] ?? 1);
      throw ctx.fail.rateLimited("DevPass usage requests are rate limited.", {
        retryAfterSeconds: Number.isFinite(delay) && delay >= 0 ? Math.min(delay, 10) : 1,
      });
    }
    if (response.status >= 500) throw ctx.fail.providerUnavailable("DevPass usage is temporarily unavailable.");
    if (response.status !== 200) throw ctx.fail.apiFailure(`DevPass returned HTTP ${response.status}.`);
    function fail(): never {
      throw ctx.fail.parseFailure("DevPass returned an unrecognized usage response.");
    }
    let body;
    try {
      body = JSON.parse(response.bodyText);
    } catch (error) {
      void error;
      return fail();
    }
    const data = body?.data;
    if (!data || !["none", "lite", "pro", "max"].includes(data.devPlan)) return fail();
    function money(key: string): number {
      const value = data[key];
      if (typeof value !== "string" || !/^\d+(?:\.\d+)?$/.test(value)) return fail();
      const number = Number(value);
      if (!Number.isFinite(number)) return fail();
      return number;
    }
    const keyUsed = money("usage");
    const keyLimit = data.limit === null ? null : money("limit");
    const keyRows = [{ label: "All-time key usage", value: ctx.format.usd(keyUsed) }];
    if (keyLimit !== null) keyRows.push({ label: "Key spending limit", value: ctx.format.usd(keyLimit) });
    if (data.devPlan === "none") {
      return {
        details: [{ title: "API key (all time)", rows: keyRows }],
        identity: { loginMethod: "Pay as you go" },
        dataConfidence: "exact",
      };
    }
    const used = money("devPlanCreditsUsed");
    const limit = money("devPlanCreditsLimit");
    const remaining = money("devPlanCreditsRemaining");
    const weeklyUsed = money("devPlanPremiumCreditsUsed");
    const weeklyLimit = money("devPlanPremiumWeeklyLimit");
    const reset = data.devPlanPremiumWeekResetsAt;
    let resetsAt: Date | null = null;
    if (reset !== null) {
      if (
        typeof reset !== "string" ||
        !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.test(reset)
      )
        return fail();
      resetsAt = new Date(reset);
      if (!Number.isFinite(resetsAt.getTime())) return fail();
    }
    return {
      primary: limit > 0 ? { usedPercent: ctx.pct(used, limit) } : null,
      secondary:
        weeklyLimit > 0 ? { usedPercent: ctx.pct(weeklyUsed, weeklyLimit), windowMinutes: 10080, resetsAt } : null,
      details: [
        {
          title: "DevPass credits",
          rows: [
            { label: "Cycle used", value: `${ctx.format.usd(used)} / ${ctx.format.usd(limit)}` },
            { label: "Cycle remaining", value: ctx.format.usd(remaining) },
            { label: "Premium weekly", value: `${ctx.format.usd(weeklyUsed)} / ${ctx.format.usd(weeklyLimit)}` },
          ],
        },
        { title: "API key (all time)", rows: keyRows },
      ],
      identity: { loginMethod: `DevPass ${data.devPlan.charAt(0).toUpperCase()}${data.devPlan.slice(1)}` },
      dataConfidence: "exact",
    };
  },
});
