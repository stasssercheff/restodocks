import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  enforceRateLimit,
  getAuthenticatedUserId,
  isServiceRoleBearer,
  isServiceRoleRequest,
  resolveCorsHeaders,
} from "../_shared/security.ts";

const DEEPL_URL = "https://api-free.deepl.com/v2/translate";
const SUPPORTED_LANGS = ["ru", "en", "es", "kk", "tr", "vi"];

function jsonResponse(req: Request, data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...resolveCorsHeaders(req), "Content-Type": "application/json" },
  });
}

async function translateWithDeepL(
  text: string,
  sourceLang: string,
  targetLang: string,
  deeplKey: string | undefined,
  supabase: ReturnType<typeof createClient>,
): Promise<string | null> {
  if (!text.trim() || sourceLang.toUpperCase() === targetLang.toUpperCase()) return null;

  const src = sourceLang.toUpperCase();
  const tgt = targetLang.toUpperCase();

  // Проверяем кэш (если таблица есть)
  try {
    const { data: cached } = await supabase
      .from("translation_cache")
      .select("translated")
      .eq("source_text", text.trim())
      .eq("source_lang", src)
      .eq("target_lang", tgt)
      .maybeSingle();

    if (cached?.translated) return cached.translated as string;
  } catch (e) {
    console.log("[auto-translate-product] Cache read skip:", (e as Error)?.message);
  }

  const key = deeplKey?.trim();
  if (!key) {
    const only = await translateWithMyMemory(text.trim(), src, targetLang.toLowerCase());
    if (!only) return null;
    try {
      await supabase.from("translation_cache").upsert(
        { source_text: text.trim(), source_lang: src, target_lang: tgt, translated: only },
        { onConflict: "source_text,source_lang,target_lang" },
      );
    } catch (_) {}
    return only;
  }

  const res = await fetch(DEEPL_URL, {
    method: "POST",
    headers: {
      "Authorization": `DeepL-Auth-Key ${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ text: [text.trim()], source_lang: src, target_lang: tgt }),
  });

  if (!res.ok) {
    console.error("[auto-translate-product] DeepL error:", res.status, await res.text());
    const fallback = await translateWithMyMemory(text.trim(), src, targetLang.toLowerCase());
    if (fallback) return fallback;
    return null;
  }

  const data = await res.json() as { translations?: Array<{ text?: string }> };
  let translated = data?.translations?.[0]?.text?.trim();
  if (!translated) {
    translated = await translateWithMyMemory(text.trim(), src, targetLang.toLowerCase());
  }
  if (!translated) return null;

  try {
    await supabase.from("translation_cache").upsert(
      { source_text: text.trim(), source_lang: src, target_lang: tgt, translated },
      { onConflict: "source_text,source_lang,target_lang" },
    );
  } catch (_) {}

  return translated;
}

/** MyMemory fallback когда DeepL недоступен/не поддерживает язык. Лимит ~1000 слов/день. */
async function translateWithMyMemory(text: string, src: string, tgt: string): Promise<string | null> {
  const source = src.toUpperCase();
  const srcCode =
    source === "RU" ? "ru" :
    source === "EN" ? "en" :
    source === "ES" ? "es" :
    source === "TR" ? "tr" :
    source === "KK" ? "kk" :
    source === "VI" ? "vi" :
    "en";
  try {
    const url = `https://api.mymemory.translated.net/get?q=${encodeURIComponent(text)}&langpair=${srcCode}|${tgt}`;
    const r = await fetch(url);
    if (!r.ok) return null;
    const j = await r.json() as { responseData?: { translatedText?: string } };
    return j?.responseData?.translatedText?.trim() || null;
  } catch (e) {
    console.log("[auto-translate-product] MyMemory fallback err:", (e as Error)?.message);
    return null;
  }
}

Deno.serve(async (req: Request) => {
  const cors = resolveCorsHeaders(req);

  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return jsonResponse(req, { error: "Method not allowed" }, 405);
  const uid = await getAuthenticatedUserId(req);
  const isService = isServiceRoleRequest(req) || isServiceRoleBearer(req);
  if (!isService && !uid) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: { ...cors, "Content-Type": "application/json" } });
  }
  if (!enforceRateLimit(req, "auto-translate-product", { windowMs: 60_000, maxRequests: 40 })) {
    return new Response(JSON.stringify({ error: "Too many requests" }), { status: 429, headers: { ...cors, "Content-Type": "application/json" } });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  let body: { product_id?: string; batch?: boolean; force_langs?: string[] };
  try {
    body = await req.json();
  } catch {
    return jsonResponse(req, { error: "Invalid JSON" }, 400);
  }

  const deeplKey = Deno.env.get("DEEPL_API_KEY")?.trim();
  if (!deeplKey) {
    console.warn("[auto-translate-product] DEEPL_API_KEY not set — using MyMemory only");
  }

  // Режим batch: переводим продукты постранично (limit/offset для обхода таймаута)
  if (body.batch) {
    const batchBody = body as {
      batch: boolean;
      limit?: number;
      offset?: number;
      force_langs?: string[];
    };
    const limit = batchBody.limit ?? 50;
    const offset = batchBody.offset ?? 0;
    const forceLangs = new Set((batchBody.force_langs ?? []).map((l: string) => l.toLowerCase()));

    const { data: products, error } = await supabase
      .from("products")
      .select("id, name, names")
      .order("name")
      .range(offset, offset + limit - 1);

    if (error) return jsonResponse(req, { error: error.message }, 500);

    let translated = 0;
    let skipped = 0;
    let failed = 0;

    for (const product of (products ?? [])) {
      const names = (product.names ?? {}) as Record<string, string>;
      const name = (product.name as string)?.trim();
      if (!name) { skipped++; continue; }

      const sourceLang = Object.keys(names).find(k => names[k]?.trim()) ?? "ru";
      const sourceText = names[sourceLang]?.trim() || name;

      let needsUpdate = false;
      const updatedNames: Record<string, string> = { ...names };

      if (!updatedNames[sourceLang]) updatedNames[sourceLang] = sourceText;

      for (const targetLang of SUPPORTED_LANGS) {
        if (targetLang === sourceLang) continue;
        const skipExisting = !forceLangs.has(targetLang) &&
          updatedNames[targetLang]?.trim() && updatedNames[targetLang] !== sourceText;
        if (skipExisting) continue;

        const result = await translateWithDeepL(sourceText, sourceLang, targetLang, deeplKey, supabase);
        if (result && result !== sourceText) {
          updatedNames[targetLang] = result;
          needsUpdate = true;
        }
      }

      if (needsUpdate) {
        const { error: updateError } = await supabase
          .from("products")
          .update({ names: updatedNames })
          .eq("id", product.id);

        if (updateError) {
          console.error("[auto-translate-product] Update error:", updateError.message);
          failed++;
        } else {
          translated++;
        }
      } else {
        skipped++;
      }

      if (translated % 50 === 0 && translated > 0) {
        await new Promise(r => setTimeout(r, 500));
      }
    }

    const batchSize = (products ?? []).length;
    return jsonResponse(req, { translated, skipped, failed, batch_size: batchSize, offset, has_more: batchSize === limit }, 200);
  }

  const { product_id } = body;
  if (!product_id) return jsonResponse(req, { error: "product_id or batch required" }, 400);

  console.log("[auto-translate-product] Processing product_id:", product_id);

  const { data: product, error: fetchError } = await supabase
    .from("products")
    .select("id, name, names")
    .eq("id", product_id)
    .maybeSingle();

  if (fetchError || !product) return jsonResponse(req, { error: "Product not found" }, 404);

  const names = ((product.names ?? {}) as Record<string, string>);
  const name = (product.name as string)?.trim();
  if (!name) return jsonResponse(req, { skipped: true }, 200);

  const sourceLang = Object.keys(names).find(k => names[k]?.trim()) ?? "ru";
  const sourceText = names[sourceLang]?.trim() || name;
  const updatedNames: Record<string, string> = { ...names, [sourceLang]: sourceText };
  let needsUpdate = false;
  const forceLangs = new Set((body.force_langs ?? []).map((l: string) => l.toLowerCase()));

  console.log("[auto-translate-product] sourceLang:", sourceLang, "sourceText:", sourceText?.slice(0, 30));

  for (const targetLang of SUPPORTED_LANGS) {
    if (targetLang === sourceLang) continue;
    const skipExisting = !forceLangs.has(targetLang) &&
      updatedNames[targetLang]?.trim() && updatedNames[targetLang] !== sourceText;
    if (skipExisting) continue;

    const result = await translateWithDeepL(sourceText, sourceLang, targetLang, deeplKey, supabase);
    if (result && result !== sourceText) {
      updatedNames[targetLang] = result;
      needsUpdate = true;
      console.log("[auto-translate-product] Translated to", targetLang, ":", result?.slice(0, 30));
    } else {
      console.log("[auto-translate-product] No translation for", targetLang, "result:", result ? "same text" : "null");
    }
  }

  if (needsUpdate) {
    const { error: updateErr } = await supabase.from("products").update({ names: updatedNames }).eq("id", product.id);
    if (updateErr) console.error("[auto-translate-product] DB update error:", updateErr.message);
  }

  console.log("[auto-translate-product] Done. needsUpdate:", needsUpdate);
  return jsonResponse(req, { product_id, names: updatedNames, updated: needsUpdate }, 200);
});
