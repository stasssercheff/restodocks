// Edge Function: сохранение обучения парсера ТТК (service_role, обход RLS)
// Вызывается клиентом при успешном парсинге и при правках пользователя
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  enforceRateLimit,
  hasValidApiKeyOrUser,
  resolveCorsHeaders,
} from "../_shared/security.ts";

Deno.serve(async (req: Request) => {
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
  if (!enforceRateLimit(req, "tt-parse-save-learning", { windowMs: 60_000, maxRequests: 25 })) {
    return new Response(JSON.stringify({ error: "Too many requests" }), {
      status: 429,
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
        // ВАЖНО: не перезатирать уже рабочие шаблоны новым "обучением" от странного файла.
        // Обновляем только пустые/-1 поля. Это предотвращает "дрейф" и поломку старых форматов.
        const { data: existing, error: selErr } = await supabase
          .from("tt_parse_templates")
          .select("header_signature, header_row_index, name_col, product_col, gross_col, net_col, waste_col, output_col, technology_col, source")
          .eq("header_signature", sig)
          .limit(1)
          .maybeSingle();
        if (selErr) {
          console.error("[tt-parse-save-learning] template select error:", selErr);
          errors.push(`template_select: ${selErr.message}`);
        } else {
          const ex = (existing ?? {}) as Record<string, unknown>;
          const pickNum = (key: string, fallback: number) => {
            const v = ex[key];
            return typeof v === "number" ? v : fallback;
          };
          const exHeader = pickNum("header_row_index", 0);
          const exName = pickNum("name_col", 0);
          const exProduct = pickNum("product_col", 1);
          const exGross = pickNum("gross_col", -1);
          const exNet = pickNum("net_col", -1);
          const exWaste = pickNum("waste_col", -1);
          const exOutput = pickNum("output_col", -1);
          const exTech = pickNum("technology_col", -1);
          const exSource = (typeof ex["source"] === "string" ? (ex["source"] as string) : null);

          const inNum = (k: string, def: number) => {
            const v = t[k];
            return typeof v === "number" ? v : def;
          };
          const inSource = typeof t.source === "string" ? t.source : null;

          const payload: Record<string, unknown> = {
            header_signature: sig,
            header_row_index: exHeader > 0 ? exHeader : inNum("header_row_index", 0),
            name_col: exName >= 0 ? exName : inNum("name_col", 0),
            product_col: exProduct >= 0 ? exProduct : inNum("product_col", 1),
            gross_col: exGross >= 0 ? exGross : inNum("gross_col", -1),
            net_col: exNet >= 0 ? exNet : inNum("net_col", -1),
            waste_col: exWaste >= 0 ? exWaste : inNum("waste_col", -1),
            output_col: exOutput >= 0 ? exOutput : inNum("output_col", -1),
            source: exSource ?? inSource,
          };
          const techIn = inNum("technology_col", -1);
          if (exTech >= 0) payload.technology_col = exTech;
          else if (techIn >= 0) payload.technology_col = techIn;

          const { error } = await supabase.from("tt_parse_templates").upsert(payload, {
            onConflict: "header_signature",
          });
          if (error) {
            console.error("[tt-parse-save-learning] template upsert error:", error);
            errors.push(`template: ${error.message}`);
          }
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
        } else {
          // Критично для обучения: tryParseByStoredTemplates ищет шаблон по header_signature.
          // Если шаблона нет (новый формат, парсинг был через AI) — следующий импорт снова шёл бы в AI.
          // Создаём минимальный шаблон из выученных колонок, чтобы следующий импорт того же формата
          // сразу парсился по шаблону с учётом правок пользователя.
          const { data: existingTemplate } = await supabase
            .from("tt_parse_templates")
            .select("header_signature")
            .eq("header_signature", sig)
            .limit(1)
            .maybeSingle();
          if (!existingTemplate) {
            const pCol = typeof l.product_col === "number" ? l.product_col : 1;
            const gCol = typeof l.gross_col === "number" ? l.gross_col : -1;
            const nCol = typeof l.net_col === "number" ? l.net_col : -1;
            const tCol = typeof l.technology_col === "number" ? l.technology_col : -1;
            const { error: tmplErr } = await supabase.from("tt_parse_templates").upsert({
              header_signature: sig,
              header_row_index: 0,
              name_col: typeof l.dish_name_col === "number" ? l.dish_name_col : 0,
              product_col: pCol >= 0 ? pCol : 1,
              gross_col: gCol,
              net_col: nCol,
              waste_col: -1,
              output_col: -1,
              technology_col: tCol >= 0 ? tCol : -1,
              source: "user_learning",
            }, { onConflict: "header_signature" });
            if (tmplErr) {
              console.error("[tt-parse-save-learning] template ensure-from-learned error:", tmplErr);
              errors.push(`template_ensure: ${tmplErr.message}`);
            } else {
              console.log("[tt-parse-save-learning] created template from learned_dish_name for", sig);
            }
          }
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
