defineProvider({
  id: "atlascloud",
  name: "Atlas Cloud",
  endpoints: ["https://api.atlascloud.ai"],
  auth: { type: "bearer", secret: "ATLASCLOUD_API_KEY" },
  settings: [{ key: "ATLASCLOUD_API_KEY", title: "Atlas Cloud API key", type: "secure" }],
  capabilities: ["http-status"],
  async fetchUsage(ctx) {
    const response = await ctx.http.get("https://api.atlascloud.ai/public/v1/balance");
    const message = `Atlas Cloud returned HTTP ${response.status}.`;
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
      throw ctx.fail.parseFailure("Atlas Cloud returned an unrecognized USD account balance.");
    }
    let data;
    try {
      data = JSON.parse(response.bodyText);
    } catch {
      return fail();
    }
    const value = data?.available?.value;
    if (
      data?.object !== "balance" ||
      data.scope !== "account" ||
      data.available?.currency !== "usd" ||
      typeof value !== "string" ||
      !/^-?\d+(?:\.\d+)?$/.test(value)
    )
      return fail();
    const balance = Number(value);
    if (!Number.isFinite(balance)) return fail();
    return {
      details: [{ title: "Account balance", rows: [{ label: "Available balance", value: ctx.format.usd(balance) }] }],
      identity: { loginMethod: "API" },
      dataConfidence: "exact",
    };
  },
});
