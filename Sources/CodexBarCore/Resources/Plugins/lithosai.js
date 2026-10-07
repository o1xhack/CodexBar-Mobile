function _nullishCoalesce(lhs, rhsFn) {
  if (lhs != null) {
    return lhs;
  } else {
    return rhsFn();
  }
}
defineProvider({
  id: "lithosai",
  name: "LithosAI",
  settings: [],
  endpoints: ["https://console.lithosai.cloud"],
  capabilities: ["browser-cookies", "http-status"],
  cookieDomains: ["console.lithosai.cloud"],
  cookiePolicy: {
    selection: "request-url",
    cache: "nonpersistent",
    imports: "access-gated",
    requiredCookies: ["__Host-console_session", "__Host-console_csrf"],
    headerEcho: {
      origin: "https://console.lithosai.cloud",
      cookie: "__Host-console_csrf",
      header: "X-Console-Csrf",
    },
  },
  async fetchUsage(ctx) {
    const domain = "console.lithosai.cloud";
    if (ctx.browser.availability(domain) === "off") throw ctx.fail.missingCredential("LithosAI cookies are disabled.");
    const invalid = (field) => {
      throw ctx.fail.parseFailure(`Could not parse LithosAI ${field}.`);
    };
    const object = (value) =>
      value !== null && typeof value === "object" && !Array.isArray(value) ? value : invalid("response object");
    const amount = (value) =>
      typeof value === "number" && Number.isSafeInteger(value) ? value : invalid("integer amount");
    const text = (value) => (typeof value === "string" && value.trim() ? value.trim() : undefined);
    const money = (value) => (value > 0 && value < 0.01 ? "Less than $0.01" : ctx.format.currency(value, "USD"));
    const sessionExpired = ctx.fail.authenticationExpired("LithosAI session expired. Sign in again.");
    let expired = false;
    for await (const session of ctx.browser.sessions(domain)) {
      const headers = {};
      const request = async (path) => {
        const response = await ctx.http.get(`https://${domain}${path}`, { cookieSession: session.id, headers });
        if (response.status === 401) throw sessionExpired;
        if (response.status === 403) throw ctx.fail.permissionDenied("LithosAI console access was denied.");
        if (response.status === 429) throw ctx.fail.rateLimited("LithosAI console requests are rate limited.");
        if (response.status >= 500) throw ctx.fail.providerUnavailable("LithosAI console is unavailable.");
        if (response.status !== 200) throw ctx.fail.apiFailure(`LithosAI console returned HTTP ${response.status}.`);
        let value;
        try {
          value = JSON.parse(response.bodyText);
        } catch (error) {
          void error;
          return invalid("JSON response");
        }
        return object(value);
      };
      try {
        const me = await request("/api/me");
        const organization = object(me.activeOrganization);
        const organizationID = _nullishCoalesce(text(organization.id), () => invalid("active organization"));
        if (!/^[A-Za-z0-9_-]{1,128}$/.test(organizationID)) return invalid("organization ID");
        headers["X-Organization-Id"] = organizationID;
        const billing = await request("/api/billing");
        const balance = amount(billing.balanceNanos) / 1e9;
        const rows = [{ label: "Balance", value: money(balance), usageValue: balance }];
        for (const [field, label, yes, no] of [
          ["hasCard", "Payment card", "Added", "Not added"],
          ["onHold", "Account status", "On hold", "Active"],
        ]) {
          if (typeof billing[field] !== "boolean") return invalid(field);
          rows.push({ label, value: billing[field] ? yes : no });
        }
        const snapshot = {
          cost: { used: balance, currency: "USD", period: "Prepaid credits" },
          details: [{ title: "Billing", rows }],
          identity: {
            email: text(object(me.user).email),
            organization: text(organization.name),
            loginMethod: "Browser session",
          },
          dataConfidence: "exact",
        };
        // Spend is optional: a broken report must not discard an authenticated balance.
        try {
          const end = ctx.date.now().toISOString().slice(0, 10);
          const start = `${end.slice(0, 7)}-01`;
          const report = await request(`/api/billing/spend?start=${start}&end=${end}`);
          if (report.start !== start || report.end !== end || !Array.isArray(report.days))
            return invalid("spend range");
          let today = 0;
          let month = 0;
          for (const raw of report.days) {
            const day = object(raw);
            if (typeof day.day !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(day.day) || day.day < start || day.day > end)
              return invalid("spend day");
            const nanos = amount(day.nanos);
            if (nanos < 0) return invalid("spend amount");
            month += nanos;
            if (day.day === end) today += nanos;
          }
          amount(month);
          rows.push({ label: "Today (UTC)", value: money(today / 1e9) });
          rows.push({ label: "This month (UTC)", value: money(month / 1e9) });
        } catch (error) {
          const failure = error;
          if (failure.transportClass === "cancelled" || error === sessionExpired) throw error;
          rows.push({ label: "Spend", value: "Unavailable" });
        }
        return snapshot;
      } catch (error) {
        if (error !== sessionExpired) throw error;
        ctx.browser.rejectCookie(domain, session);
        expired = true;
      }
    }
    if (expired)
      throw ctx.fail.authenticationExpired("LithosAI session expired. Sign in again or paste fresh cookies.");
    throw ctx.fail.missingCredential(
      `Sign in to console.lithosai.cloud. Supported browsers: ${ctx.browser.supportedBrowsers}. Or paste its Cookie header.`,
    );
  },
});
