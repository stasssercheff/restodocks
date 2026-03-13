// Edge Function: парсинг ТТК по сохранённым шаблонам (tt_parse_templates).
// Использует service role — обходит 400/401 при прямом запросе с клиента (RLS/auth).
// Не использует AI, без лимитов.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { tryParseByStoredTemplates } from "../_shared/try_stored_ttk_templates.ts";

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
    const body = (await req.json()) as { rows?: string[][] };
    const rows = body.rows;
    if (!rows || !Array.isArray(rows) || rows.length < 2) {
      return new Response(JSON.stringify({ cards: null }), {
        status: 200,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    const storedCards = await tryParseByStoredTemplates(rows);
    if (!storedCards || storedCards.length === 0) {
      return new Response(JSON.stringify({ cards: null }), {
        status: 200,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    const normalized = storedCards.map((card) => ({
      dishName: card.dishName ?? null,
      technologyText: card.technologyText ?? null,
      isSemiFinished: card.isSemiFinished ?? undefined,
      ingredients: (card.ingredients ?? []).map((i) => ({
        productName: i.productName ?? "",
        grossGrams: i.grossGrams ?? undefined,
        netGrams: i.netGrams ?? undefined,
        unit: i.unit ?? undefined,
        primaryWastePct: i.primaryWastePct ?? undefined,
        outputGrams: i.outputGrams ?? undefined,
        ingredientType: i.ingredientType ?? undefined,
      })),
    }));

    return new Response(JSON.stringify({ cards: normalized }), {
      status: 200,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ cards: null, error: String(e) }), {
      status: 200,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  }
});
