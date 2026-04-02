// Edge Function: парсинг ТТК по сохранённым шаблонам (tt_parse_templates).
// Использует service role — обходит 400/401 при прямом запросе с клиента (RLS/auth).
// Не использует AI, без лимитов.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { tryParseByStoredTemplates } from "../_shared/try_stored_ttk_templates.ts";
import {
  enforceRateLimit,
  getAuthenticatedUserId,
  isServiceRoleBearer,
  isServiceRoleRequest,
  resolveCorsHeaders,
} from "../_shared/security.ts";

function corsHeaders(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin || "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
}

Deno.serve(async (req: Request) => {
  const cors = resolveCorsHeaders(req);
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders(req.headers.get("Origin")) });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  }

  const uid = await getAuthenticatedUserId(req);
  const isService = isServiceRoleRequest(req) || isServiceRoleBearer(req);
  if (!isService && !uid) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
  if (!enforceRateLimit(req, "parse-ttk-by-templates", { windowMs: 60_000, maxRequests: 60 })) {
    return new Response(JSON.stringify({ error: "Too many requests" }), {
      status: 429,
      headers: { ...cors, "Content-Type": "application/json" },
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
    if (result && result.cards.length > 0) {
      const first = result.cards[0];
      const ingr = (first?.ingredients ?? []).slice(0, 5).map((i) => `${i.productName?.slice(0, 15)}: gross=${i.grossGrams} net=${i.netGrams}`);
      console.log("[parse-ttk] cards=" + result.cards.length + " dish=" + (first?.dishName ?? "") + " ingr=" + JSON.stringify(ingr));
    }
    if (!result || result.cards.length === 0) {
      const headerRow = rows.find((r) => r.some((c) => /наименование|брутто|продукт/i.test(String(c))));
      console.log("[parse-ttk] no match: rows=" + rows.length + " header_sample=" + (headerRow?.slice(0, 5).join("|") ?? ""));
      return new Response(JSON.stringify({ cards: null }), {
        status: 200,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    const normalized = result.cards.map((card) => ({
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
      })),
    }));

    const sanityIssues = result.sanityIssues ?? [];
    return new Response(JSON.stringify({
      cards: normalized,
      header_signature: result.headerSignature,
      sanity_issues: sanityIssues,
    }), {
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
