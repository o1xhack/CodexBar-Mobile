type ChutesObject = Record<string, unknown>;

const chutesKeys = {
  rollingPayloadKeys: ["rolling", "rollingwindow", "rolling4h", "fourhour", "fourhourusage", "window4h"],
  monthlyPayloadKeys: ["monthly", "monthlyusage", "subscription", "subscriptionusage", "billingperiod"],
  quotaContainerKeys: ["quotas", "quota", "quotausage", "limits", "usage", "entries", "subscriptionusage"],
  labelKeys: ["label", "name", "title", "type", "quotatype", "period", "window", "windowname", "chuteid"],
  limitKeys: [
    "limit",
    "cap",
    "max",
    "maximum",
    "quota",
    "quotalimit",
    "monthlycap",
    "monthlylimit",
    "requestlimit",
    "tokenlimit",
    "hardlimit",
    "total",
  ],
  usedKeys: [
    "used",
    "usage",
    "usedamount",
    "consumed",
    "consumedamount",
    "current",
    "currentusage",
    "requests",
    "requestcount",
    "tokens",
    "tokenusage",
    "monthlyusage",
  ],
  remainingKeys: ["remaining", "available", "balance", "left", "remainingamount", "availableamount"],
  percentUsedKeys: ["percentused", "usagepercent", "usedpercent", "utilization", "utilizationpercent"],
  percentRemainingKeys: ["percentremaining", "remainingpercent"],
  resetKeys: [
    "resetat",
    "resetsat",
    "resettime",
    "nextresetat",
    "renewsat",
    "renewalat",
    "periodend",
    "currentperiodend",
    "expiresat",
    "windowend",
    "endtime",
  ],
  unitKeys: ["unit", "units", "currency", "quotaunit"],
  activeKeys: ["active", "isactive", "subscriptionactive", "hassubscription"],
  statusKeys: ["status", "state", "subscriptionstatus"],
  planKeys: ["planname", "plan", "tier", "subscriptionplan", "subscriptiontier"],
  windowMinuteKeys: ["windowminutes", "periodminutes", "durationminutes"],
  windowHourKeys: ["windowhours", "periodhours", "durationhours"],
  windowDayKeys: ["windowdays", "perioddays", "durationdays"],
  windowSecondKeys: ["windowseconds", "periodseconds", "durationseconds"],
  windowStringKeys: ["window", "period", "interval", "duration"],
};

function chutesObject(value: unknown): ChutesObject | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? (value as ChutesObject) : undefined;
}

function chutesValue(object: ChutesObject, keys: string[]): unknown {
  for (const key of keys) {
    const entry = Object.keys(object).find((candidate) => candidate.toLowerCase().replace(/[^a-z0-9]/g, "") === key);
    if (entry !== undefined) return object[entry];
  }
}

function chutesNumber(value: unknown): number | undefined {
  const cleaned = typeof value === "string" ? value.trim().replace(/[,$%]/g, "") : value;
  if (cleaned === "" || cleaned == null || !["string", "number", "boolean"].includes(typeof cleaned)) return;
  const number = Number(cleaned);
  return Number.isFinite(number) ? number : undefined;
}

function chutesString(value: unknown): string | undefined {
  if (typeof value === "boolean") return value ? "1" : "0";
  return typeof value === "string" || typeof value === "number" ? String(value).trim() || undefined : undefined;
}

function chutesDate(value: unknown): Date | undefined {
  const numeric = typeof value === "number" || (typeof value === "string" && value.trim() !== "") ? Number(value) : NaN;
  const date = Number.isFinite(numeric)
    ? new Date(numeric > 0 ? numeric * (numeric > 1e10 ? 1 : 1000) : NaN)
    : new Date(typeof value === "string" ? value.trim() : NaN);
  return Number.isFinite(date.getTime()) ? date : undefined;
}

