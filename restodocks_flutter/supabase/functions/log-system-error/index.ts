// Запись в system_errors с сервера (Edge / cron / внешние вызовы).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  enforceRateLimit,
  getAuthenticatedUserId,
  isServiceRoleBearer,
  isServiceRoleRequest,
  resolveCorsHeaders,
} from "../_shared/security.ts";

Deno.serve(async (req: Request) => {
  const corsHeaders = resolveCorsHeaders(req);
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
  const userId = await getAuthenticatedUserId(req);
  const isService = isServiceRoleRequest(req) || isServiceRoleBearer(req);
  if (!isService && !userId) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
  if (!enforceRateLimit(req, "log-system-error", { windowMs: 60_000, maxRequests: 60 })) {
    return new Response(JSON.stringify({ error: "Too many requests" }), {
      status: 429,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  try {
    const body = (await req.json()) as {
      establishmentId?: string;
      message?: string;
      severity?: string;
      source?: string;
      context?: Record<string, unknown>;
      employeeId?: string | null;
      posOrderId?: string | null;
      posOrderLineId?: string | null;
      diningTableId?: string | null;
    };

    const establishmentId = body.establishmentId?.trim();
    const message = body.message?.trim();
    if (!establishmentId || !message) {
      return new Response(
        JSON.stringify({ error: "establishmentId and message required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const sev = body.severity === "warning" || body.severity === "critical"
      ? body.severity
      : "error";
    const src = (body.source && body.source.length > 0) ? body.source : "edge";

    const supabase = createClient(supabaseUrl, supabaseServiceKey);
    const { data: est } = await supabase
      .from("establishments")
      .select("id, owner_id")
      .eq("id", establishmentId)
      .maybeSingle();
    if (!est?.id) {
      return new Response(JSON.stringify({ error: "Invalid establishment" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    if (!isService && userId) {
      const { data: emp } = await supabase
        .from("employees")
        .select("id")
        .eq("id", userId)
        .eq("establishment_id", establishmentId)
        .maybeSingle();
      const isOwner = String(est.owner_id ?? "") === userId;
      if (!emp?.id && !isOwner) {
        return new Response(JSON.stringify({ error: "Forbidden for establishment" }), {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    }

    const row: Record<string, unknown> = {
      establishment_id: establishmentId,
      severity: sev,
      source: src,
      message: message.length > 8000 ? message.slice(0, 8000) : message,
      context: body.context ?? {},
    };
    if (body.employeeId) row.employee_id = body.employeeId;
    if (body.posOrderId) row.pos_order_id = body.posOrderId;
    if (body.posOrderLineId) row.pos_order_line_id = body.posOrderLineId;
    if (body.diningTableId) row.dining_table_id = body.diningTableId;

    const { data, error } = await supabase.from("system_errors").insert(row).select("id").single();
    if (error) {
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    return new Response(JSON.stringify({ ok: true, id: data?.id }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return new Response(JSON.stringify({ error: msg }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
