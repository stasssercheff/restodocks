/**
 * Общий слой вызова ИИ. Поддерживаются: GigaChat, OpenAI, Google Gemini, Anthropic Claude.
 * Переменные:
 * - AI_PROVIDER = "gigachat" | "openai" | "gemini" | "claude" — явный выбор; иначе по приоритету ключей
 * - GIGACHAT_AUTH_KEY = Base64(ClientID:ClientSecret) — GigaChat (бесплатный лимит для физлиц)
 * - OPENAI_API_KEY — OpenAI (фото + текст)
 * - GEMINI_API_KEY — Google AI Studio, бесплатный tier (aistudio.google.com)
 * - ANTHROPIC_API_KEY — Claude API (платно)
 * Задачи с картинками (чек, ТТК из фото) пока только через OpenAI.
 */

const GIGACHAT_AUTH_URL = "https://ngw.devices.sberbank.ru:9443/api/v2/oauth";
const GIGACHAT_CHAT_URL = "https://gigachat.devices.sberbank.ru/api/v1/chat/completions";
const GIGACHAT_SCOPE = "GIGACHAT_API_PERS";
const OPENAI_URL = "https://api.openai.com/v1/chat/completions";
const GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models";
const CLAUDE_URL = "https://api.anthropic.com/v1/messages";

export type Message = { role: "system" | "user" | "assistant"; content: string };

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

export type TextProvider = "gigachat" | "openai" | "gemini" | "claude";

/** Определяет провайдера: AI_PROVIDER или по приоритету ключей (gigachat → gemini → claude → openai) */
export function getProvider(): TextProvider {
  const forced = Deno.env.get("AI_PROVIDER")?.toLowerCase();
  if (forced === "openai" || forced === "gigachat" || forced === "gemini" || forced === "claude") return forced;
  if (Deno.env.get("GIGACHAT_AUTH_KEY")?.trim()) return "gigachat";
  if (Deno.env.get("GEMINI_API_KEY")?.trim()) return "gemini";
  if (Deno.env.get("ANTHROPIC_API_KEY")?.trim()) return "claude";
  return "openai";
}

/**
 * Вызов чата (только текст). Провайдер: GigaChat / Gemini / Claude / OpenAI по AI_PROVIDER или ключам.
 */
export async function chatText(options: {
  messages: Message[];
  model?: string;
  temperature?: number;
  maxTokens?: number;
}): Promise<string> {
  const provider = getProvider();
  const { messages, temperature = 0.3, maxTokens = 2048 } = options;

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
    const data = (await res.json()) as { candidates?: { content?: { parts?: { text?: string }[] } }[] };
    const text = data.candidates?.[0]?.content?.parts?.[0]?.text?.trim();
    if (text == null) throw new Error("Gemini: empty response");
    return text;
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
    const data = (await res.json()) as { content?: { type: string; text?: string }[] };
    const block = data.content?.find((c) => c.type === "text");
    const text = block && "text" in block ? block.text?.trim() : null;
    if (text == null) throw new Error("Claude: empty response");
    return text;
  }

  if (provider === "gigachat") {
    const authKey = Deno.env.get("GIGACHAT_AUTH_KEY")?.trim();
    if (!authKey) throw new Error("GIGACHAT_AUTH_KEY not set");
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
    const data = (await res.json()) as { choices?: { message?: { content?: string } }[] };
    const content = data.choices?.[0]?.message?.content?.trim();
    if (content == null) throw new Error("GigaChat: empty response");
    return content;
  }

  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) throw new Error("OPENAI_API_KEY not set");
  const model = options.model ?? "gpt-4o-mini";
  const body: Record<string, unknown> = {
    model,
    messages,
    temperature,
  };
  if (maxTokens != null) body.max_tokens = maxTokens;
  const res = await fetch(OPENAI_URL, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
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

/** Вызов OpenAI с поддержкой изображений (base64). Для чека/ТТК из фото — только OpenAI. */
export async function chatWithVision(options: {
  messages: (Message | { role: "user"; content: Array<{ type: "text"; text: string } | { type: "image_url"; image_url: { url: string } }> })[];
  model?: string;
  temperature?: number;
  maxTokens?: number;
}): Promise<string> {
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) throw new Error("OPENAI_API_KEY not set (required for vision)");
  const res = await fetch(OPENAI_URL, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
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
