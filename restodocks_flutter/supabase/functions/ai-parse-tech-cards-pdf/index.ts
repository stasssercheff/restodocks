// Supabase Edge Function: распознавание ТТК из PDF
// Извлекает текст через unpdf, парсит через ИИ
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { extractText, getDocumentProxy } from "npm:unpdf@0.4.1";
import { chatText } from "../_shared/ai_provider.ts";

function corsHeaders(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin || "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
}

const PDF_SYSTEM_PROMPT = `Ты парсер технологических карт (ТТК, рецептов, полуфабрикатов). На входе — сырой текст из PDF.

КРИТИЧНО: Если в тексте есть хоть какая-то ТТК (название блюда/ПФ, ингредиенты, технология) — ты ОБЯЗАН извлечь хотя бы одну карточку. Подстраивайся под ЛЮБОЙ формат: Shama.Book, iiko, ГОСТ, собственные шаблоны ресторанов. Не требуй точного соответствия образцу.

Структура бывает разной: название в заголовке или отдельной строке; таблица с колонками № / Наименование / Продукт / Сырьё / Брутто / Нетто / Расход; числа в граммах или порциях. Извлекай что есть. Для grossGrams/netGrams бери любые подходящие числа (брутто, нетто, расход на порцию). ingredientType: "product" — сырьё; "semi_finished" — ПФ. isSemiFinished: true если в названии "ПФ".

Верни ТОЛЬКО валидный JSON, без markdown и обёрток:
{ "cards": [ { "dishName": string, "technologyText": string|null, "isSemiFinished": boolean|null, "ingredients": [ { "productName": string, "grossGrams": number|null, "netGrams": number|null, "primaryWastePct": number|null, "cookingMethod": string|null, "cookingLossPct": number|null, "unit": string|null, "ingredientType": "product"|"semi_finished"|null } ] } ] }

Если нет ни одной карточки: { "cards": [] }`;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders(req.headers.get("Origin")) });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  }

  try {
    const body = (await req.json()) as { pdfBase64?: string };
    const pdfBase64 = body.pdfBase64;
    if (!pdfBase64 || typeof pdfBase64 !== "string") {
      return new Response(JSON.stringify({ error: "pdfBase64 required" }), {
        status: 400,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    const hasProvider = Deno.env.get("GROQ_API_KEY")?.trim() ||
      Deno.env.get("GEMINI_API_KEY")?.trim() ||
      Deno.env.get("GIGACHAT_AUTH_KEY")?.trim() ||
      Deno.env.get("OPENAI_API_KEY");
    if (!hasProvider) {
      return new Response(JSON.stringify({ error: "AI provider key required" }), {
        status: 500,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    // Decode base64 to Uint8Array
    const binary = atob(pdfBase64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i);
    }

    // Extract text
    let text: string;
    try {
      const pdf = await getDocumentProxy(bytes);
      const result = await extractText(pdf, { mergePages: true });
      text = result.text ?? "";
    } catch (e) {
      return new Response(JSON.stringify({ cards: [], reason: `extraction_failed: ${e}` }), {
        status: 200,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    if (!text.trim()) {
      return new Response(JSON.stringify({ cards: [], reason: "empty_text" }), {
        status: 200,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    let content: string;
    try {
      content = await chatText({
        messages: [
          { role: "system", content: PDF_SYSTEM_PROMPT },
          { role: "user", content: `PDF extracted text:\n\n${text}` },
        ],
        maxTokens: 16384,
      }) ?? "";
    } catch (aiErr) {
      return new Response(JSON.stringify({ cards: [], reason: `ai_error: ${aiErr}` }), {
        status: 200,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    if (!content?.trim()) {
      return new Response(JSON.stringify({ cards: [], reason: "ai_empty_response" }), {
        status: 200,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    let parsed: { cards?: unknown[] } | null = null;
    const cleanContent = content.replace(/^```\w*\n?|\n?```$/g, "").trim();
    const jsonCandidates = [
      cleanContent,
      content,
      content.match(/\{[\s\S]*"cards"[\s\S]*\}/)?.[0] ?? "",
      content.match(/\{[\s\S]*"cards"\s*:\s*\[[\s\S]*\]\s*[\},]/)?.[0]?.replace(/,\s*$/, "}") ?? "",
    ];
    for (const candidate of jsonCandidates) {
      if (!candidate || candidate.length < 10) continue;
      try {
        parsed = JSON.parse(candidate) as { cards?: unknown[] };
        if (Array.isArray(parsed.cards)) break;
      } catch {
        /* try next */
      }
    }

    // Retry with simpler prompt if first attempt returned no cards
    if ((!parsed || !Array.isArray(parsed.cards) || parsed.cards.length === 0) && text.length > 100) {
      try {
        const simpleContent = await chatText({
          messages: [
            { role: "system", content: "Extract tech card from text. Return JSON: { \"cards\": [ { \"dishName\": string, \"technologyText\": string|null, \"isSemiFinished\": boolean|null, \"ingredients\": [ { \"productName\": string, \"grossGrams\": number|null, \"netGrams\": number|null } ] } ] }. No markdown." },
            { role: "user", content: text },
          ],
          maxTokens: 8192,
        });
        if (simpleContent?.trim()) {
          const simpleCleaned = simpleContent.replace(/^```\w*\n?|\n?```$/g, "").trim();
          const simpleParsed = JSON.parse(simpleCleaned) as { cards?: unknown[] };
          if (Array.isArray(simpleParsed.cards) && simpleParsed.cards.length > 0) {
            parsed = simpleParsed;
          }
        }
      } catch {
        /* keep original parsed */
      }
    }

    const cards = parsed && Array.isArray(parsed.cards) ? parsed.cards : [];
    const reasonIfEmpty = cards.length === 0 ? "ai_no_cards" : undefined;

    const normalized = cards.map((card) => {
      const c = card as Record<string, unknown>;
      const ingredients = Array.isArray(c.ingredients)
        ? (c.ingredients as Record<string, unknown>[]).map((i) => {
            const it = String(i.ingredientType ?? "").toLowerCase();
            const ingredientType = (it === "product" || it === "semi_finished") ? it : undefined;
            return {
              productName: String(i.productName ?? ""),
              grossGrams: i.grossGrams != null ? Number(i.grossGrams) : undefined,
              netGrams: i.netGrams != null ? Number(i.netGrams) : undefined,
              unit: i.unit != null ? String(i.unit) : undefined,
              cookingMethod: i.cookingMethod != null ? String(i.cookingMethod) : undefined,
              primaryWastePct: i.primaryWastePct != null ? Number(i.primaryWastePct) : undefined,
              cookingLossPct: i.cookingLossPct != null ? Number(i.cookingLossPct) : undefined,
              ingredientType,
            };
          })
        : [];
      return {
        dishName: c.dishName != null ? String(c.dishName) : null,
        technologyText: c.technologyText != null ? String(c.technologyText) : null,
        ingredients,
        isSemiFinished: typeof c.isSemiFinished === "boolean" ? c.isSemiFinished : undefined,
      };
    });

    const payload = reasonIfEmpty ? { cards: normalized, reason: reasonIfEmpty } : { cards: normalized };
    return new Response(JSON.stringify(payload), {
      status: 200,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ cards: [], reason: `error: ${e}` }), {
      status: 200,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  }
});
