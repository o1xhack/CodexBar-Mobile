defineProvider({
  id: "longcat",
  name: "LongCat",
  settings: [],
  endpoints: ["https://longcat.chat"],
  capabilities: ["browser-cookies", "http-status"],
  cookieDomains: ["longcat.chat", "www.longcat.chat"],
  cookiePolicy: { selection: "request-url", cache: "nonpersistent" },
  async fetchUsage(ctx) {
    type ObjectValue = Record<string, unknown>;
    const object = (value: unknown): ObjectValue | undefined =>
      value !== null && typeof value === "object" && !Array.isArray(value) ? (value as ObjectValue) : undefined;
    const number = (value: unknown): number | undefined => {
      if (typeof value === "number" || typeof value === "boolean") return Number(value);
      if (typeof value !== "string" || value.trim() === "") return undefined;
      if (/^[+-]?nan$/i.test(value)) return NaN;
      if (/^[+-]?inf(?:inity)?$/i.test(value)) return value.startsWith("-") ? -Infinity : Infinity;
      const parsed = Number(value);
      return Number.isNaN(parsed) ? undefined : parsed;
    };
    const text = (value: unknown): string | undefined =>
      typeof value === "string" || typeof value === "number" ? String(value) : undefined;
    const invalid = (message: string): never => {
      throw ctx.fail.parseFailure(`Invalid LongCat response: ${message}`);
    };
    const expired = () =>
      Object.assign(ctx.fail.authenticationExpired("LongCat session is invalid or expired. Sign in again."), {
        retrySession: true,
      });
    const domain = "longcat.chat";
    if (ctx.browser.availability(domain) === "off") throw ctx.fail.missingCredential("LongCat cookies are disabled.");
    const headers = {
      Accept: "application/json, text/plain, */*",
      Origin: "https://longcat.chat",
      Referer: "https://longcat.chat/platform/usage",
      "Accept-Language": "en-US,en;q=0.9",
      "User-Agent":
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36",
    };
    const unwrap = (body: string): ObjectValue => {
      let parsed: unknown;
      try {
        parsed = JSON.parse(body);
      } catch (error) {
        if (error instanceof SyntaxError) return invalid("not a JSON object");
        throw error;
      }
      const envelope = object(parsed) ?? invalid("not a JSON object");
      if ("code" in envelope) {
        const raw = number(envelope.code);
        if (raw === undefined || !Number.isFinite(raw) || raw >= 9223372036854775808 || raw < -9223372036854775808)
          return invalid("response code was not a valid integer");
        const code = Math.trunc(raw);
        if (code === 401 || code === 403) throw expired();
        if (code !== 0 && code !== 200)
          throw ctx.fail.apiFailure(text(envelope.message) ?? text(envelope.msg) ?? `LongCat code ${code}`);
      }
      return object("data" in envelope ? envelope.data : envelope) ?? invalid("data was not an object");
    };
    const expiry = (value: unknown): Date | undefined => {
      const numeric = number(value);
      let date: Date;
      if (numeric !== undefined && numeric > 1000000000) {
        date = new Date(numeric > 1000000000000 ? numeric : numeric * 1000);
      } else if (typeof value === "string") {
        const legacy = /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$/.exec(value);
        date = legacy
          ? new Date(+legacy[1], +legacy[2] - 1, +legacy[3], +legacy[4], +legacy[5], +legacy[6])
          : new Date(value);
      } else return undefined;
      return Number.isFinite(date.getTime()) ? date : undefined;
    };
    const whole = (value: number): string => {
      const truncated = Math.trunc(value);
      const plain = truncated.toFixed(0);
      if (!plain.includes("e")) return plain;
      const [coefficient, exponent] = plain.split("e+");
      const [integer, fraction = ""] = coefficient.split(".");
      return integer + fraction + "0".repeat(Number(exponent) - fraction.length);
    };
    let lastCredentialError: unknown;
    for await (const session of ctx.browser.sessions(domain)) {
      const request = async (path: string, post = false): Promise<ObjectValue> => {
        const options = { headers, cookieSession: session.id };
        let response: CodexBarHTTPTextResponse;
        try {
          response = post
            ? await ctx.http.post(`https://longcat.chat${path}`, { ...options, body: {} })
            : await ctx.http.get(`https://longcat.chat${path}`, options);
        } catch (error) {
          if ((error as { failureKind?: string }).failureKind === "missing-credential")
            throw Object.assign(ctx.fail.missingCredential("No LongCat cookies match this request."), {
              retrySession: true,
            });
          throw error;
        }
        if (response.status === 401 || response.status === 403 || (response.status >= 300 && response.status < 400))
          throw expired();
        if (response.status !== 200) throw ctx.fail.apiFailure(`LongCat HTTP ${response.status} for ${path}`);
        return unwrap(response.bodyText);
      };
      const optional = async (path: string, post = false): Promise<ObjectValue | undefined> => {
        try {
          return await request(path, post);
        } catch (error) {
          if ((error as CodexBarHTTPError).transportClass === "cancelled") throw error;
          return undefined;
        }
      };
      try {
        const account = await request("/api/v1/user-current");
        const summary = await optional("/api/pay/quota/metering/token-packs/summary", true);
        const lot = object(summary?.currentLot);
        let total: number | undefined;
        let used: number | undefined;
        if (text(lot?.status)?.toUpperCase() === "ACTIVE" && (number(lot?.totalToken) ?? 0) > 0) {
          total = number(lot?.totalToken);
          used = number(lot?.consumedToken) ?? 0;
        } else {
          const payload = await request("/api/lc-platform/v1/tokenUsage");
          const usage = object(payload.usage) ?? payload;
          total = number(usage.totalToken);
          if (total === undefined) return invalid("tokenUsage was missing totalToken");
          used = number(usage.usedToken) ?? total - (number(usage.availableToken) ?? total);
        }
        const fuel = await optional("/api/lc-platform/v1/pending-fuel-packages");
        const fuelTotal = number(fuel?.totalQuota);
        let remaining = 0;
        let sawRemaining = false;
        let reset: Date | undefined;
        for (const raw of Array.isArray(fuel?.list) ? fuel.list : []) {
          const pack = object(raw);
          const available = number(pack?.availableToken);
          if (available !== undefined) {
            remaining += available;
            sawRemaining = true;
          }
          const date = expiry(pack?.expireTime);
          if (date && (!reset || date < reset)) reset = date;
        }
        if (!sawRemaining) remaining = fuelTotal ?? 0;
        const primaryUsed = Math.max(0, used ?? 0);
        const fuelUsed = Math.max(0, (fuelTotal ?? 0) - remaining);
        const primary =
          total !== undefined && Number.isFinite(total) && total > 0 && Number.isFinite(primaryUsed)
            ? { usedPercent: ctx.pct(primaryUsed, total), resetDescription: `${whole(primaryUsed)}/${whole(total)}` }
            : undefined;
        const secondary =
          fuelTotal !== undefined &&
          Number.isFinite(fuelTotal) &&
          fuelTotal > 0 &&
          Number.isFinite(remaining) &&
          Number.isFinite(fuelUsed)
            ? {
                usedPercent: ctx.pct(fuelUsed, fuelTotal),
                resetsAt: reset,
                resetDescription: `Fuel pack: ${whole(remaining)}/${whole(fuelTotal)}`,
              }
            : undefined;
        return {
          empty: !primary && !secondary,
          primary,
          secondary,
          identity: { organization: text(account.name) ?? text(account.nickName) },
        };
      } catch (error) {
        if (!(error as { retrySession?: boolean }).retrySession) throw error;
        lastCredentialError = error;
        ctx.browser.rejectCookie(domain, session);
      }
    }
    throw lastCredentialError ?? ctx.fail.missingCredential("No LongCat session cookies found in browsers.");
  },
});
