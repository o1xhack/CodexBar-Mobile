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
  id: "bifrost",
  name: "Bifrost",
  endpoints: [{ setting: "BIFROST_BASE_URL", policy: "https-or-private-network-http" }],
  auth: { type: "header", header: "x-bf-vk", secret: "BIFROST_API_KEY" },
  settings: [
    { key: "BIFROST_API_KEY", title: "Virtual key", type: "secure" },
    { key: "BIFROST_BASE_URL", title: "Base URL", type: "plain" },
  ],
  capabilities: ["http-status"],
  async fetchUsage(ctx) {
    const fail = (message) => {
      throw ctx.fail.parseFailure(`Bifrost: ${message}`);
    };
    const object = (value) => {
      if (!value || typeof value !== "object" || Array.isArray(value)) return fail("expected an object");
      return value;
    };
    const array = (value) => {
      if (value == null) return [];
      if (!Array.isArray(value)) return fail("expected an array");
      return value.map(object);
    };
    const text = (value) => {
      if (value == null) return undefined;
      if (typeof value !== "string") return fail("invalid string");
      return value.trim() || undefined;
    };
    const number = (value) => {
      if (value == null) return undefined;
      if (typeof value !== "number" || !Number.isFinite(value)) return fail("invalid number");
      return value;
    };
    const compare = (a, b) => (a < b ? -1 : a > b ? 1 : 0);
    const bounded = (value) => Array.from(value).slice(0, 120).join("");
    const labels = {
      "1h": "Hourly",
      "1d": "Daily",
      "1w": "Weekly",
      "1M": "Monthly",
      "1Q": "Quarterly",
      "1Y": "Yearly",
    };
    const units = {
      Y: 31536000,
      Q: 7776000,
      M: 2592000,
      w: 604800,
      d: 86400,
      h: 3600,
      m: 60,
      s: 1,
      ms: 0.001,
      us: 0.000001,
      µs: 0.000001,
      μs: 0.000001,
      ns: 0.000000001,
    };
    const duration = (raw) => {
      if (!raw) return undefined;
      const extended = raw.match(/^(\d+(?:\.\d+)?)([dwMQY])$/u);
      const parts = raw.match(/(?:\d+(?:\.\d*)?|\.\d+)(?:ns|us|µs|μs|ms|s|m|h)/gu);
      let seconds;
      if (extended) seconds = Number(extended[1]) * units[extended[2]];
      else if (parts && parts.join("") === raw) {
        seconds = parts.reduce((sum, part) => {
          const match = part.match(/^([\d.]+)(.+)$/u);
          return sum + Number(match[1]) * units[match[2]];
        }, 0);
      }
      return seconds !== undefined && Number.isFinite(seconds) && seconds > 0 ? seconds : undefined;
    };
    const timing = (reset, lastReset) => {
      const raw = text(reset),
        seconds = duration(raw),
        last = text(lastReset);
      // The quota endpoint omits the owner's calendar-alignment policy. Do not invent calendar resets.
      const fixed = raw !== undefined && !/[dwMQY]$/u.test(raw);
      let resetsAt;
      if (fixed && last && seconds) {
        const start = new Date(last).getTime(),
          period = seconds * 1000;
        const next = new Date(
          start + (Math.max(0, Math.floor((ctx.date.now().getTime() - start) / period)) + 1) * period,
        );
        if (Number.isFinite(next.getTime())) resetsAt = next;
      }
      const minutes = seconds === undefined ? 0 : Math.floor(seconds / 60);
      return {
        seconds,
        resetsAt,
        label: raw && Object.hasOwn(labels, raw) ? labels[raw] : undefined,
        windowMinutes: fixed && Number.isSafeInteger(minutes) && minutes > 0 ? minutes : undefined,
      };
    };
    const rawBase = ctx.settings.get("BIFROST_BASE_URL") || "";
    const [base, suffix = ""] = rawBase.split(/(?=[?#])/u, 2);
    let response;
    try {
      response = await ctx.http.get(`${base.replace(/\/+$/u, "")}/api/governance/virtual-keys/quota${suffix}`);
    } catch (error) {
      if (error.transportClass === "cancelled") throw error;
      throw ctx.fail.networkFailure("Bifrost quota request could not reach the configured gateway.");
    }
    const message = `Bifrost quota request failed (HTTP ${response.status}).`;
    if (response.status === 401) throw ctx.fail.authenticationExpired("Bifrost rejected the virtual key.");
    if (response.status === 403) throw ctx.fail.permissionDenied("Bifrost denied access to this virtual key's quota.");
    if (response.status === 429) throw ctx.fail.rateLimited(message);
    if (response.status >= 500) throw ctx.fail.providerUnavailable(message);
    if (response.status < 200 || response.status >= 300) throw ctx.fail.apiFailure(message);
    let decoded;
    try {
      decoded = JSON.parse(response.bodyText);
    } catch (error) {
      void error;
      return fail("invalid quota JSON");
    }
    const root = object(decoded);
    if (root.is_active != null && typeof root.is_active !== "boolean") return fail("invalid key activity");
    const scopes = [
      { id: "", body: root },
      ...array(root.provider_configs).map((body, index) => ({
        id: `provider-${index}-`,
        title: `Provider ${text(body.provider) || index + 1}`,
        body,
      })),
      ...array(root.model_configs).map((body, index) => ({
        id: `model-${index}-`,
        title: `Model ${[text(body.provider), text(body.model_name) || index + 1].filter(Boolean).join(" · ")}`,
        body,
      })),
    ];
    const budgets = scopes
      .flatMap((scope) =>
        array(scope.body.budgets).flatMap((budget) => {
          const id = text(budget.id);
          if (!id) return [];
          const amount = _nullishCoalesce(number(budget.override_amount), () => 0),
            mode = text(budget.override_mode);
          const cycles = _nullishCoalesce(number(budget.override_cycles_remaining), () => 0);
          if (!Number.isInteger(cycles)) return fail("invalid override cycles");
          const active = amount > 0 && (mode === "forever" || (mode === "cycles" && cycles > 0));
          const limit = _nullishCoalesce(number(budget.max_limit), () => 0) + (active ? amount : 0);
          if (!Number.isFinite(limit)) return fail("invalid effective budget");
          return [
            {
              id,
              scope,
              source: text(budget.source_name),
              limit,
              used: _nullishCoalesce(number(budget.current_usage), () => 0),
              timing: timing(budget.reset_duration, budget.last_reset),
              models: array(budget.per_model_usage),
            },
          ];
        }),
      )
      .sort(
        (a, b) =>
          _nullishCoalesce(a.timing.seconds, () => Infinity) - _nullishCoalesce(b.timing.seconds, () => Infinity) ||
          compare(a.id, b.id),
      );
    const limits = scopes.flatMap((scope) => {
      const components = array(scope.body.rate_limits);
      // rate_limit is a compatibility merge of these components, not another pool.
      const selected = components.length
        ? components
        : scope.body.rate_limit == null
          ? []
          : [object(scope.body.rate_limit)];
      return selected.map((limit, index) => ({ scope, limit, index }));
    });
    if (root.is_active === false && !budgets.length && !limits.length) {
      throw ctx.fail.permissionDenied("Bifrost virtual key is inactive and has no budgets or rate limits to display.");
    }
    const allWindows = budgets
      .filter((budget) => budget.limit > 0)
      .map((budget) => ({
        id: `bifrost-${budget.scope.id}budget-${budget.id}`,
        scope: budget.scope,
        title: bounded([budget.scope.title, budget.source || "Budget"].filter(Boolean).join(" · ")),
        window: {
          usedPercent: ctx.pct(budget.used, budget.limit),
          windowMinutes: budget.timing.windowMinutes,
          resetsAt: budget.timing.resetsAt,
          resetDescription: [
            _optionalChain([
              budget,
              "access",
              (_) => _.source,
              "optionalAccess",
              (_2) => _2.slice,
              "call",
              (_3) => _3(0, 24),
            ]),
            budget.timing.label,
            `${ctx.format.usd(budget.used)} / ${ctx.format.usd(budget.limit)}`,
          ]
            .filter(Boolean)
            .join(" · "),
        },
      }));
    const windows = allWindows.filter((window) => !window.scope.id);
    const extraWindows = [...windows.slice(2), ...allWindows.filter((window) => window.scope.id)].map(
      ({ id, title, window }) => ({ id, title, window }),
    );
    limits.forEach(({ scope, limit, index }) => {
      const source = text(limit.source_name);
      for (const [key, title] of [
        ["token", "Tokens"],
        ["request", "Requests"],
      ]) {
        const max = number(limit[`${key}_max_limit`]),
          used = _nullishCoalesce(number(limit[`${key}_current_usage`]), () => 0);
        const reset = text(limit[`${key}_reset_duration`]),
          known = max !== undefined && max > 0;
        // Last-reset timestamps are serialized even for unconfigured dimensions.
        if (!known && !reset) continue;
        const time = timing(reset, limit[`${key}_last_reset`]);
        extraWindows.push({
          id: `bifrost-${scope.id}${key}s-${index}`,
          title: bounded([scope.title, source, title].filter(Boolean).join(" ")),
          usageKnown: known,
          window: {
            usedPercent: known ? ctx.pct(used, max) : 0,
            windowMinutes: time.windowMinutes,
            resetsAt: time.resetsAt,
            resetDescription: time.label,
          },
        });
      }
    });
    if (root.is_active === false) {
      extraWindows.unshift({ id: "bifrost-key-inactive", title: "Key inactive", usageKnown: false, usedPercent: 0 });
    }
    const first = budgets.find((budget) => !budget.scope.id),
      details = [];
    const modelName = (raw) =>
      raw
        .replace(/^(us-gov|us|eu|apac|global)\./iu, "")
        .replace(
          /^(ai21|amazon|anthropic|cohere|deepseek|luma|meta|mistral|openai|qwen|stability|twelvelabs|writer)\./iu,
          "",
        )
        .replace(/-v\d+:\d+$/u, "")
        .replace(/(?:-|\s)(?:\d{8}|\d{4}-\d{2}-\d{2})$/u, "")
        .replace(/[ \t-]+$/u, "") || raw;
    const tokenCount = (value) => {
      const magnitude = Math.abs(value),
        sign = value < 0 ? "-" : "";
      for (const [threshold, divisor, unit] of [
        [999500000, 1e9, "B"],
        [999500, 1e6, "M"],
        [1000, 1000, "K"],
      ]) {
        if (magnitude >= threshold) {
          const scaled = magnitude / divisor;
          return sign + scaled.toFixed(scaled >= 10 ? 0 : 1).replace(/\.0$/u, "") + unit;
        }
      }
      return String(value);
    };
    const models = (_optionalChain([first, "optionalAccess", (_4) => _4.models]) || [])
      .map((model) => {
        const tokens = number(model.total_tokens);
        number(model.total_requests);
        return {
          raw: text(model.model) || "Model",
          provider: text(model.provider),
          cost: number(model.total_cost),
          tokens: tokens !== undefined && Math.abs(tokens) < 9223372036854775808 ? Math.trunc(tokens) : undefined,
        };
      })
      .filter((model) => (model.cost || 0) !== 0 || (model.tokens || 0) !== 0)
      .sort((a, b) => (b.cost || 0) - (a.cost || 0) || (b.tokens || 0) - (a.tokens || 0) || compare(a.raw, b.raw));
    if (models.length) {
      const visible = models.slice(0, 5),
        names = visible.map((model) => modelName(model.raw));
      const mixed = new Set(visible.map((model) => model.provider).filter(Boolean)).size > 1;
      const rows = visible.map((model, index) => ({
        label: bounded(
          [
            mixed ? model.provider : undefined,
            names.indexOf(names[index]) !== names.lastIndexOf(names[index]) ? model.raw : names[index],
          ]
            .filter(Boolean)
            .join(" · "),
        ),
        value: model.cost === undefined ? "—" : ctx.format.usd(model.cost),
        usageValue: model.cost,
        secondaryValue: model.tokens === undefined ? undefined : `${tokenCount(model.tokens)} tokens`,
      }));
      if (models.length > 5) rows.push({ label: "Other models", value: String(models.length - 5) });
      details.push({ title: "Models", rows });
    }
    if (budgets.length > 1 || budgets.some((budget) => budget.scope.id))
      details.push({
        title: "Budgets",
        rows: budgets.slice(0, 24).map((budget) => ({
          label: bounded([budget.scope.title, budget.source || `Budget ${budget.id}`].filter(Boolean).join(" · ")),
          value:
            budget.limit > 0
              ? `${ctx.format.usd(budget.used)} / ${ctx.format.usd(budget.limit)}`
              : ctx.format.usd(budget.used),
          secondaryValue: budget.timing.label,
          usageValue: budget.used,
          progress: budget.limit > 0 ? ctx.pct(budget.used, budget.limit) / 100 : undefined,
        })),
      });
    return {
      primary: _optionalChain([windows, "access", (_5) => _5[0], "optionalAccess", (_6) => _6.window]),
      secondary: _optionalChain([windows, "access", (_7) => _7[1], "optionalAccess", (_8) => _8.window]),
      extraWindows,
      details,
      cost: first
        ? {
            used: first.used,
            limit: Math.max(0, first.limit),
            currency: "USD",
            period: first.timing.label || (first.limit > 0 ? "Budget" : "Spend"),
            resetsAt: first.timing.resetsAt,
          }
        : undefined,
      identity: {
        email: text(root.virtual_key_name),
        organization: _optionalChain([first, "optionalAccess", (_9) => _9.source]),
        loginMethod: "api",
      },
    };
  },
});
