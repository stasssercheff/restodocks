// Edge Function: сохранение чеклиста через service role (обходит RLS и права RPC).
// Используется при legacy-логине (auth: false).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function corsHeaders(origin: string | null): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": origin || "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
}

interface ChecklistItemInput {
  title?: string;
  sort_order?: number;
  tech_card_id?: string | null;
  target_quantity?: number | null;
  target_unit?: string | null;
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

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  if (!supabaseUrl || !supabaseServiceKey) {
    return new Response(JSON.stringify({ error: "Server configuration error" }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const supabase = createClient(supabaseUrl, supabaseServiceKey, {
    auth: { persistSession: false },
  });

  try {
    const body = (await req.json()) as {
      checklist_id?: string;
      name?: string;
      updated_at?: string;
      action_config?: Record<string, unknown>;
      assigned_department?: string;
      assigned_section?: string | null;
      assigned_employee_id?: string | null;
      assigned_employee_ids?: string[];
      deadline_at?: string | null;
      scheduled_for_at?: string | null;
      additional_name?: string | null;
      type?: string | null;
      items?: ChecklistItemInput[];
    };

    const {
      checklist_id,
      name,
      updated_at,
      action_config,
      assigned_department,
      assigned_section,
      assigned_employee_id,
      assigned_employee_ids,
      deadline_at,
      scheduled_for_at,
      additional_name,
      type,
      items = [],
    } = body;

    if (!checklist_id || !name || !updated_at) {
      return new Response(
        JSON.stringify({ error: "checklist_id, name, updated_at required" }),
        { status: 400, headers: { ...cors, "Content-Type": "application/json" } }
      );
    }

    const { error: updateError } = await supabase
      .from("checklists")
      .update({
        name: String(name),
        updated_at: updated_at,
        action_config: action_config ?? { has_numeric: false, has_toggle: true },
        assigned_department: assigned_department?.trim() || "kitchen",
        assigned_section: assigned_section || null,
        assigned_employee_id: assigned_employee_id || null,
        assigned_employee_ids: assigned_employee_ids ?? [],
        deadline_at: deadline_at || null,
        scheduled_for_at: scheduled_for_at || null,
        additional_name: additional_name || null,
        type: type || null,
      })
      .eq("id", checklist_id);

    if (updateError) {
      console.error("[save-checklist] UPDATE error:", updateError);
      return new Response(
        JSON.stringify({ error: updateError.message }),
        { status: 500, headers: { ...cors, "Content-Type": "application/json" } }
      );
    }

    const { error: deleteError } = await supabase
      .from("checklist_items")
      .delete()
      .eq("checklist_id", checklist_id);

    if (deleteError) {
      console.error("[save-checklist] DELETE items error:", deleteError);
      return new Response(
        JSON.stringify({ error: deleteError.message }),
        { status: 500, headers: { ...cors, "Content-Type": "application/json" } }
      );
    }

    for (let i = 0; i < items.length; i++) {
      const it = items[i];
      const techCardId = it.tech_card_id?.trim();
      const targetQty = it.target_quantity != null ? Number(it.target_quantity) : null;
      const targetUnit = it.target_unit?.trim() || null;

      const { error: insertError } = await supabase.from("checklist_items").insert({
        checklist_id,
        title: it.title ?? "",
        sort_order: it.sort_order ?? i,
        tech_card_id: techCardId && techCardId !== "" ? techCardId : null,
        target_quantity: targetQty,
        target_unit: targetUnit,
      });

      if (insertError) {
        console.error("[save-checklist] INSERT item error:", insertError);
        return new Response(
          JSON.stringify({ error: insertError.message }),
          { status: 500, headers: { ...cors, "Content-Type": "application/json" } }
        );
      }
    }

    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("[save-checklist] Unexpected error:", e);
    return new Response(
      JSON.stringify({ error: String(e) }),
      { status: 500, headers: { ...cors, "Content-Type": "application/json" } }
    );
  }
});
