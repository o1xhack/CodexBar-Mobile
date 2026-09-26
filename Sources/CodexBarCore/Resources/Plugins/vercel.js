defineProvider({
  id: "vercel",
  name: "Vercel AI Gateway",
  endpoints: ["https://ai-gateway.vercel.sh"],
  auth: { type: "bearer", secret: "AI_GATEWAY_API_KEY" },
  settings: [{ key: "AI_GATEWAY_API_KEY", title: "AI Gateway API key", type: "secure" }],
  capabilities: ["http-status"],
  async fetchUsage(ctx) {
    const response = await ctx.http.get("https://ai-gateway.vercel.sh/v1/credits");
    const message = `Vercel AI Gateway returned HTTP ${response.status}.`;
    if (response.status === 401) throw ctx.fail.authenticationExpired(message);
    if (response.status === 403) throw ctx.fail.permissionDenied(message);
    if (response.status === 429) {
      const delay = Number(response.headers["retry-after"] ?? 1);
      throw ctx.fail.rateLimited(message, {
        retryAfterSeconds: Number.isFinite(delay) && delay >= 0 ? Math.min(delay, 10) : 1,
      });
    }
    if (response.status >= 500) throw ctx.fail.providerUnavailable(message);
    if (response.status !== 200) throw ctx.fail.apiFailure(message);
    function fail() {
      throw ctx.fail.parseFailure("Vercel AI Gateway returned an unrecognized credit balance.");
    }
    let data;
    try {
      data = JSON.parse(response.bodyText);
    } catch {
      return fail();
    }
    function money(value) {
      if (typeof value !== "string" || !/^-?\d+(?:\.\d+)?$/.test(value)) return fail();
      const amount = Number(value);
      if (!Number.isFinite(amount)) return fail();
      return amount;
    }
    const balance = money(data?.balance);
    const spent = money(data?.total_used);
    if (spent < 0) return fail();
    return {
      details: [
        {
          title: "Team credits",
          rows: [
            { label: "Available balance", value: ctx.format.usd(balance) },
            { label: "Lifetime spend", value: ctx.format.usd(spent) },
          ],
        },
      ],
      identity: { loginMethod: "API" },
      dataConfidence: "exact",
    };
  },
});
