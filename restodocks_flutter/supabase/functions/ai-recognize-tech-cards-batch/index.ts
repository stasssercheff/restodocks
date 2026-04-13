// Supabase Edge Function: распознавание нескольких ТТК из одного документа (Excel/Numbers)
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { chatText } from "../_shared/ai_provider.ts";

function corsHeaders(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin || "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
}

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
    const body = (await req.json()) as { rows?: string[][]; establishmentId?: string; nomenclatureProductNames?: string[] };
    const rows = body.rows;
    const establishmentId = typeof body.establishmentId === "string" ? body.establishmentId.trim() : undefined;
    const nomenclatureProductNames = Array.isArray(body.nomenclatureProductNames) ? body.nomenclatureProductNames.filter((n): n is string => typeof n === "string").slice(0, 500) : [];

    // Лимит: 3 парсинга через AI в день на заведение
    if (establishmentId) {
      const { checkAndIncrementAiTtkUsage } = await import("../_shared/ai_ttk_limit.ts");
      const { allowed, reason } = await checkAndIncrementAiTtkUsage(establishmentId);
      if (!allowed) {
        return new Response(
          JSON.stringify({ cards: [], error: reason ?? "ai_limit_exceeded", reason: reason ?? "ai_limit_exceeded" }),
          { status: 200, headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" } },
        );
      }
    }

    const hasTextProvider = Deno.env.get("DEEPSEEK_API_KEY")?.trim() || Deno.env.get("GROQ_API_KEY")?.trim() || Deno.env.get("GEMINI_API_KEY")?.trim() || Deno.env.get("GIGACHAT_AUTH_KEY")?.trim() || Deno.env.get("OPENAI_API_KEY");
    if (!hasTextProvider) {
      return new Response(JSON.stringify({ error: "DEEPSEEK_API_KEY, GROQ_API_KEY, GEMINI_API_KEY, GIGACHAT_AUTH_KEY or OPENAI_API_KEY required" }), {
        status: 500,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    if (!rows || !Array.isArray(rows)) {
      return new Response(JSON.stringify({ error: "rows (array of row arrays) required" }), {
        status: 400,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    // 1. Сначала пробуем парсинг по сохранённым шаблонам (tt_parse_templates) — без AI, без лимитов.
    // Это обходит 400/401 при прямом запросе к tt_parse_templates с клиента (RLS/auth).
    const { tryParseByStoredTemplates } = await import("../_shared/try_stored_ttk_templates.ts");
    const storedResult = await tryParseByStoredTemplates(rows);
    if (storedResult && storedResult.cards.length > 0) {
      const normalized = storedResult.cards.map((card) => ({
        dishName: card.dishName ?? null,
        technologyText: card.technologyText ?? null,
        isSemiFinished: card.isSemiFinished ?? undefined,
        yieldGrams: card.yieldGrams ?? undefined,
        ingredients: (card.ingredients ?? []).map((i) => ({
          productName: i.productName ?? "",
          grossGrams: i.grossGrams ?? undefined,
          netGrams: i.netGrams ?? undefined,
          unit: i.unit ?? undefined,
          primaryWastePct: i.primaryWastePct ?? undefined,
          outputGrams: i.outputGrams ?? undefined,
          ingredientType: i.ingredientType ?? undefined,
          pricePerKg: (i as { pricePerKg?: number | null }).pricePerKg ?? undefined,
        })),
      }));
      return new Response(JSON.stringify({ cards: normalized }), {
        status: 200,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    const systemPrompt = `You are a tech card (recipe/semi-finished) parser. The document often contains MANY tech cards (50–200+). Your task is to extract ALL of them.

Structure in the table (columns may be in different order or have different names):
- Recipe/dish name: "Наименование" or first column; often bold or in a header row; can be "ПФ ..." (semi-finished) or a dish name.
- Ingredient name: "Продукт" or product column.
- Quantities: "Брутто" (gross, g), "Нетто" (net, g), "Выход" (output, g).
- Percentages: "Процент отхода" / "отход" (waste %), "Уварка" / "ужаривание" (shrinkage/cooking loss %).
- Technology: "Технология" — multi-line cooking instructions; often in a merged cell on the right for the whole block.

If the document has prices (e.g. "Цена за 1 кг/л", "Цена", "Стоимость", "Кг") try to extract pricePerKg (price per kg/l) per ingredient. This is used to auto-fill nomenclature prices. If unsure, set pricePerKg null.

How to split cards: each card is a block — one dish name row (or name in first column), then ingredient rows, then usually an "Итого" (total) row. When you see a new dish name or "Наименование" again or a clear separator, start a new card. Technology text belongs to the card it is next to (merged cell).

For each ingredient, set ingredientType: "product" if it is purchased (сырьё, смесь, мука, масло, сливки — e.g. "смесь РИКО", "шоколад черный"); "semi_finished" if it is a semi-finished product made in-house (ПФ, крем, бисквит, соус собственного производства).

If column order or names vary (different languages, extra columns), infer from context. Extract: dishName, ingredients (productName, grossGrams, netGrams, primaryWastePct, cookingLossPct, ingredientType; unit default "g"), technologyText. Do not return empty just because the format is non-standard — parse as much as you can.

Return ONLY valid JSON, no markdown:
{ "cards": [ { "dishName": string, "technologyText": string | null, "isSemiFinished": boolean | null, "ingredients": [ { "productName": string, "grossGrams": number | null, "netGrams": number | null, "outputGrams": number | null, "primaryWastePct": number | null, "cookingMethod": string | null, "cookingLossPct": number | null, "unit": string | null, "ingredientType": "product" | "semi_finished" | null, "pricePerKg": number | null } ] }, ... ] }

If gross and net are given but primaryWastePct is not: calculate waste = (1 - net/gross)*100. If net and output (weight after cooking) are given but cookingLossPct is not: calculate cookingLossPct = (1 - output/net)*100.

Return ALL cards found (up to hundreds). If no cards, return { "cards": [] }.`;

    const nomenclatureHint = nomenclatureProductNames.length > 0
      ? `\n\nНоменклатура заведения (подсказка при маппинге ингредиентов — предпочитать эти названия, если документ явно ссылается на тот же продукт; НЕ заменять произвольно):\n${nomenclatureProductNames.slice(0, 200).join(", ")}`
      : "";

    const content = await chatText({
      messages: [
        { role: "system", content: systemPrompt + nomenclatureHint },
        { role: "user", content: `Document table rows:\n${JSON.stringify(rows)}` },
      ],
      maxTokens: 16384,
      context: "ttk_parse",
    });

    if (!content?.trim()) {
      return new Response(JSON.stringify({ cards: [] }), {
        status: 200,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    let parsed: { cards?: unknown[] };
    try {
      const cleaned = content.replace(/^```\w*\n?|\n?```$/g, "").trim();
      parsed = JSON.parse(cleaned) as { cards?: unknown[] };
    } catch {
      return new Response(JSON.stringify({ cards: [] }), {
        status: 200,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    const cards = Array.isArray(parsed.cards) ? parsed.cards : [];
    const toNumber = (v: unknown): number | undefined => {
      if (v == null) return undefined;
      if (typeof v === "number") return Number.isFinite(v) ? v : undefined;
      const s = String(v).trim();
      if (!s) return undefined;
      const cleaned = s.replace(/\s+/g, "").replace(/,/g, ".").replace(/[^\d.\-]/g, "");
      const n = Number.parseFloat(cleaned);
      return Number.isFinite(n) ? n : undefined;
    };
    const normalized = cards.map((card) => {
      const c = card as Record<string, unknown>;
      const ingredients = Array.isArray(c.ingredients)
        ? (c.ingredients as Record<string, unknown>[]).map((i) => {
            const it = String(i.ingredientType ?? "").toLowerCase();
            const ingredientType = (it === "product" || it === "semi_finished") ? it : undefined;
            return {
              productName: String(i.productName ?? ""),
              grossGrams: toNumber(i.grossGrams),
              netGrams: toNumber(i.netGrams),
              unit: i.unit != null ? String(i.unit) : undefined,
              cookingMethod: i.cookingMethod != null ? String(i.cookingMethod) : undefined,
              primaryWastePct: toNumber(i.primaryWastePct),
              cookingLossPct: toNumber(i.cookingLossPct),
              outputGrams: toNumber(i.outputGrams),
              ingredientType,
              pricePerKg: toNumber(i.pricePerKg),
            };
          })
        : [];
      return {
        dishName: c.dishName != null ? String(c.dishName) : null,
        technologyText: c.technologyText != null ? String(c.technologyText) : null,
        ingredients: ingredients,
        isSemiFinished: typeof c.isSemiFinished === "boolean" ? c.isSemiFinished : undefined,
        yieldGrams: toNumber((c as Record<string, unknown>).yieldGrams),
      };
    });

    return new Response(JSON.stringify({ cards: normalized }), {
      status: 200,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  }
});
