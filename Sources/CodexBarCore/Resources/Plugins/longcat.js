function _nullishCoalesce(lhs, rhsFn) {
  if (lhs != null) {
    return lhs;
  } else {
    return rhsFn();
  }
}
function _optionalChain(ops) {
  let lastAccessLHS = undefined;
  let value = ops[0];
  let i = 1;
  while (i < ops.length) {
    const op = ops[i];
    const fn = ops[i + 1];
    i += 2;
    if ((op === "optionalAccess" || op === "optionalCall") && value == null) {
      return undefined;
    }
    if (op === "access" || op === "optionalAccess") {
      lastAccessLHS = value;
      value = fn(value);
    } else if (op === "call" || op === "optionalCall") {
      value = fn((...args) => value.call(lastAccessLHS, ...args));
      lastAccessLHS = undefined;
    }
  }
  return value;
}
defineProvider({
  id: "longcat",
  name: "LongCat",
  settings: [],
  endpoints: ["https://longcat.chat"],
  capabilities: ["browser-cookies", "http-status"],
  cookieDomains: ["longcat.chat", "www.longcat.chat"],
  cookiePolicy: { selection: "request-url", cache: "nonpersistent" },
  async fetchUsage(ctx) {
    const object = (value) =>
      value !== null && typeof value === "object" && !Array.isArray(value) ? value : undefined;
    const number = (value) => {
      if (typeof value === "number" || typeof value === "boolean") return Number(value);
      if (typeof value !== "string" || value.trim() === "") return undefined;
      if (/^[+-]?nan$/i.test(value)) return NaN;
      if (/^[+-]?inf(?:inity)?$/i.test(value)) return value.startsWith("-") ? -Infinity : Infinity;
      const parsed = Number(value);
      return Number.isNaN(parsed) ? undefined : parsed;
    };
    const text = (value) => (typeof value === "string" || typeof value === "number" ? String(value) : undefined);
    const invalid = (message) => {
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
    const unwrap = (body) => {
      let parsed;
      try {
        parsed = JSON.parse(body);
      } catch (error) {
        if (error instanceof SyntaxError) return invalid("not a JSON object");
        throw error;
      }
      const envelope = _nullishCoalesce(object(parsed), () => invalid("not a JSON object"));
      if ("code" in envelope) {
        const raw = number(envelope.code);
        if (raw === undefined || !Number.isFinite(raw) || raw >= 9223372036854775808 || raw < -9223372036854775808)
          return invalid("response code was not a valid integer");
        const code = Math.trunc(raw);
        if (code === 401 || code === 403) throw expired();
        if (code !== 0 && code !== 200)
          throw ctx.fail.apiFailure(
            _nullishCoalesce(
              _nullishCoalesce(text(envelope.message), () => text(envelope.msg)),
              () => `LongCat code ${code}`,
            ),
          );
      }
      return _nullishCoalesce(object("data" in envelope ? envelope.data : envelope), () =>
        invalid("data was not an object"),
      );
    };
    const expiry = (value) => {
      const numeric = number(value);
      let date;
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
    const whole = (value) => {
      const truncated = Math.trunc(value);
      const plain = truncated.toFixed(0);
      if (!plain.includes("e")) return plain;
      const [coefficient, exponent] = plain.split("e+");
      const [integer, fraction = ""] = coefficient.split(".");
      return integer + fraction + "0".repeat(Number(exponent) - fraction.length);
    };
    let lastCredentialError;
    for await (const session of ctx.browser.sessions(domain)) {
      const request = async (path, post = false) => {
        const options = { headers, cookieSession: session.id };
        let response;
        try {
          response = post
            ? await ctx.http.post(`https://longcat.chat${path}`, { ...options, body: {} })
            : await ctx.http.get(`https://longcat.chat${path}`, options);
        } catch (error) {
          if (error.failureKind === "missing-credential")
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
      const optional = async (path, post = false) => {
        try {
          return await request(path, post);
        } catch (error) {
          if (error.transportClass === "cancelled") throw error;
          return undefined;
        }
      };
      try {
        const account = await request("/api/v1/user-current");
        const summary = await optional("/api/pay/quota/metering/token-packs/summary", true);
        const lot = object(_optionalChain([summary, "optionalAccess", (_) => _.currentLot]));
        let total;
        let used;
        if (
          _optionalChain([
            text,
            "call",
            (_2) => _2(_optionalChain([lot, "optionalAccess", (_3) => _3.status])),
            "optionalAccess",
            (_4) => _4.toUpperCase,
            "call",
            (_5) => _5(),
          ]) === "ACTIVE" &&
          _nullishCoalesce(number(_optionalChain([lot, "optionalAccess", (_6) => _6.totalToken])), () => 0) > 0
        ) {
          total = number(_optionalChain([lot, "optionalAccess", (_7) => _7.totalToken]));
          used = _nullishCoalesce(number(_optionalChain([lot, "optionalAccess", (_8) => _8.consumedToken])), () => 0);
        } else {
          const payload = await request("/api/lc-platform/v1/tokenUsage");
          const usage = _nullishCoalesce(object(payload.usage), () => payload);
          total = number(usage.totalToken);
          if (total === undefined) return invalid("tokenUsage was missing totalToken");
          used = _nullishCoalesce(
            number(usage.usedToken),
            () => total - _nullishCoalesce(number(usage.availableToken), () => total),
          );
        }
        const fuel = await optional("/api/lc-platform/v1/pending-fuel-packages");
        const fuelTotal = number(_optionalChain([fuel, "optionalAccess", (_9) => _9.totalQuota]));
        let remaining = 0;
        let sawRemaining = false;
        let reset;
        for (const raw of Array.isArray(_optionalChain([fuel, "optionalAccess", (_10) => _10.list])) ? fuel.list : []) {
          const pack = object(raw);
          const available = number(_optionalChain([pack, "optionalAccess", (_11) => _11.availableToken]));
          if (available !== undefined) {
            remaining += available;
            sawRemaining = true;
          }
          const date = expiry(_optionalChain([pack, "optionalAccess", (_12) => _12.expireTime]));
          if (date && (!reset || date < reset)) reset = date;
        }
        if (!sawRemaining) remaining = _nullishCoalesce(fuelTotal, () => 0);
        const primaryUsed = Math.max(
          0,
          _nullishCoalesce(used, () => 0),
        );
        const fuelUsed = Math.max(0, _nullishCoalesce(fuelTotal, () => 0) - remaining);
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
          identity: { organization: _nullishCoalesce(text(account.name), () => text(account.nickName)) },
        };
      } catch (error) {
        if (!error.retrySession) throw error;
        lastCredentialError = error;
        ctx.browser.rejectCookie(domain, session);
      }
    }
    throw _nullishCoalesce(lastCredentialError, () =>
      ctx.fail.missingCredential("No LongCat session cookies found in browsers."),
    );
  },
});
