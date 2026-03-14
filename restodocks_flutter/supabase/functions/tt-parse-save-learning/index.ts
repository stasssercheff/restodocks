// Edge Function: сохранение обучения парсера ТТК (service_role, обход RLS)
// Вызывается клиентом при успешном парсинге и при правках пользователя
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function corsHeaders(origin: string | null): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": origin || "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
}

Deno.serve(async (req: Request) => {
  const cors = corsHeaders(req.headers.get("Origin"));
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: cors });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    return new Response(JSON.stringify({ error: "Server configuration error" }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const supabase = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });

  let body: Record<string, unknown>;
  try {
    const parsed = await req.json();
    body = parsed && typeof parsed === "object" ? parsed : {};
  } catch (parseErr) {
    console.error("[tt-parse-save-learning] JSON parse error:", parseErr);
    return new Response(
      JSON.stringify({ error: "Invalid JSON", details: [String(parseErr)] }),
      { status: 400, headers: { ...cors, "Content-Type": "application/json" } }
    );
  }

  const keys = Object.keys(body).filter((k) => body[k] != null);
  console.log("[tt-parse-save-learning] body keys:", keys.join(","));

  try {
    const errors: string[] = [];

    // 1. Шаблон (tt_parse_templates)
    if (body.template && typeof body.template === "object") {
      const t = body.template as Record<string, unknown>;
      const sig = t.header_signature as string;
      if (sig) {
        const payload: Record<string, unknown> = {
          header_signature: sig,
          header_row_index: t.header_row_index ?? 0,
          name_col: t.name_col ?? 0,
          product_col: t.product_col ?? 1,
          gross_col: t.gross_col ?? -1,
          net_col: t.net_col ?? -1,
          waste_col: t.waste_col ?? -1,
          output_col: t.output_col ?? -1,
          source: t.source ?? null,
        };
        if (t.technology_col != null) payload.technology_col = t.technology_col;
        const { error } = await supabase.from("tt_parse_templates").upsert(payload, {
          onConflict: "header_signature",
        });
        if (error) {
          console.error("[tt-parse-save-learning] template upsert error:", error);
          errors.push(`template: ${error.message}`);
        }
      }
    }

    // 2. Выученная позиция названия (tt_parse_learned_dish_name)
    if (body.learned_dish_name && typeof body.learned_dish_name === "object") {
      const l = body.learned_dish_name as Record<string, unknown>;
      const sig = l.header_signature as string;
      if (sig) {
        const payload: Record<string, unknown> = {
          header_signature: sig,
          dish_name_row_offset: l.dish_name_row_offset ?? 0,
          dish_name_col: l.dish_name_col ?? 0,
        };
        if (l.product_col != null) payload.product_col = l.product_col;
        if (l.gross_col != null) payload.gross_col = l.gross_col;
        if (l.net_col != null) payload.net_col = l.net_col;
        if (l.technology_col != null) payload.technology_col = l.technology_col;
        const { error } = await supabase.from("tt_parse_learned_dish_name").upsert(payload, {
          onConflict: "header_signature",
        });
        if (error) {
          console.error("[tt-parse-save-learning] learned_dish_name upsert error:", error);
          errors.push(`learned_dish_name: ${error.message}`);
        }
      }
    }

    // 3. Правка (tt_parse_corrections)
    if (body.correction && typeof body.correction === "object") {
      const c = body.correction as Record<string, unknown>;
      const sig = c.header_signature as string;
      const field = c.field as string;
      const corrected = c.corrected_value as string;
      if (sig && field && corrected) {
        const { error } = await supabase.from("tt_parse_corrections").insert({
          establishment_id: c.establishment_id ?? null,
          header_signature: sig,
          field,
          original_value: c.original_value ?? null,
          corrected_value: corrected,
        });
        if (error) {
          console.error("[tt-parse-save-learning] correction insert error:", error);
          errors.push(`correction: ${error.message}`);
        }
      }
    }

    if (errors.length > 0) {
      console.error("[tt-parse-save-learning] save_failed:", errors);
      return new Response(
        JSON.stringify({ error: "save_failed", details: errors }),
        { status: 500, headers: { ...cors, "Content-Type": "application/json" } }
      );
    }

    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("[tt-parse-save-learning] error:", e);
    return new Response(
      JSON.stringify({ error: String(e) }),
      { status: 500, headers: { ...cors, "Content-Type": "application/json" } }
    );
  }
});
