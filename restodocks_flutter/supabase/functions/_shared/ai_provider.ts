/**
 * Общий слой вызова ИИ. Поддерживаются: DeepSeek, Groq, Gemini, GigaChat, OpenRouter, Mistral, Cerebras, OpenAI, Claude.
 * Переменные:
 * - AI_PROVIDER = глобально для всех (если задан)
 * - AI_PROVIDER_TTK = общий провайдер ТТК (legacy fallback)
 * - AI_PROVIDER_TTK_PARSE = парсинг ТТК (ai-parse-tech-cards-pdf, ai-recognize-tech-card, ai-recognize-tech-cards-batch)
 * - AI_PROVIDER_TTK_CREATE = создание ТТК с ИИ (новый поток генерации рецептов)
 * - AI_PROVIDER_NUTRITION = КБЖУ (ai-refine-nutrition)
 * - AI_PROVIDER_PRODUCT = продукты (ai-normalize, ai-find-duplicates, ai-verify, ai-recognize-product, ai-parse-product-list)
 * - AI_PROVIDER_CHECKLIST = чеклисты (ai-generate-checklist)
 * - DEEPSEEK_API_KEY — DeepSeek
 * - GROQ_API_KEY — Groq (free tier)
 * - GEMINI_API_KEY — Google AI Studio
 * - GIGACHAT_AUTH_KEY / GIGACHAT_API_KEY — GigaChat (Base64 client_id:client_secret)
 * - OPENROUTER_API_KEY — OpenRouter (много бесплатных моделей)
 * - MISTRAL_API_KEY — Mistral La Plateforme (free tier)
 * - CEREBRAS_API_KEY — Cerebras (free tier, быстрая генерация)
 * - OPENAI_API_KEY, ANTHROPIC_API_KEY
 * chatText с fallback: при ошибке пробует следующий провайдер.
 */

const GROQ_URL = "https://api.groq.com/openai/v1/chat/completions";
const DEEPSEEK_URL = "https://api.deepseek.com/chat/completions";
const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";
const MISTRAL_URL = "https://api.mistral.ai/v1/chat/completions";
const CEREBRAS_URL = "https://api.cerebras.ai/v1/chat/completions";
const GIGACHAT_AUTH_URL = "https://ngw.devices.sberbank.ru:9443/api/v2/oauth";
const GIGACHAT_CHAT_URL = "https://gigachat.devices.sberbank.ru/api/v1/chat/completions";
const GIGACHAT_SCOPE = "GIGACHAT_API_PERS";
const OPENAI_URL = "https://api.openai.com/v1/chat/completions";
const GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models";
const CLAUDE_URL = "https://api.anthropic.com/v1/messages";

export type Message = { role: "system" | "user" | "assistant"; content: string };
type UsageStats = { inputTokens: number; outputTokens: number; totalTokens: number };
type ChatResult = {
  content: string;
  provider: TextProvider;
  model: string;
  usage: UsageStats;
  latencyMs: number;
};

let gigachatToken: string | null = null;
let gigachatExpiresAt = 0;

async function getGigaChatToken(authKey: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (gigachatToken && gigachatExpiresAt > now + 60) return gigachatToken;
  const res = await fetch(GIGACHAT_AUTH_URL, {
    method: "POST",
    headers: {
      "Authorization": `Basic ${authKey}`,
      "Content-Type": "application/x-www-form-urlencoded",
      "RqUID": crypto.randomUUID(),
    },
    body: new URLSearchParams({ scope: GIGACHAT_SCOPE }).toString(),
  });
  if (!res.ok) {
    const t = await res.text();
    throw new Error(`GigaChat auth: ${res.status} ${t}`);
  }
  const data = (await res.json()) as { access_token?: string; expires_at?: number };
  gigachatToken = data.access_token ?? null;
  gigachatExpiresAt = data.expires_at ?? now + 30 * 60;
  if (!gigachatToken) throw new Error("GigaChat: no access_token");
  return gigachatToken;
}

export type TextProvider = "deepseek" | "groq" | "gigachat" | "openai" | "gemini" | "claude" | "openrouter" | "mistral" | "cerebras";

const PROVIDER_NAMES: TextProvider[] = ["deepseek", "groq", "openai", "gigachat", "gemini", "claude", "openrouter", "mistral", "cerebras"];

