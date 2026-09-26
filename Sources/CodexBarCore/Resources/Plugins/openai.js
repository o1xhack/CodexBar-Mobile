defineProvider({
  id: "openai",
  name: "OpenAI",
  endpoints: ["https://api.openai.com"],
  auth: { type: "bearer", secret: "OPENAI_API_KEY" },
  settings: [
    { key: "OPENAI_API_KEY", title: "API key", type: "secure" },
    { key: "OPENAI_PROJECT_ID", title: "Project ID", type: "plain" },
    { key: "OPENAI_HISTORY_DAYS", title: "History days", type: "plain" },
    { key: "OPENAI_ALLOW_BALANCE_FALLBACK", title: "Balance fallback", type: "plain" },
  ],

  async fetchUsage(ctx) {
    function fail(kind, message) {
      const error = ctx.fail[kind.replace(/-([a-z])/g, (_, letter) => letter.toUpperCase())](message);
      error.credentialRejected = kind === "authentication-expired";
      throw error;
    }
    function parseJSON(text) {
      try {
        return JSON.parse(text);
      } catch {
        throw ctx.fail.parseFailure("Failed to parse OpenAI API JSON");
      }
    }
    const projectID = ctx.settings.get("OPENAI_PROJECT_ID");
    const rawHistoryDays = Number(ctx.settings.get("OPENAI_HISTORY_DAYS") || "30");
    const historyDays = Number.isInteger(rawHistoryDays) ? Math.max(1, Math.min(365, rawHistoryDays)) : 30;

    function finite(value, field, optional) {
      if (optional && (value === null || value === undefined || value === "")) return null;
      const number = typeof value === "number" ? value : typeof value === "string" ? Number(value.trim()) : NaN;
      if (!Number.isFinite(number)) throw ctx.fail.parseFailure(`OpenAI ${field} must be numeric`);
      return number;
    }
    function integer(value, field, optional) {
      if (optional && (value === null || value === undefined)) return null;
      const number = typeof value === "number" ? value : NaN;
      if (!Number.isSafeInteger(number) || number < 0)
        throw ctx.fail.parseFailure(`OpenAI ${field} must be an integer`);
      return number;
    }
    function name(value, fallback) {
      if (value != null && typeof value !== "string") throw ctx.fail.parseFailure("Invalid OpenAI name");
      return typeof value === "string" && value.trim() ? value.trim() : fallback;
    }
    function usd(value) {
      return ctx.format.usd(Math.max(0, value));
    }
    function queryURL(path, range, groupBy, page) {
      const query = [
        `start_time=${range.start}`,
        `end_time=${range.end}`,
        "bucket_width=1d",
        `limit=${range.limit}`,
        `group_by=${encodeURIComponent(groupBy)}`,
      ];
      if (projectID) query.push(`project_ids=${encodeURIComponent(projectID)}`);
      if (page) query.push(`page=${encodeURIComponent(page)}`);
      return `https://api.openai.com${path}?${query.join("&")}`;
    }
    function ranges() {
      const today = ctx.date.now();
      today.setUTCHours(0, 0, 0, 0);
      let cursor = Math.floor(today.getTime() / 1000) - (historyDays - 1) * 86400;
      let remaining = historyDays;
      const result = [];
      while (remaining > 0) {
        const limit = Math.min(31, remaining);
        result.push({ start: cursor, end: cursor + limit * 86400, limit });
        cursor += limit * 86400;
        remaining -= limit;
      }
      return result;
    }
    async function pages(path, groupBy) {
      const buckets = [];
      for (const range of ranges()) {
        let page = null;
        const seen = new Set();
        for (let count = 0; count < 100; count += 1) {
          const response = await ctx.http.get(queryURL(path, range, groupBy, page), {
            timeoutSeconds: 20,
            retryPolicy: "transientIdempotent",
          });
          if (response.status !== 200) {
            fail(
              response.status === 401 || response.status === 403
                ? "authentication-expired"
                : response.status === 429
                  ? "rate-limited"
                  : "api-failure",
              `OpenAI API usage ${path} error: HTTP ${response.status}`,
            );
          }
          const body = parseJSON(response.bodyText);
          if (
            !body ||
            typeof body !== "object" ||
            Array.isArray(body) ||
            !Array.isArray(body.data) ||
            typeof body.has_more !== "boolean" ||
            (body.next_page != null && typeof body.next_page !== "string")
          ) {
            throw ctx.fail.parseFailure(`Failed to parse OpenAI ${path} page`);
          }
          buckets.push(...body.data);
          if (!body.has_more) break;
          if (typeof body.next_page !== "string" || !body.next_page.trim()) {
            throw ctx.fail.parseFailure(`OpenAI ${path} pagination cursor missing`);
          }
          page = body.next_page.trim();
          if (seen.has(page)) throw ctx.fail.parseFailure(`OpenAI ${path} pagination cursor repeated`);
          seen.add(page);
          if (count === 99) throw ctx.fail.parseFailure(`OpenAI ${path} pagination exceeded 100 pages`);
        }
      }
      return buckets;
    }

    try {
      const costBuckets = await pages("/v1/organization/costs", "line_item");
      const completionBuckets = await pages("/v1/organization/usage/completions", "model");
      const daily = new Map();
      function bucket(raw) {
        if (
          !raw ||
          typeof raw !== "object" ||
          Array.isArray(raw) ||
          !Number.isSafeInteger(raw.start_time) ||
          !Number.isSafeInteger(raw.end_time) ||
          !Array.isArray(raw.results)
        ) {
          throw ctx.fail.parseFailure("Failed to parse OpenAI usage bucket");
        }
        let value = daily.get(raw.start_time);
        if (!value) {
          value = {
            start: raw.start_time,
            end: raw.end_time,
            cost: 0,
            requests: 0,
            input: 0,
            cached: 0,
            output: 0,
            tokens: 0,
            models: new Map(),
            lines: new Map(),
          };
          daily.set(raw.start_time, value);
        }
        return value;
      }
      for (const raw of costBuckets) {
        const day = bucket(raw);
        for (const item of raw.results) {
          if (!item || typeof item !== "object" || Array.isArray(item))
            throw ctx.fail.parseFailure("Failed to parse OpenAI cost result");
          if (
            item.amount != null &&
            (typeof item.amount !== "object" ||
              Array.isArray(item.amount) ||
              (item.amount.currency != null && typeof item.amount.currency !== "string"))
          ) {
            throw ctx.fail.parseFailure("Invalid OpenAI cost amount");
          }
          const amount = item.amount ? finite(item.amount.value, "cost amount", true) || 0 : 0;
          day.cost += amount;
          const line = name(item.line_item, "API");
          day.lines.set(line, (day.lines.get(line) || 0) + amount);
        }
      }
      for (const raw of completionBuckets) {
        const day = bucket(raw);
        for (const item of raw.results) {
          if (!item || typeof item !== "object" || Array.isArray(item))
            throw ctx.fail.parseFailure("Failed to parse OpenAI completion result");
          const input = integer(item.input_tokens, "input_tokens", true) || 0;
          const cached = integer(item.input_cached_tokens, "input_cached_tokens", true) || 0;
          const audioInput = integer(item.input_audio_tokens, "input_audio_tokens", true) || 0;
          const output = integer(item.output_tokens, "output_tokens", true) || 0;
          const audioOutput = integer(item.output_audio_tokens, "output_audio_tokens", true) || 0;
          const requests = integer(item.num_model_requests, "num_model_requests", true) || 0;
          const tokens = input + audioInput + output + audioOutput;
          day.requests += requests;
          day.input += input + audioInput;
          day.cached += cached;
          day.output += output + audioOutput;
          day.tokens += tokens;
          const modelName = name(item.model, "Responses and Chat Completions");
          const model = day.models.get(modelName) || { requests: 0, tokens: 0, input: 0, cached: 0, output: 0 };
          model.requests += requests;
          model.tokens += tokens;
          model.input += input + audioInput;
          model.cached += cached;
          model.output += output + audioOutput;
          day.models.set(modelName, model);
        }
      }
      const days = Array.from(daily.values())
        .filter((day) => day.start * 1000 <= ctx.date.now().getTime())
        .sort((a, b) => a.start - b.start);
      const costDays =
        historyDays === 1
          ? days.filter(
              (day) => day.start * 1000 <= ctx.date.now().getTime() && ctx.date.now().getTime() < day.end * 1000,
            )
          : days.slice(-historyDays);
      const cost = costDays.reduce((sum, day) => sum + day.cost, 0);
      const identity = { loginMethod: projectID ? `Admin API: ${projectID}` : "Admin API" };
      if (projectID) identity.organization = `Project: ${projectID}`;
      return {
        usage: {
          cost: { used: cost, currency: "USD", period: historyDays === 1 ? "Today" : `Last ${historyDays} days` },
          identity,
        },
        sourceLabel: projectID ? "admin-api:project" : "admin-api",
        card: {
          openAIAPIUsage: {
            historyDays,
            projectID: projectID || null,
            daily: days.map((day) => ({
              startTime: day.start,
              endTime: day.end,
              costUSD: day.cost,
              requests: day.requests,
              inputTokens: day.input,
              cachedInputTokens: day.cached,
              outputTokens: day.output,
              totalTokens: day.tokens,
              lineItems: Array.from(day.lines, ([name, costUSD]) => ({ name, costUSD })).sort(
                (a, b) => b.costUSD - a.costUSD || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0),
              ),
              models: Array.from(day.models, ([name, model]) => ({
                name,
                requests: model.requests,
                inputTokens: model.input,
                cachedInputTokens: model.cached,
                outputTokens: model.output,
                totalTokens: model.tokens,
              })).sort((a, b) => b.totalTokens - a.totalTokens || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0)),
            })),
          },
        },
      };
    } catch (usageError) {
      if (ctx.settings.get("OPENAI_ALLOW_BALANCE_FALLBACK") !== "1") throw usageError;
      try {
        const response = await ctx.http.get("https://api.openai.com/v1/dashboard/billing/credit_grants");
        if (response.status === 401)
          fail(
            "authentication-expired",
            "OpenAI rejected this key for credit balance access (HTTP 401). Use an organization Admin API key for usage; project and service-account keys do not provide organization usage access.",
          );
        if (response.status === 403)
          fail(
            "permission-denied",
            "OpenAI API credit balance endpoint returned HTTP 403. Use a legacy/user API key with billing access; project keys may not expose credit grants.",
          );
        if (response.status !== 200) fail("api-failure", `OpenAI API credit balance error: HTTP ${response.status}`);
        const body = parseJSON(response.bodyText);
        if (!body || typeof body !== "object" || Array.isArray(body)) throw usageError;
        if (![body.total_granted, body.total_used, body.total_available].every((value) => typeof value === "number"))
          throw ctx.fail.parseFailure("Invalid OpenAI credit balance totals");
        const granted = finite(body.total_granted, "total_granted", false);
        const used = finite(body.total_used, "total_used", false);
        const available = finite(body.total_available, "total_available", false);
        if (
          body.grants != null &&
          (!body.grants ||
            typeof body.grants !== "object" ||
            Array.isArray(body.grants) ||
            !Array.isArray(body.grants.data))
        ) {
          throw ctx.fail.parseFailure("Invalid OpenAI credit grants");
        }
        for (const grant of body.grants?.data || []) {
          if (
            !grant ||
            typeof grant !== "object" ||
            Array.isArray(grant) ||
            [grant.grant_amount, grant.used_amount, grant.expires_at].some(
              (value) => value != null && (typeof value !== "number" || !Number.isFinite(value)),
            )
          ) {
            throw ctx.fail.parseFailure("Invalid OpenAI credit grant");
          }
        }
        const futureExpiries =
          body.grants && Array.isArray(body.grants.data)
            ? body.grants.data
                .map((item) => item && finite(item.expires_at, "expires_at", true))
                .filter((value) => value !== null && value * 1000 > ctx.date.now().getTime())
                .sort((a, b) => a - b)
            : [];
        const resetsAt = futureExpiries.length ? ctx.date.unixSeconds(futureExpiries[0]) : null;
        const primary = {
          usedPercent: granted > 0 ? ctx.pct(used, granted) : available > 0 ? 0 : 100,
          resetDescription: `${usd(available)} available`,
        };
        if (resetsAt) primary.resetsAt = resetsAt;
        const cost = { used: Math.max(0, used), limit: Math.max(0, granted), currency: "USD", period: "API credits" };
        if (resetsAt) cost.resetsAt = resetsAt;
        return {
          usage: { primary, cost, identity: { loginMethod: `API balance: ${usd(available)}` } },
          sourceLabel: "billing-api",
        };
      } catch (balanceError) {
        throw usageError.credentialRejected === true ? balanceError : usageError;
      }
    }
  },
});
