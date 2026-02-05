// Supabase Edge Function: распознавание нескольких ТТК из одного документа (Excel/Numbers)
import "jsr:@supabase/functions-js/edge_runtime.d.ts";
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

    const systemPrompt = `You are a tech card (recipe card) parser. The document may contain MULTIPLE tech cards. Each card has:
- A dish/semi-finished name (often in a header row or first column)
- A table with columns: 1=Dish name, 2=Product, 3=Gross (g), 4=Waste %, 5=Net (g), 6=Cooking method, 7=Cooking loss %, 8=Output, 9=Price/kg, 10=Cost, 11=Technology
- Technology text (column 11 or a separate block)

Split the table rows by blocks: when you see a new dish name or a clear separator (empty row, new header), start a new card.

Return ONLY valid JSON with this exact structure (no markdown):
{ "cards": [ { "dishName": string, "technologyText": string | null, "isSemiFinished": boolean | null, "ingredients": [ { "productName": string, "grossGrams": number | null, "netGrams": number | null, "primaryWastePct": number | null, "cookingMethod": string | null, "cookingLossPct": number | null, "unit": string | null } ] }, ... ] }

If the document has only one card, return { "cards": [ { ... } ] }. If no cards found, return { "cards": [] }.`;

    const content = await chatText({
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: `Document table rows:\n${JSON.stringify(rows)}` },
      ],
      maxTokens: 8192,
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
