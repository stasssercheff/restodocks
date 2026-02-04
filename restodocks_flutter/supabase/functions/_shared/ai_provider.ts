/**
 * Общий слой вызова ИИ. Приоритет на старте: бесплатные (GigaChat), при наличии ключей — OpenAI.
 * Переменные:
 * - AI_PROVIDER = "gigachat" | "openai" (по умолчанию: gigachat если задан GIGACHAT_AUTH_KEY, иначе openai)
 * - GIGACHAT_AUTH_KEY = Base64(ClientID:ClientSecret) из личного кабинета GigaChat
 * - OPENAI_API_KEY = ключ OpenAI
 * Задачи с картинками (чек, ТТК из фото) пока только через OpenAI.
 */

const GIGACHAT_AUTH_URL = "https://ngw.devices.sberbank.ru:9443/api/v2/oauth";
const GIGACHAT_CHAT_URL = "https://gigachat.devices.sberbank.ru/api/v1/chat/completions";
const GIGACHAT_SCOPE = "GIGACHAT_API_PERS";
const OPENAI_URL = "https://api.openai.com/v1/chat/completions";

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

/** Определяет провайдера: приоритет GigaChat (бесплатный лимит), иначе OpenAI */
export function getProvider(): "gigachat" | "openai" {
  const forced = Deno.env.get("AI_PROVIDER")?.toLowerCase();
  if (forced === "openai" || forced === "gigachat") return forced;
  const authKey = Deno.env.get("GIGACHAT_AUTH_KEY");
  if (authKey?.trim()) return "gigachat";
  return "openai";
}

/**
 * Вызов чата (только текст). Использует GigaChat, если задан GIGACHAT_AUTH_KEY и не указан AI_PROVIDER=openai, иначе OpenAI.
 */
export async function chatText(options: {
  messages: Message[];
  model?: string;
  temperature?: number;
  maxTokens?: number;
}): Promise<string> {
  const provider = getProvider();
  const { messages, temperature = 0.3, maxTokens } = options;

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
