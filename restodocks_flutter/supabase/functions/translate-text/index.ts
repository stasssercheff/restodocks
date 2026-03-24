import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { enforceRateLimit, hasValidApiKeyOrUser, resolveCorsHeaders } from "../_shared/security.ts";

const DEEPL_URL = "https://api-free.deepl.com/v2/translate";
const DEEPL_USAGE_URL = "https://api-free.deepl.com/v2/usage";

function corsHeaders(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin || "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
}

function jsonResponse(data: unknown, status = 200, origin: string | null = null) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin");
  const cors = resolveCorsHeaders(req);

  if (req.method === "OPTIONS") {
    return new Response(null, { headers: cors });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
  if (!(await hasValidApiKeyOrUser(req))) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
  if (!enforceRateLimit(req, "translate-text", { windowMs: 60_000, maxRequests: 60 })) {
    return new Response(JSON.stringify({ error: "Too many requests" }), {
      status: 429,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const deeplKey = Deno.env.get("DEEPL_API_KEY")?.trim();
  if (!deeplKey) {
    return jsonResponse({ error: "DEEPL_API_KEY not set in Supabase secrets" }, 500, origin);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, supabaseKey);

  let body: { text?: string; from?: string; to?: string; usage?: boolean };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400, origin);
  }

  // Режим проверки лимита: {"usage": true}
  if (body.usage) {
    const usageRes = await fetch(DEEPL_USAGE_URL, {
      headers: { "Authorization": `DeepL-Auth-Key ${deeplKey}` },
    });
    if (!usageRes.ok) {
      return jsonResponse({ error: "Failed to fetch DeepL usage" }, 500, origin);
    }
    const usageData = await usageRes.json() as { character_count: number; character_limit: number };
    const used = usageData.character_count;
    const limit = usageData.character_limit;
    const pct = Math.round((used / limit) * 100);
    return jsonResponse({
      used,
      limit,
      remaining: limit - used,
      percent_used: pct,
      warning: pct >= 80,
    }, 200, origin);
  }

  const { text, from = "RU", to } = body;

  if (!text || typeof text !== "string" || !to || typeof to !== "string") {
    return jsonResponse({ error: "text and to (target language) are required" }, 400, origin);
  }

  const trimmed = text.trim();
  if (!trimmed) {
    return jsonResponse({ translatedText: "" }, 200, origin);
  }

  const sourceLang = from.toUpperCase();
  const targetLang = to.toUpperCase();

  // Если исходный и целевой язык совпадают — возвращаем как есть
  if (sourceLang === targetLang) {
    return jsonResponse({ translatedText: trimmed }, 200, origin);
  }

  // Проверяем кеш
  const { data: cached } = await supabase
    .from("translation_cache")
    .select("translated")
    .eq("source_text", trimmed)
    .eq("source_lang", sourceLang)
    .eq("target_lang", targetLang)
    .maybeSingle();

  if (cached?.translated) {
    return jsonResponse({ translatedText: cached.translated, cached: true }, 200, origin);
  }

  // Кеша нет — идём в DeepL
  const deeplRes = await fetch(DEEPL_URL, {
    method: "POST",
    headers: {
      "Authorization": `DeepL-Auth-Key ${deeplKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      text: [trimmed],
      source_lang: sourceLang,
      target_lang: targetLang,
    }),
  });

  if (!deeplRes.ok) {
    const errText = await deeplRes.text();
    console.error("[translate-text] DeepL error:", deeplRes.status, errText);

    // Fallback — возвращаем оригинал чтобы не сломать UI
    return jsonResponse({
      translatedText: trimmed,
      fallback: true,
      error: `DeepL API: ${deeplRes.status}`,
    }, 200, origin);
  }

  const deeplData = await deeplRes.json() as {
    translations?: Array<{ text?: string }>;
  };
  const translated = deeplData?.translations?.[0]?.text?.trim();

  if (!translated) {
    return jsonResponse({ translatedText: trimmed, fallback: true }, 200, origin);
  }

  // Сохраняем в кеш (upsert на случай race condition)
  await supabase.from("translation_cache").upsert({
    source_text: trimmed,
    source_lang: sourceLang,
    target_lang: targetLang,
    translated,
  }, { onConflict: "source_text,source_lang,target_lang" });

  return jsonResponse({ translatedText: translated }, 200, origin);
});
