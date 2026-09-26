defineProvider({
  id: "moonshot",
  name: "Moonshot / Kimi Open Platform",
  endpoints: ["https://api.moonshot.ai", "https://api.moonshot.cn"],
  auth: { type: "bearer", secret: "MOONSHOT_API_KEY" },
  settings: [
    { key: "MOONSHOT_API_KEY", title: "API key", type: "secure" },
    { key: "BASE_URL", title: "Resolved regional API origin", type: "plain" },
  ],
  capabilities: ["http-status"],
  async fetchUsage(ctx) {
    const origin = ctx.settings.get("BASE_URL");
    if (origin !== "https://api.moonshot.ai" && origin !== "https://api.moonshot.cn") {
      throw ctx.fail.apiFailure("Invalid Moonshot API region.");
    }
    let response;
    try {
      response = await ctx.http.get(`${origin}/v1/users/me/balance`, {
        headers: { Accept: "application/json" },
      });
    } catch (error) {
      if (error.transportCode === -1011) {
        throw ctx.fail.networkFailure("Moonshot network error: Invalid response");
      }
      throw error;
    }
    if (response.status !== 200) throw ctx.fail.apiFailure(`Moonshot API error: HTTP ${response.status}`);
    const fail = (field) => {
      throw ctx.fail.parseFailure(`Failed to parse Moonshot response: ${field}`);
    };
    const object = (value, field) => {
      if (!value || typeof value !== "object" || Array.isArray(value)) return fail(field);
      return value;
    };
    let decoded;
    try {
      decoded = JSON.parse(response.bodyText);
    } catch (error) {
      void error;
      return fail("expected JSON");
    }
    const root = object(decoded, "expected a response object");
    if (typeof root.code !== "number" || !Number.isInteger(root.code)) return fail("code");
    if (typeof root.scode !== "string") return fail("scode");
    if (typeof root.status !== "boolean") return fail("status");
    const data = object(root.data, "data");
    const number = (key) => {
      const value = data[key];
      if (typeof value !== "number" || !Number.isFinite(value)) return fail(key);
      return value;
    };
    const balance = number("available_balance");
    const cash = number("cash_balance");
    number("voucher_balance");
    if (root.code !== 0 || !root.status) {
      throw ctx.fail.apiFailure(`Moonshot API error: code ${root.code}, scode ${root.scode}`);
    }
    const currency = origin === "https://api.moonshot.cn" ? "CNY" : "USD";
    const deficit = cash < 0 ? ` · ${ctx.format.currency(Math.abs(cash), currency)} in deficit` : "";
    return { identity: { loginMethod: `Balance: ${ctx.format.currency(balance, currency)}${deficit}` } };
  },
});