export type AIContext = "ttk" | "ttk_parse" | "ttk_create" | "nutrition" | "product" | "checklist";

function toInt(value: unknown): number {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : 0;
}

function parseUsage(raw: unknown): UsageStats {
  const usage = (raw && typeof raw === "object") ? raw as Record<string, unknown> : {};
  const inputTokens = toInt(
    usage.prompt_tokens ??
      usage.input_tokens ??
      usage.promptTokenCount ??
      usage.inputTokenCount,
  );
  const outputTokens = toInt(
    usage.completion_tokens ??
      usage.output_tokens ??
      usage.candidatesTokenCount ??
      usage.outputTokenCount,
  );
  const totalTokens = toInt(
    usage.total_tokens ??
      usage.totalTokenCount ??
      (inputTokens + outputTokens),
  );
  return {
    inputTokens,
    outputTokens,
    totalTokens: totalTokens > 0 ? totalTokens : inputTokens + outputTokens,
  };
}

function defaultRatePerM(provider: TextProvider, model: string): { input: number; output: number } {
  const key = `${provider}:${model}`.toLowerCase();
  const exactMap: Record<string, { input: number; output: number }> = {
    "deepseek:deepseek-chat": { input: 0.27, output: 1.10 },
    "deepseek:deepseek-reasoner": { input: 0.55, output: 2.19 },
  };
  if (exactMap[key]) return exactMap[key];
  if (provider === "deepseek") return exactMap["deepseek:deepseek-chat"];
  return { input: 0, output: 0 };
}

function getRates(provider: TextProvider, model: string): { input: number; output: number } {
  const modelKey = model.toUpperCase().replace(/[^A-Z0-9]+/g, "_");
  const inputOverride = Deno.env.get(`AI_COST_${provider.toUpperCase()}_${modelKey}_INPUT_PER_M`);
  const outputOverride = Deno.env.get(`AI_COST_${provider.toUpperCase()}_${modelKey}_OUTPUT_PER_M`);
  if (inputOverride && outputOverride) {
    return { input: Number(inputOverride) || 0, output: Number(outputOverride) || 0 };
  }
  return defaultRatePerM(provider, model);
}

function estimateCostUsd(provider: TextProvider, model: string, usage: UsageStats): number {
  const rates = getRates(provider, model);
  const usd = (usage.inputTokens / 1_000_000) * rates.input + (usage.outputTokens / 1_000_000) * rates.output;
  return Number.isFinite(usd) ? Number(usd.toFixed(6)) : 0;
}

async function logAiUsage(payload: {
  provider: TextProvider;
  model: string;
  context?: AIContext;
  usage: UsageStats;
  latencyMs: number;
  status: "ok" | "error";
  errorMessage?: string;
}) {
  const url = Deno.env.get("SUPABASE_URL")?.trim();
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
  if (!url || !serviceKey) return;

  const functionName = Deno.env.get("SB_EXECUTION_ID")?.trim() || Deno.env.get("DENO_DEPLOYMENT_ID")?.trim() || null;
  const body = {
    provider: payload.provider,
    model: payload.model,
    context: payload.context ?? null,
    function_name: functionName,
    input_tokens: payload.usage.inputTokens,
    output_tokens: payload.usage.outputTokens,
    total_tokens: payload.usage.totalTokens,
    estimated_cost_usd: estimateCostUsd(payload.provider, payload.model, payload.usage),
    latency_ms: payload.latencyMs,
    status: payload.status,
    error_message: payload.errorMessage ?? null,
  };
  try {
    await fetch(`${url}/rest/v1/ai_usage_logs`, {
      method: "POST",
      headers: {
        "apikey": serviceKey,
        "Authorization": `Bearer ${serviceKey}`,
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
      },
      body: JSON.stringify(body),
    });
  } catch (e) {
    console.warn("ai_usage_logs insert failed:", e);
  }
}

