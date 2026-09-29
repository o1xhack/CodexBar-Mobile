defineProvider({
  id: "abacus",
  name: "Abacus AI",
  endpoints: ["https://apps.abacus.ai"],
  settings: [
    { key: "REQUEST_TIMEOUT", title: "Request timeout", type: "plain" },
    { key: "MAX_COOKIE_CANDIDATES", title: "Cookie candidate limit", type: "plain" },
  ],
  capabilities: ["browser-cookies", "http-status"],
  cookieDomains: ["apps.abacus.ai"],
  async fetchUsage(ctx) {
    const domain = "apps.abacus.ai";
    const timeout = Number(ctx.settings.get("REQUEST_TIMEOUT") || 15);
    const billingBudget = Math.min(timeout, 5);
    const maximumCandidates = Number(ctx.settings.get("MAX_COOKIE_CANDIDATES") || 5);
    const manual = ctx.browser.availability(domain) === "manual";
    const auth = () => ctx.fail.authenticationExpired("Unauthorized. Please log in to Abacus AI.");
    let clearCookie = false;
    const parseFailure = (message) => {
      clearCookie = true;
      throw ctx.fail.parseFailure(`Could not parse Abacus AI usage: ${message}`);
    };
    const parse = (response) => {
      if (response.status === 401 || response.status === 403) {
        clearCookie = true;
        throw auth();
      }
      if (response.status !== 200) throw ctx.fail.apiFailure(`Abacus AI API error: HTTP ${response.status}`);
      let root;
      try {
        root = JSON.parse(response.bodyText);
      } catch (error) {
        void error;
        return parseFailure("invalid JSON");
      }
      if (!root || typeof root !== "object" || Array.isArray(root)) return parseFailure("invalid response");
      if (root.success !== true || !root.result || typeof root.result !== "object" || Array.isArray(root.result)) {
        const message = typeof root.error === "string" ? root.error.toLowerCase() : "unknown error";
        if (/expired|session|login|authenticate|unauthorized|unauthenticated|forbidden/.test(message)) {
          clearCookie = true;
          throw auth();
        }
        return parseFailure(message);
      }
      return root.result;
    };
    // NumberFormatter's credit display uses decimal half-even rounding before grouping.
    const credits = (value) => {
      const digits = value >= 1000 ? 0 : 1;
      const scale = 10 ** digits;
      const scaled = value * scale;
      const lower = Math.floor(scaled);
      const rounded = scaled - lower === 0.5 ? lower + Math.abs(lower % 2) : Math.round(scaled);
      return ctx.format.number(rounded / scale, { maximumFractionDigits: digits });
    };
    let lastError;
    let attempts = 0;
    for await (const session of ctx.browser.sessions(domain)) {
      clearCookie = false;
      try {
        const headers = { Cookie: session.header, Accept: "application/json", "Content-Type": "application/json" };
        const response = await ctx.http.getWithOptional(
          `https://${domain}/api/_getOrganizationComputePoints`,
          {
            url: `https://${domain}/api/_getBillingInfo`,
            method: "POST",
            body: {},
            headers,
            timeoutSeconds: billingBudget,
          },
          { headers, timeoutSeconds: timeout, optionalBudgetSeconds: billingBudget },
        );
        const points = parse(response);
        const total = points.totalComputePoints;
        const left = points.computePointsLeft;
        if (
          typeof total !== "number" ||
          !Number.isFinite(total) ||
          typeof left !== "number" ||
          !Number.isFinite(left)
        ) {
          return parseFailure("Missing credit fields in compute points response");
        }
        let billing = {};
        try {
          if (response.optional) billing = parse(response.optional);
        } catch (error) {
          void error;
          // Billing failure never invalidates the session that just returned the required credits.
          clearCookie = false;
        }
        let resetsAt;
        if (typeof billing.nextBillingDate === "string" && /^\d{4}-\d{2}-\d{2}T/.test(billing.nextBillingDate)) {
          try {
            resetsAt = ctx.date.iso(billing.nextBillingDate);
          } catch (error) {
            void error;
          }
        }
        const used = total - left;
        const windowMinutes = resetsAt
          ? Math.max(
              1,
              Math.trunc((resetsAt.getTime() - ctx.date.addMonths(resetsAt, -1, ctx.env.timeZone).getTime()) / 60000),
            )
          : 30 * 24 * 60;
        return {
          primary: {
            usedPercent: total > 0 ? ctx.pct(used, total) : 0,
            windowMinutes,
            resetsAt,
            resetDescription: `${credits(used)} / ${credits(total)} credits`,
          },
          identity: { loginMethod: typeof billing.currentTier === "string" ? billing.currentTier : undefined },
        };
      } catch (error) {
        if (manual || error.transportClass === "cancelled") throw error;
        if (clearCookie) ctx.browser.rejectCookie(domain, session);
        lastError = error;
        if (++attempts >= maximumCandidates) break;
      }
    }
    if (lastError) throw lastError;
    throw ctx.fail.missingCredential(
      "No Abacus AI session found. Please log in to apps.abacus.ai in your browser or paste a Cookie header in manual mode.",
    );
  },
});