function chutesMinutes(payload: ChutesObject): number | undefined {
  const units: [string[], number][] = [
    [chutesKeys.windowMinuteKeys, 1],
    [chutesKeys.windowHourKeys, 60],
    [chutesKeys.windowDayKeys, 1440],
    [chutesKeys.windowSecondKeys, 1 / 60],
  ];
  let minutes: number | undefined;
  for (const [keys, multiplier] of units) {
    const number = chutesNumber(chutesValue(payload, keys));
    if (number !== undefined) {
      minutes = number * multiplier;
      break;
    }
  }
  if (minutes === undefined) {
    const text = chutesString(chutesValue(payload, chutesKeys.windowStringKeys))?.toLowerCase().replace(/ /g, "");
    const match = text?.match(/^([+]?(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?)(.+)$/);
    if (match && Number(match[1]) > 0) {
      const unit = match[2];
      const multiplier = /^(min|m$)/.test(unit)
        ? 1
        : /^(hour|hr|h$)/.test(unit)
          ? 60
          : /^(day|d$)/.test(unit)
            ? 1440
            : /^(month|mo$)/.test(unit)
              ? 43200
              : NaN;
      minutes = Number(match[1]) * multiplier;
    }
  }
  if (minutes === undefined) return;
  const rounded = Math.sign(minutes) * Math.round(Math.abs(minutes));
  return rounded > 0 && rounded < 9223372036854775808 ? rounded : undefined;
}

type ChutesWindow = {
  label?: string;
  unit: string;
  used?: number;
  limit?: number;
  remaining?: number;
  explicitPercent?: number;
  rate: CodexBarRateWindow;
};
type ChutesParsed = {
  rolling?: ChutesWindow;
  monthly?: ChutesWindow;
  fallback: ChutesWindow[];
  plan?: string;
  active?: boolean;
  renewal?: Date;
};

function chutesQuota(payload: ChutesObject, label?: string, minutes?: number): ChutesWindow | undefined {
  const read = (keys: string[]) => chutesNumber(chutesValue(payload, keys));
  const limit = read(chutesKeys.limitKeys),
    used = read(chutesKeys.usedKeys),
    remaining = read(chutesKeys.remainingKeys);
  const normalize = (value: number) => Math.max(0, Math.min(100, Math.abs(value) < 1 ? value * 100 : value));
  const percentUsed = read(chutesKeys.percentUsedKeys),
    percentRemaining = read(chutesKeys.percentRemainingKeys);
  const total = limit ?? (used !== undefined && remaining !== undefined ? used + remaining : undefined);
  const consumed = used ?? (total !== undefined && remaining !== undefined ? total - remaining : undefined);
  const percent =
    percentUsed !== undefined
      ? normalize(percentUsed)
      : percentRemaining !== undefined
        ? 100 - normalize(percentRemaining)
        : total !== undefined && total > 0 && consumed !== undefined
          ? (consumed / total) * 100
          : undefined;
  if (percent === undefined) return;
  const unit = chutesString(chutesValue(payload, chutesKeys.unitKeys)) ?? "credits";
  const describedUsed =
    used ?? (limit !== undefined && remaining !== undefined ? Math.max(0, limit - remaining) : undefined);
  const amount = (value: number) => {
    const rounded = Math.sign(value) * Math.round(Math.abs(value));
    if (Math.abs(value - rounded) < 0.0001 && Math.abs(rounded) < 9223372036854775808)
      return BigInt(rounded).toString();
    // toFixed switches to exponential notation at 1e21; retain the full represented integer.
    if (Math.abs(value) >= 1e21) return BigInt(value).toString();
    const absolute = Math.abs(value),
      fraction = absolute % 1;
    // Binary-exact cent ties round to even in native printf, unlike toFixed.
    if (fraction === 0.125 || fraction === 0.625) {
      return `${value < 0 ? "-" : ""}${BigInt(Math.trunc(absolute))}.${fraction === 0.125 ? "12" : "62"}`;
    }
    return value.toFixed(2).replace(/\.?0+$/, "");
  };
  return {
    label: chutesString(chutesValue(payload, chutesKeys.labelKeys)) ?? label,
    unit,
    used,
    limit,
    remaining,
    // Selection compares quota data before projecting it into display windows.
    explicitPercent: percentUsed !== undefined || percentRemaining !== undefined ? percent : undefined,
    rate: {
      usedPercent: Math.max(0, Math.min(100, percent)),
      windowMinutes: chutesMinutes(payload) ?? minutes,
      resetsAt: chutesDate(chutesValue(payload, chutesKeys.resetKeys)),
      resetDescription:
        limit !== undefined && limit > 0 && describedUsed !== undefined
          ? `${amount(describedUsed)}/${amount(limit)} ${unit}`
          : undefined,
    },
  };
}

function chutesParse(value: unknown): ChutesParsed {
  const root = chutesObject(value) ?? (Array.isArray(value) ? { quotas: value } : {});
  const data = chutesObject(chutesValue(root, ["data", "result"])) ?? root;
  const dictionary = (keys: string[]) => chutesObject(chutesValue(root, keys)) ?? chutesObject(chutesValue(data, keys));
  const subscription = dictionary(["subscription", "subscriptionusage", "currentsubscription", "plan"]) ?? {};
  const context = (keys: string[], convert: (value: unknown) => unknown) =>
    convert(chutesValue(root, keys)) ?? convert(chutesValue(data, keys)) ?? convert(chutesValue(subscription, keys));
  const windows: ChutesWindow[] = [];
  const seen = new Set<string>();
  const canonical = (value: unknown): string => {
    if (value instanceof Date) return value.toISOString();
    if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
    const object = chutesObject(value);
    return object
      ? `{${Object.keys(object)
          .sort()
          .map((key) => `${JSON.stringify(key)}:${canonical(object[key])}`)
          .join(",")}}`
      : JSON.stringify(value);
  };
  const collect = (value: unknown) => {
    if (Array.isArray(value)) {
      value.forEach(collect);
      return;
    }
    const object = chutesObject(value);
    if (!object) return;
    const quota = chutesQuota(object),
      key = canonical(object);
    if (quota && !seen.has(key)) {
      seen.add(key);
      windows.push(quota);
    }
    Object.values(object).forEach(collect);
  };
  [
    chutesValue(root, chutesKeys.quotaContainerKeys),
    chutesValue(data, chutesKeys.quotaContainerKeys),
    data,
    root,
  ].forEach(collect);
  const kind = (window: ChutesWindow) => {
    const label = `${window.label ?? ""} ${window.unit}`.toLowerCase();
    if (/rolling|4h|4 h|4-hour|four hour|four-hour/.test(label) || window.rate.windowMinutes === 240) return "rolling";
    if (/month|billing|subscription/.test(label) || (window.rate.windowMinutes ?? 0) >= 40320) return "monthly";
  };
  const rollingPayload = dictionary(chutesKeys.rollingPayloadKeys),
    monthlyPayload = dictionary(chutesKeys.monthlyPayloadKeys);
  const rolling =
    (rollingPayload && chutesQuota(rollingPayload, "4-hour quota", 240)) ?? windows.find((w) => kind(w) === "rolling");
  const monthly =
    (monthlyPayload && chutesQuota(monthlyPayload, "Monthly quota", 43200)) ??
    windows.find((w) => kind(w) === "monthly");
  const bool = (value: unknown): boolean | undefined => {
    if (typeof value === "boolean") return value;
    if (typeof value === "number") return value !== 0;
    if (typeof value !== "string") return;
    const text = value.trim().toLowerCase();
    if (["true", "1", "yes", "active"].includes(text)) return true;
    if (["false", "0", "no", "inactive", "none"].includes(text)) return false;
  };
  let active = context(chutesKeys.activeKeys, bool) as boolean | undefined;
  if (active === undefined) {
    const status = (context(chutesKeys.statusKeys, chutesString) as string | undefined)?.toLowerCase() ?? "";
    if (status.includes("active") && !status.includes("inactive")) active = true;
    else if (/free|inactive|cancel|none|expired/.test(status)) active = false;
  }
  return {
    rolling,
    monthly,
    fallback: windows.filter((w) => canonical(w) !== canonical(rolling) && canonical(w) !== canonical(monthly)),
    plan: context(chutesKeys.planKeys, chutesString) as string | undefined,
    active,
    renewal: context(chutesKeys.resetKeys, chutesDate) as Date | undefined,
  };
}

function chutesSnapshot(parsed: ChutesParsed): CodexBarUsageSnapshot {
  const rolling = parsed.rolling && { ...parsed.rolling.rate, windowMinutes: parsed.rolling.rate.windowMinutes ?? 240 };
  const monthly = parsed.monthly && {
    ...parsed.monthly.rate,
    windowMinutes: parsed.monthly.rate.windowMinutes ?? 43200,
  };
  const fallback = parsed.fallback.map((window) => window.rate);
  const primary = rolling ?? (!monthly ? fallback[0] : undefined);
  const secondary = monthly ?? (rolling ? fallback[0] : primary ? fallback[1] : undefined);
  return {
    empty: true,
    primary,
    secondary,
    subscriptionRenewsAt: parsed.renewal ?? monthly?.resetsAt,
    identity: {
      loginMethod:
        parsed.plan ??
        (parsed.active === false
          ? "No active subscription"
          : parsed.active === undefined && !primary && !secondary
            ? "No usage data"
            : undefined),
    },
  };
}

defineProvider({
  id: "chutes",
  name: "Chutes",
  endpoints: [{ setting: "BASE_URL", policy: "https" }],
  auth: { type: "bearer", secret: "CHUTES_API_KEY" },
  capabilities: ["http-status"],
  settings: [
    { key: "BASE_URL", title: "API URL", type: "plain" },
    { key: "CHUTES_API_KEY", title: "API key", type: "secure" },
  ],
  async fetchUsage(ctx) {
    const base = (ctx.settings.get("BASE_URL") || "https://api.chutes.ai").match(/^([^?#]*)(.*)$/)!;
    const get = async (path: string): Promise<unknown> => {
      const response = await ctx.http.get(`${base[1].replace(/\/+$/, "")}/users/me/${path}${base[2]}`, {
        timeoutSeconds: 15,
      });
      if (response.status === 401 || response.status === 403) {
        throw ctx.fail.authenticationExpired("Chutes API key was rejected. Check the API key in Settings.");
      }
      if (response.status < 200 || response.status >= 300)
        throw ctx.fail.apiFailure(`Chutes usage API error: HTTP ${response.status}`);
      try {
        const value = JSON.parse(response.bodyText);
        if (!chutesObject(value) && !Array.isArray(value)) throw new Error("Expected an object or array");
        return value;
      } catch (error) {
        void error;
        throw ctx.fail.parseFailure("Chutes usage parse error: invalid JSON.");
      }
    };
    const subscription = chutesParse(await get("subscription_usage"));
    const keepRequiredError = (error: unknown) => {
      // Optional quota detail must never conceal revoked credentials or a cancelled refresh.
      if (
        (error as CodexBarHTTPError).transportClass === "cancelled" ||
        (error as Error).message.includes("Chutes API key was rejected")
      )
        throw error;
    };
    if (!subscription.rolling || !subscription.monthly) {
      try {
        const raw = await get("quotas"),
          root = chutesObject(raw);
        const list = [raw, root?.quotas, root?.data, chutesObject(root?.data)?.quotas].find(Array.isArray);
        let quotas = chutesParse(raw);
        if (Array.isArray(list) && list.some(chutesObject)) {
          const enriched: ChutesObject[] = [];
          for (const item of list) {
            const definition = chutesObject(item);
            if (!definition) continue;
            const id = [definition.chute_id, definition.chuteId, definition.id].map(chutesString).find(Boolean);
            let usage: ChutesObject | undefined;
            if (id) {
              try {
                const result = chutesObject(await get(`quota_usage/${encodeURIComponent(id)}`));
                usage = chutesObject(result?.data) ?? chutesObject(result?.result) ?? result;
              } catch (error) {
                keepRequiredError(error);
              }
            }
            enriched.push({ ...definition, ...usage });
          }
          const parsed = chutesParse({ quotas: enriched }),
            snapshot = chutesSnapshot(parsed);
          if (snapshot.primary || snapshot.secondary) quotas = parsed;
        }
        const snapshot = chutesSnapshot(quotas);
        if (snapshot.primary || snapshot.secondary) {
          subscription.rolling ??= quotas.rolling;
          subscription.monthly ??= quotas.monthly;
          subscription.fallback.push(...quotas.fallback);
        }
      } catch (error) {
        keepRequiredError(error);
      }
    }
    return chutesSnapshot(subscription);
  },
});