/** Список провайдеров с ключами, в порядке приоритета (каскад при fallback) */
function getAvailableProviders(context?: AIContext): TextProvider[] {
  const ctx = context ?? null;
  const ttkRaw =
    ctx === "ttk" ? Deno.env.get("AI_PROVIDER_TTK") : undefined;
  const ttkParseRaw =
    (ctx === "ttk_parse" || ctx === "ttk")
      ? (Deno.env.get("AI_PROVIDER_TTK_PARSE") || Deno.env.get("AI_PROVIDER_TTK"))
      : undefined;
  const ttkCreateRaw =
    (ctx === "ttk_create" || ctx === "ttk")
      ? (Deno.env.get("AI_PROVIDER_TTK_CREATE") || Deno.env.get("AI_PROVIDER_TTK"))
      : undefined;
  const nutritionRaw = ctx === "nutrition" ? Deno.env.get("AI_PROVIDER_NUTRITION") : undefined;
  const productRaw = ctx === "product" ? Deno.env.get("AI_PROVIDER_PRODUCT") : undefined;
  const checklistRaw = ctx === "checklist" ? Deno.env.get("AI_PROVIDER_CHECKLIST") : undefined;
  const raw =
    ttkCreateRaw ||
    ttkParseRaw ||
    ttkRaw ||
    nutritionRaw ||
    productRaw ||
    checklistRaw ||
    Deno.env.get("AI_PROVIDER");
  const forced = raw ? String(raw).toLowerCase().trim() : undefined;
  if (forced && PROVIDER_NAMES.includes(forced as TextProvider)) {
    return [forced as TextProvider];
  }
  const list: TextProvider[] = [];
  if (Deno.env.get("DEEPSEEK_API_KEY")?.trim()) list.push("deepseek");
  if (Deno.env.get("GROQ_API_KEY")?.trim()) list.push("groq");
  if (Deno.env.get("GEMINI_API_KEY")?.trim()) list.push("gemini");
  if (Deno.env.get("GIGACHAT_AUTH_KEY")?.trim() || Deno.env.get("GIGACHAT_API_KEY")?.trim()) list.push("gigachat");
  if (Deno.env.get("OPENROUTER_API_KEY")?.trim()) list.push("openrouter");
  if (Deno.env.get("MISTRAL_API_KEY")?.trim()) list.push("mistral");
  if (Deno.env.get("CEREBRAS_API_KEY")?.trim()) list.push("cerebras");
  if (Deno.env.get("OPENAI_API_KEY")?.trim()) list.push("openai");
  if (Deno.env.get("ANTHROPIC_API_KEY")?.trim()) list.push("claude");
  // Генерация ТТК: ниже задержка важнее «порядка ключей в .env» — сначала быстрые провайдеры.
  if (ctx === "ttk_create" && list.length > 1) {
    const preferredOrder: TextProvider[] = [
      "cerebras",
      "groq",
      "gemini",
      "mistral",
      "openrouter",
      "deepseek",
      "openai",
      "gigachat",
      "claude",
    ];
    const ordered: TextProvider[] = [];
    for (const p of preferredOrder) {
      if (list.includes(p)) ordered.push(p);
    }
    for (const p of list) {
      if (!ordered.includes(p)) ordered.push(p);
    }
    return ordered;
  }
  return list.length > 0 ? list : ["openai"];
}

/** Первый доступный провайдер (для context — с учётом AI_PROVIDER_*) */
export function getProvider(context?: AIContext): TextProvider {
  return getAvailableProviders(context)[0];
}

