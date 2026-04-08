// Edge: сохранение документа приёмки поставки (payload с клиента) — рассылка получателям как у заказов.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  enforceRateLimit,
  getAuthenticatedUserId,
  isServiceRoleBearer,
  isServiceRoleRequest,
  resolveCorsHeaders,
} from "../_shared/security.ts";

function isApproverOnDevice(roles: unknown, department: string): boolean {
  const r = Array.isArray(roles) ? (roles as string[]) : [];
  if (r.includes("executive_chef") || r.includes("sous_chef")) return true;
  if (r.includes("owner") || r.includes("general_manager")) return true;
  const d = (department || "kitchen").toLowerCase();
  if (d === "bar" && r.includes("bar_manager")) return true;
  return false;
}

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
  const authUid = await getAuthenticatedUserId(req);
  const isService = isServiceRoleRequest(req) || isServiceRoleBearer(req);
  if (!isService && !authUid) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
  if (!enforceRateLimit(req, "save-procurement-receipt", { windowMs: 60_000, maxRequests: 40 })) {
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
      createdByEmployeeId?: string;
      payload?: Record<string, unknown>;
      sourceOrderDocumentId?: string | null;
      /** Строки для согласования цен (только если приёмку делает не шеф/не владелец с полномочиями на устройстве). */
      priceApprovalLines?: unknown[];
      nomenclatureEstablishmentId?: string | null;
    };

    const {
      establishmentId,
      createdByEmployeeId,
      payload,
      sourceOrderDocumentId,
      priceApprovalLines,
      nomenclatureEstablishmentId,
    } = body;

    if (!establishmentId || !createdByEmployeeId || !payload || typeof payload !== "object") {
      return new Response(
        JSON.stringify({ error: "establishmentId, createdByEmployeeId, payload required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);
    if (!isService) {
      if (!authUid) {
        return new Response(
          JSON.stringify({ error: "Authenticated user required" }),
          { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
      if (createdByEmployeeId !== authUid) {
        return new Response(
          JSON.stringify({ error: "createdByEmployeeId must match authenticated user" }),
          { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }
    const { data: creator, error: creatorError } = await supabase
      .from("employees")
      .select("id")
      .eq("id", createdByEmployeeId)
      .eq("establishment_id", establishmentId)
      .maybeSingle();
    if (creatorError || !creator?.id) {
      return new Response(
        JSON.stringify({ error: "Invalid employee for establishment" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const { data: empRows } = await supabase
      .from("employees")
      .select("id, email, roles")
      .eq("establishment_id", establishmentId);

    const recipientRoles = ["owner", "executive_chef", "sous_chef"];
    const recipients = (empRows || []).filter((e: { id: string; email?: string; roles?: string[] }) => {
      const roles = Array.isArray(e.roles) ? e.roles : [];
      return roles.some((r: string) => recipientRoles.includes(r));
    });

    if (recipients.length === 0) {
      const { data: estab } = await supabase
        .from("establishments")
        .select("owner_id")
        .eq("id", establishmentId)
        .single();
      const ownerId = estab?.owner_id;
      if (ownerId) {
        const { data: owner } = await supabase
          .from("employees")
          .select("id, email")
          .eq("id", ownerId)
          .single();
        if (owner) recipients.push(owner);
      }
    }

    if (recipients.length === 0) {
      const { data: creatorEmp } = await supabase
        .from("employees")
        .select("id, email")
        .eq("id", createdByEmployeeId)
        .single();
      if (creatorEmp) recipients.push(creatorEmp);
    }

    if (recipients.length === 0) {
      recipients.push({ id: createdByEmployeeId, email: "" });
    }

    const seen = new Set<string>();
    const unique = recipients.filter((r: { id: string }) => {
      if (seen.has(r.id)) return false;
      seen.add(r.id);
      return true;
    });

    const srcId =
      sourceOrderDocumentId && typeof sourceOrderDocumentId === "string" && sourceOrderDocumentId.length > 0
        ? sourceOrderDocumentId
        : null;

    const rows = unique.map((r: { id: string; email?: string }) => ({
      establishment_id: establishmentId,
      created_by_employee_id: createdByEmployeeId,
      recipient_chef_id: r.id,
      recipient_email: r.email ?? "",
      payload,
      source_order_document_id: srcId,
    }));

    const { data: inserted, error } = await supabase
      .from("procurement_receipt_documents")
      .insert(rows)
      .select("id")
      .limit(1);

    if (error) {
      console.error("procurement_receipt_documents insert error:", error);
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const firstId = Array.isArray(inserted) && inserted.length > 0 ? (inserted[0] as { id: string })?.id : null;

    let priceApprovalInserted = false;
    const lines = Array.isArray(priceApprovalLines) ? priceApprovalLines : [];
    const nomEst =
      typeof nomenclatureEstablishmentId === "string" && nomenclatureEstablishmentId.length > 0
        ? nomenclatureEstablishmentId
        : null;
    if (lines.length > 0 && nomEst && firstId) {
      const { data: creatorEmp } = await supabase
        .from("employees")
        .select("roles")
        .eq("id", createdByEmployeeId)
        .maybeSingle();
      const payloadHeader = (payload?.header ?? {}) as Record<string, unknown>;
      const dept = String(payloadHeader["department"] ?? "kitchen");
      if (!isApproverOnDevice(creatorEmp?.roles, dept)) {
        const { error: apprErr } = await supabase.from("procurement_price_approval_requests").insert({
          establishment_id: establishmentId,
          receipt_document_id: firstId,
          nomenclature_establishment_id: nomEst,
          created_by_employee_id: createdByEmployeeId,
          status: "pending",
          lines,
        });
        if (apprErr) {
          console.error("procurement_price_approval_requests insert:", apprErr);
        } else {
          priceApprovalInserted = true;
        }
      }
    }

    return new Response(
      JSON.stringify({ ok: true, id: firstId, priceApprovalInserted }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (e) {
    console.error("save-procurement-receipt error:", e);
    return new Response(
      JSON.stringify({ error: String(e) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
