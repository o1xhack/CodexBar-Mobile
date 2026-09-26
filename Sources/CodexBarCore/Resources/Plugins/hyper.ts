defineProvider({
  id: "hyper",
  name: "Charm Hyper",
  endpoints: ["https://hyper.charm.land"],
  capabilities: ["browser-cookies", "http-status"],
  cookieDomains: ["hyper.charm.land"],
  settings: [
    { key: "HYPER_API_KEY", title: "API key", type: "secure" },
    { key: "SOURCE_MODE", title: "Source", type: "plain" },
  ],
  async fetchUsage(ctx) {
    const domain = "hyper.charm.land";
    const key = ctx.settings.getSecret("HYPER_API_KEY");
    const webOnly = ctx.settings.get("SOURCE_MODE") === "web";
    const missing = (): never => {
      throw ctx.fail.missingCredential("Sign in to hyper.charm.land or configure a Charm Hyper API key.");
    };
    const request = (headers: Record<string, string>, timeoutSeconds = 10) =>
      ctx.http.get(`https://${domain}/v1/credits`, {
        headers,
        timeoutSeconds,
      });
    let response: CodexBarHTTPTextResponse | undefined;
    let session = false;
    if (ctx.browser.availability(domain) !== "off") {
      try {
        const cookie = await ctx.browser.cookieHeader(domain);
        session = true;
        response = await request({ Cookie: cookie }, 5);
      } catch (error) {
        if ((error as CodexBarHTTPError).transportClass === "cancelled") throw error;
        if (webOnly || !key) {
          if (session) throw ctx.fail.networkFailure("Charm Hyper session request failed.");
          return missing();
        }
      }
      if (
        response &&
        (response.status === 401 ||
          response.status === 403 ||
          (response.status >= 300 && response.status < 400) ||
          (response.status === 200 && response.headers["content-type"]?.toLowerCase().includes("text/html")))
      ) {
        ctx.browser.rejectCookie(domain);
        if (webOnly || !key) {
          throw ctx.fail.authenticationExpired(
            "Charm Hyper session expired. Sign in again or paste a fresh Cookie header.",
          );
        }
        response = undefined;
      }
    }
    if (!response) {
      if (webOnly || !key) return missing();
      response = await request({ Authorization: `Bearer ${key}` });
      session = false;
    }
    if (response.status === 401) throw ctx.fail.authenticationExpired("Charm Hyper API key rejected (HTTP 401).");
    if (response.status === 403)
      throw ctx.fail.permissionDenied("Charm Hyper API key cannot access credits (HTTP 403).");
    if (response.status === 429) throw ctx.fail.rateLimited("Charm Hyper credits requests are rate limited.");
    if (response.status >= 500) throw ctx.fail.providerUnavailable(`Charm Hyper API error: HTTP ${response.status}`);
    if (response.status !== 200) throw ctx.fail.apiFailure(`Charm Hyper API error: HTTP ${response.status}`);

    let payload: { balance?: unknown } | null;
    try {
      payload = JSON.parse(response.bodyText);
    } catch (error) {
      void error;
      throw ctx.fail.parseFailure("Charm Hyper credits response is not valid JSON.");
    }
    const balance = payload?.balance;
    if (typeof balance !== "number" || !Number.isFinite(balance) || balance < 0) {
      throw ctx.fail.parseFailure("Charm Hyper balance must be a non-negative number.");
    }
    return {
      details: [
        {
          title: "Hypercredits",
          rows: [
            {
              label: "Balance",
              value: `${ctx.format.number(balance, { maximumFractionDigits: 2 })} HC`,
              usageValue: balance,
            },
          ],
        },
      ],
      identity: { loginMethod: session ? "Browser session" : "API key" },
      dataConfidence: "exact",
    };
  },
});