/** Внутренний вызов одного провайдера (без fallback) */
async function chatTextWithProvider(provider: TextProvider, options: {
  messages: Message[];
  model?: string;
  temperature?: number;
  maxTokens?: number;
  context?: AIContext;
}): Promise<ChatResult> {
  const { messages, temperature = 0.3, maxTokens = 2048 } = options;
  const startedAt = Date.now();

  if (provider === "deepseek") {
    const apiKey = Deno.env.get("DEEPSEEK_API_KEY")?.trim();
    if (!apiKey) throw new Error("DEEPSEEK_API_KEY not set");
    const model = options.model ?? "deepseek-chat";
    const body: Record<string, unknown> = { model, messages, temperature };
    if (maxTokens != null) body.max_tokens = maxTokens;
    const res = await fetch(DEEPSEEK_URL, {
      method: "POST",
      headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const err = await res.text();
      throw new Error(`DeepSeek: ${res.status} ${err}`);
    }
    const data = (await res.json()) as { choices?: { message?: { content?: string } }[]; usage?: unknown };
    const content = data.choices?.[0]?.message?.content?.trim();
    if (content == null) throw new Error("DeepSeek: empty response");
    const usage = parseUsage(data.usage);
    const latencyMs = Date.now() - startedAt;
    await logAiUsage({ provider, model, context: options.context, usage, latencyMs, status: "ok" });
    return { content, provider, model, usage, latencyMs };
  }

  if (provider === "groq") {
    const apiKey = Deno.env.get("GROQ_API_KEY")?.trim();
    if (!apiKey) throw new Error("GROQ_API_KEY not set");
    const model = options.model ?? "llama-3.3-70b-versatile";
    const body: Record<string, unknown> = { model, messages, temperature };
    if (maxTokens != null) body.max_tokens = maxTokens;
    const res = await fetch(GROQ_URL, {
      method: "POST",
      headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const err = await res.text();
      throw new Error(`Groq: ${res.status} ${err}`);
    }
    const data = (await res.json()) as { choices?: { message?: { content?: string } }[]; usage?: unknown };
    const content = data.choices?.[0]?.message?.content?.trim();
    if (content == null) throw new Error("Groq: empty response");
    const usage = parseUsage(data.usage);
    const latencyMs = Date.now() - startedAt;
    await logAiUsage({ provider, model, context: options.context, usage, latencyMs, status: "ok" });
    return { content, provider, model, usage, latencyMs };
  }

  if (provider === "gemini") {
    const apiKey = Deno.env.get("GEMINI_API_KEY")?.trim();
    if (!apiKey) throw new Error("GEMINI_API_KEY not set");
    const model = options.model ?? "gemini-2.0-flash";
    const systemMsg = messages.find((m) => m.role === "system");
    const chatMessages = messages.filter((m) => m.role !== "system");
    const contents = chatMessages.map((m) => ({
      role: m.role === "assistant" ? "model" : "user",
      parts: [{ text: m.content }],
    }));
    const body: Record<string, unknown> = {
      contents,
      generationConfig: { maxOutputTokens: maxTokens, temperature },
    };
    if (systemMsg?.content) body.systemInstruction = { parts: [{ text: systemMsg.content }] };
    const res = await fetch(`${GEMINI_URL}/${model}:generateContent`, {
      method: "POST",
      headers: { "x-goog-api-key": apiKey, "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const err = await res.text();
      throw new Error(`Gemini: ${res.status} ${err}`);
    }
    const data = (await res.json()) as {
      candidates?: { content?: { parts?: { text?: string }[] } }[];
      usageMetadata?: unknown;
    };
    const text = data.candidates?.[0]?.content?.parts?.[0]?.text?.trim();
    if (text == null) throw new Error("Gemini: empty response");
    const usage = parseUsage(data.usageMetadata);
    const latencyMs = Date.now() - startedAt;
    await logAiUsage({ provider, model, context: options.context, usage, latencyMs, status: "ok" });
    return { content: text, provider, model, usage, latencyMs };
  }

  if (provider === "claude") {
    const apiKey = Deno.env.get("ANTHROPIC_API_KEY")?.trim();
    if (!apiKey) throw new Error("ANTHROPIC_API_KEY not set");
    const model = options.model ?? "claude-3-5-haiku-20241022";
    const systemMsg = messages.find((m) => m.role === "system");
    const chatMessages = messages.filter((m) => m.role !== "system");
    const body: Record<string, unknown> = {
      model,
      max_tokens: maxTokens,
      messages: chatMessages.map((m) => ({ role: m.role, content: m.content })),
    };
    if (systemMsg?.content) body.system = systemMsg.content;
    const res = await fetch(CLAUDE_URL, {
      method: "POST",
      headers: {
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const err = await res.text();
      throw new Error(`Claude: ${res.status} ${err}`);
    }
    const data = (await res.json()) as { content?: { type: string; text?: string }[]; usage?: unknown };
    const block = data.content?.find((c) => c.type === "text");
    const text = block && "text" in block ? block.text?.trim() : null;
    if (text == null) throw new Error("Claude: empty response");
    const usage = parseUsage(data.usage);
    const latencyMs = Date.now() - startedAt;
    await logAiUsage({ provider, model, context: options.context, usage, latencyMs, status: "ok" });
    return { content: text, provider, model, usage, latencyMs };
  }

  if (provider === "gigachat") {
    const authKey = Deno.env.get("GIGACHAT_AUTH_KEY")?.trim() || Deno.env.get("GIGACHAT_API_KEY")?.trim();
    if (!authKey) throw new Error("GIGACHAT_AUTH_KEY or GIGACHAT_API_KEY not set");
    const token = await getGigaChatToken(authKey);
    const model = options.model ?? "GigaChat-2"; // Lite, бесплатный лимит
    const body: Record<string, unknown> = {
      model,
      messages: messages.map((m) => ({ role: m.role, content: m.content })),
      temperature,
    };
    if (maxTokens != null) body.max_tokens = maxTokens;
    const res = await fetch(GIGACHAT_CHAT_URL, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const err = await res.text();
      throw new Error(`GigaChat: ${res.status} ${err}`);
    }
    const data = (await res.json()) as { choices?: { message?: { content?: string } }[]; usage?: unknown };
    const content = data.choices?.[0]?.message?.content?.trim();
    if (content == null) throw new Error("GigaChat: empty response");
    const usage = parseUsage(data.usage);
    const latencyMs = Date.now() - startedAt;
    await logAiUsage({ provider, model, context: options.context, usage, latencyMs, status: "ok" });
    return { content, provider, model, usage, latencyMs };
  }

  if (provider === "openrouter") {
    const apiKey = Deno.env.get("OPENROUTER_API_KEY")?.trim();
    if (!apiKey) throw new Error("OPENROUTER_API_KEY not set");
    const model = options.model ?? "meta-llama/llama-3.2-3b-instruct:free";
    const body: Record<string, unknown> = { model, messages, temperature };
    if (maxTokens != null) body.max_tokens = maxTokens;
    const res = await fetch(OPENROUTER_URL, {
      method: "POST",
      headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const err = await res.text();
      throw new Error(`OpenRouter: ${res.status} ${err}`);
    }
    const data = (await res.json()) as { choices?: { message?: { content?: string } }[]; usage?: unknown };
    const content = data.choices?.[0]?.message?.content?.trim();
    if (content == null) throw new Error("OpenRouter: empty response");
    const usage = parseUsage(data.usage);
    const latencyMs = Date.now() - startedAt;
    await logAiUsage({ provider, model, context: options.context, usage, latencyMs, status: "ok" });
    return { content, provider, model, usage, latencyMs };
  }

  if (provider === "mistral") {
    const apiKey = Deno.env.get("MISTRAL_API_KEY")?.trim();
    if (!apiKey) throw new Error("MISTRAL_API_KEY not set");
    const model = options.model ?? "mistral-small-latest";
    const body: Record<string, unknown> = { model, messages, temperature };
    if (maxTokens != null) body.max_tokens = maxTokens;
    const res = await fetch(MISTRAL_URL, {
      method: "POST",
      headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const err = await res.text();
      throw new Error(`Mistral: ${res.status} ${err}`);
    }
    const data = (await res.json()) as { choices?: { message?: { content?: string } }[]; usage?: unknown };
    const content = data.choices?.[0]?.message?.content?.trim();
    if (content == null) throw new Error("Mistral: empty response");
    const usage = parseUsage(data.usage);
    const latencyMs = Date.now() - startedAt;
    await logAiUsage({ provider, model, context: options.context, usage, latencyMs, status: "ok" });
    return { content, provider, model, usage, latencyMs };
  }

  if (provider === "cerebras") {
    const apiKey = Deno.env.get("CEREBRAS_API_KEY")?.trim();
    if (!apiKey) throw new Error("CEREBRAS_API_KEY not set");
    const model = options.model ?? "llama3.1-8b";
    const body: Record<string, unknown> = { model, messages, temperature };
    if (maxTokens != null) body.max_tokens = maxTokens;
    const res = await fetch(CEREBRAS_URL, {
      method: "POST",
      headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const err = await res.text();
      throw new Error(`Cerebras: ${res.status} ${err}`);
    }
    const data = (await res.json()) as { choices?: { message?: { content?: string } }[]; usage?: unknown };
    const content = data.choices?.[0]?.message?.content?.trim();
    if (content == null) throw new Error("Cerebras: empty response");
    const usage = parseUsage(data.usage);
    const latencyMs = Date.now() - startedAt;
    await logAiUsage({ provider, model, context: options.context, usage, latencyMs, status: "ok" });
    return { content, provider, model, usage, latencyMs };
  }

  if (provider === "openai") {
    const apiKey = Deno.env.get("OPENAI_API_KEY");
    if (!apiKey) throw new Error("OPENAI_API_KEY not set");
    const model = options.model ?? "gpt-4o-mini";
    const body: Record<string, unknown> = { model, messages, temperature };
    if (maxTokens != null) body.max_tokens = maxTokens;
    const res = await fetch(OPENAI_URL, {
      method: "POST",
      headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const err = await res.text();
      throw new Error(`OpenAI: ${res.status} ${err}`);
    }
    const data = (await res.json()) as { choices?: { message?: { content?: string } }[]; usage?: unknown };
    const content = data.choices?.[0]?.message?.content?.trim();
    if (content == null) throw new Error("OpenAI: empty response");
    const usage = parseUsage(data.usage);
    const latencyMs = Date.now() - startedAt;
    await logAiUsage({ provider, model, context: options.context, usage, latencyMs, status: "ok" });
    return { content, provider, model, usage, latencyMs };
  }

  throw new Error(`Unknown provider: ${provider}`);
}

/**
 * Вызов чата (только текст). Каскад: при ошибке/пустом ответе пробует следующий провайдер.
 * context: "ttk_parse" | "ttk_create" | "nutrition" | "product" | "checklist" — для выбора AI_PROVIDER_*.
 */
export async function chatText(options: {
  messages: Message[];
  model?: string;
  temperature?: number;
  maxTokens?: number;
  context?: AIContext;
}): Promise<string> {
  const providers = getAvailableProviders(options.context);
  let lastError: Error | null = null;
  for (const provider of providers) {
    try {
      const result = await chatTextWithProvider(provider, options);
      if (result.content?.trim()) return result.content;
    } catch (e) {
      lastError = e instanceof Error ? e : new Error(String(e));
      await logAiUsage({
        provider,
        model: options.model ?? "",
        context: options.context,
        usage: { inputTokens: 0, outputTokens: 0, totalTokens: 0 },
        latencyMs: 0,
        status: "error",
        errorMessage: lastError.message.slice(0, 500),
      });
      console.warn(`AI provider ${provider} failed:`, lastError.message);
    }
  }
  throw lastError ?? new Error("No AI provider available");
}

/** Вызов с поддержкой изображений. Каскад: Groq (Llama 4 Scout) → OpenAI. */
export async function chatWithVision(options: {
  messages: (Message | { role: "user"; content: Array<{ type: "text"; text: string } | { type: "image_url"; image_url: { url: string } }> })[];
  model?: string;
  temperature?: number;
  maxTokens?: number;
}): Promise<string> {
  const groqKey = Deno.env.get("GROQ_API_KEY")?.trim();
  const openaiKey = Deno.env.get("OPENAI_API_KEY")?.trim();

  if (groqKey) {
    try {
      const res = await fetch(GROQ_URL, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${groqKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "meta-llama/llama-4-scout-17b-16e-instruct",
          messages: options.messages,
          temperature: options.temperature ?? 0.2,
          max_tokens: options.maxTokens ?? 2048,
        }),
      });
      if (res.ok) {
        const data = (await res.json()) as { choices?: { message?: { content?: string } }[] };
        const content = data.choices?.[0]?.message?.content?.trim();
        if (content) return content;
      } else {
        console.warn("Groq vision failed:", res.status, await res.text());
      }
    } catch (e) {
      console.warn("Groq vision error:", e);
    }
  }

  if (!openaiKey) throw new Error("OPENAI_API_KEY not set (required when Groq vision fails or is unavailable)");
  const res = await fetch(OPENAI_URL, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${openaiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: options.model ?? "gpt-4o",
      messages: options.messages,
      temperature: options.temperature ?? 0.2,
      max_tokens: options.maxTokens,
    }),
  });
  if (!res.ok) {
    const err = await res.text();
    throw new Error(`OpenAI: ${res.status} ${err}`);
  }
  const data = (await res.json()) as { choices?: { message?: { content?: string } }[] };
  const content = data.choices?.[0]?.message?.content?.trim();
  if (content == null) throw new Error("OpenAI: empty response");
  return content;
}
