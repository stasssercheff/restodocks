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
    let body: { rows?: unknown };
    try {
      body = (await req.json()) as { rows?: unknown };
    } catch {
      return new Response(JSON.stringify({ cards: null }), {
        status: 200,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }
    const raw = body.rows;
    if (!raw || !Array.isArray(raw) || raw.length < 2) {
      return new Response(JSON.stringify({ cards: null }), {
        status: 200,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }
    // Гарантированно string[][] (клиент может передать num в ячейках → 400)
    const rows: string[][] = raw.map((r: unknown) =>
      Array.isArray(r) ? (r as unknown[]).map((c) => (c != null ? String(c).trim() : "")) : []
    );

    const result = await tryParseByStoredTemplates(rows);
    if (!result || result.cards.length === 0) {
      return new Response(JSON.stringify({ cards: null }), {
        status: 200,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    const normalized = result.cards.map((card) => ({
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

    return new Response(JSON.stringify({ cards: normalized, header_signature: result.headerSignature }), {
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
