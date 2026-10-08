defineProvider({
  id: "langdock",
  name: "Langdock",
  endpoints: ["https://app.langdock.com"],
  settings: [],
  capabilities: ["browser-cookies", "http-status"],
  cookieDomains: ["langdock.com", "app.langdock.com"],
  cookiePolicy: {
    selection: "request-url",
    cache: "nonpersistent",
    imports: "access-gated",
    store: "selected-profile",
    requiredCookies: ["auth_token"],
    sessionURL: "https://app.langdock.com/api/trpc/usageSettings.getPersonalUsage",
  },
  snapshotPolicy: { percent: "preserve-overage" },
  async fetchUsage(ctx) {
    const fail = () => {
      throw ctx.fail.parseFailure("Langdock returned an unexpected personal usage response.");
    };
    const object = (value) => (value !== null && typeof value === "object" && !Array.isArray(value) ? value : fail());
    const percent = (value) => (typeof value === "number" && Number.isFinite(value) ? value : fail());
    const reset = (value) => {
      if (value === undefined || value === null) return undefined;
      if (typeof value !== "string") return fail();
      try {
        return ctx.date.iso(value);
      } catch (error) {
        void error;
        return fail();
      }
    };
    const denied = (code) => {
      if (code === "UNAUTHORIZED") {
        throw ctx.fail.authenticationExpired("The selected browser profile is no longer signed in to Langdock.");
      }
      if (code === "FORBIDDEN") throw ctx.fail.permissionDenied("Langdock denied access to personal usage.");
      if (code === "TOO_MANY_REQUESTS") throw ctx.fail.rateLimited("Langdock usage requests are rate limited.");
      if (code === "INTERNAL_SERVER_ERROR" || code === "TIMEOUT") {
        throw ctx.fail.providerUnavailable("Langdock personal usage is temporarily unavailable.");
      }
      throw ctx.fail.apiFailure("Langdock rejected the personal usage request.");
    };
    for await (const session of ctx.browser.sessions("app.langdock.com")) {
      const input = encodeURIComponent(JSON.stringify({ 0: { json: null, meta: { values: ["undefined"], v: 1 } } }));
      const response = await ctx.http.get(
        `https://app.langdock.com/api/trpc/usageSettings.getPersonalUsage?batch=1&input=${input}`,
        {
          cookieSession: session.id,
          headers: { Accept: "application/json", Referer: "https://app.langdock.com/settings/account/usage" },
        },
      );
      if (response.status === 401) return denied("UNAUTHORIZED");
      if (response.status === 403) return denied("FORBIDDEN");
      if (response.status === 429) return denied("TOO_MANY_REQUESTS");
      if (response.status >= 500) return denied("INTERNAL_SERVER_ERROR");
      if (response.status < 200 || response.status >= 300) {
        throw ctx.fail.apiFailure(`Langdock usage request failed with HTTP ${response.status}.`);
      }
      let raw;
      try {
        raw = JSON.parse(response.bodyText);
      } catch (error) {
        void error;
        return fail();
      }
      if (!Array.isArray(raw) || raw.length !== 1) return fail();
      const envelope = object(raw[0]);
      if (envelope.error !== undefined) {
        const code = object(object(object(envelope.error).json).data).code;
        return typeof code === "string" && code.length ? denied(code) : fail();
      }
      const payload = object(object(object(envelope.result).data).json);
      if (payload.hasIncludedUsageLimits !== undefined && typeof payload.hasIncludedUsageLimits !== "boolean") {
        return fail();
      }
      if (payload.hasIncludedUsageLimits === false || payload.planUsage == null) {
        return {
          details: [
            { title: "Usage", rows: [{ label: "Included limits", value: "No included usage limits available" }] },
          ],
          dataConfidence: "percentOnly",
        };
      }
      const plan = object(payload.planUsage);
      if (typeof plan.sessionUsageLimitsEnabled !== "boolean") return fail();
      const sessionReset = reset(plan.sessionResetsAt);
      const weeklyReset = reset(plan.weeklyResetsAt);
      return {
        primary: plan.sessionUsageLimitsEnabled
          ? { usedPercent: percent(plan.sessionUsagePercent), windowMinutes: 300, resetsAt: sessionReset }
          : undefined,
        secondary: { usedPercent: percent(plan.weeklyUsagePercent), windowMinutes: 10080, resetsAt: weeklyReset },
        dataConfidence: "percentOnly",
      };
    }
    throw ctx.fail.missingCredential("No Langdock session was found in the selected browser profile.");
  },
});
