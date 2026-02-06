// Supabase Edge Function: распознавание нескольких ТТК из одного документа (Excel/Numbers)
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { chatText } from "../_shared/ai_provider.ts";

function corsHeaders(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin || "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
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
    const body = (await req.json()) as { rows?: string[][] };
    const rows = body.rows;

    const hasTextProvider = Deno.env.get("GIGACHAT_AUTH_KEY")?.trim() || Deno.env.get("OPENAI_API_KEY");
    if (!hasTextProvider) {
      return new Response(JSON.stringify({ error: "GIGACHAT_AUTH_KEY or OPENAI_API_KEY required" }), {
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

    const systemPrompt = `You are a tech card (recipe/semi-finished) parser. The document often contains MANY tech cards (50–200+). Your task is to extract ALL of them.

Structure in the table (columns may be in different order or have different names):
- Recipe/dish name: "Наименование" or first column; often bold or in a header row; can be "ПФ ..." (semi-finished) or a dish name.
- Ingredient name: "Продукт" or product column.
- Quantities: "Брутто" (gross, g), "Нетто" (net, g), "Выход" (output, g).
- Percentages: "Процент отхода" / "отход" (waste %), "Уварка" / "ужаривание" (shrinkage/cooking loss %).
- Technology: "Технология" — multi-line cooking instructions; often in a merged cell on the right for the whole block.

IGNORE these columns (do not use, do not require): "Цена за 1 кг/л", "Кг", "Стоимость", "Цена за 1", price, cost. The system calculates cost itself.

How to split cards: each card is a block — one dish name row (or name in first column), then ingredient rows, then usually an "Итого" (total) row. When you see a new dish name or "Наименование" again or a clear separator, start a new card. Technology text belongs to the card it is next to (merged cell).

If column order or names vary (different languages, extra columns), infer from context. Extract: dishName, ingredients (productName, grossGrams, netGrams, primaryWastePct, cookingLossPct; unit default "g"), technologyText. Do not return empty just because the format is non-standard — parse as much as you can.

Return ONLY valid JSON, no markdown:
{ "cards": [ { "dishName": string, "technologyText": string | null, "isSemiFinished": boolean | null, "ingredients": [ { "productName": string, "grossGrams": number | null, "netGrams": number | null, "primaryWastePct": number | null, "cookingMethod": string | null, "cookingLossPct": number | null, "unit": string | null } ] }, ... ] }

Return ALL cards found (up to hundreds). If no cards, return { "cards": [] }.`;

    const content = await chatText({
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: `Document table rows:\n${JSON.stringify(rows)}` },
      ],
      maxTokens: 16384,
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
    const normalized = cards.map((card) => {
      const c = card as Record<string, unknown>;
      const ingredients = Array.isArray(c.ingredients)
        ? (c.ingredients as Record<string, unknown>[]).map((i) => ({
            productName: String(i.productName ?? ""),
            grossGrams: i.grossGrams != null ? Number(i.grossGrams) : undefined,
            netGrams: i.netGrams != null ? Number(i.netGrams) : undefined,
            unit: i.unit != null ? String(i.unit) : undefined,
            cookingMethod: i.cookingMethod != null ? String(i.cookingMethod) : undefined,
            primaryWastePct: i.primaryWastePct != null ? Number(i.primaryWastePct) : undefined,
            cookingLossPct: i.cookingLossPct != null ? Number(i.cookingLossPct) : undefined,
          }))
        : [];
      return {
        dishName: c.dishName != null ? String(c.dishName) : null,
        technologyText: c.technologyText != null ? String(c.technologyText) : null,
        ingredients: ingredients,
        isSemiFinished: typeof c.isSemiFinished === "boolean" ? c.isSemiFinished : undefined,
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
