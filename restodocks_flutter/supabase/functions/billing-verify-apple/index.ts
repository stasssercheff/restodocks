// Edge Function: server-side validation Apple receipt -> единый Pro-статус заведения.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  enforceRateLimit,
  getAuthenticatedUserId,
  isServiceRoleBearer,
  isServiceRoleRequest,
  resolveCorsHeaders,
} from "../_shared/security.ts";

type AppleVerifyReceiptResponse = {
  status?: number;
  environment?: string;
  latest_receipt_info?: Array<Record<string, unknown>>;
  receipt?: {
    in_app?: Array<Record<string, unknown>>;
  };
};

function parseRoles(raw: unknown): string[] {
  if (Array.isArray(raw)) return raw.map((r) => String(r).toLowerCase().trim());
  if (typeof raw === "string") {
    return raw
      .split(",")
      .map((r) => r.toLowerCase().trim())
      .filter(Boolean);
  }
  return [];
}

async function verifyReceiptWithApple(
  receiptData: string,
  sharedSecret: string,
): Promise<AppleVerifyReceiptResponse> {
  const payload = {
    "receipt-data": receiptData,
    password: sharedSecret,
    "exclude-old-transactions": true,
  };

  const prodRes = await fetch("https://buy.itunes.apple.com/verifyReceipt", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  const prodJson = (await prodRes.json()) as AppleVerifyReceiptResponse;
  if (prodJson.status === 21007) {
    const sandboxRes = await fetch("https://sandbox.itunes.apple.com/verifyReceipt", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    return (await sandboxRes.json()) as AppleVerifyReceiptResponse;
  }
  return prodJson;
}

function extractMaxExpiryMs(data: AppleVerifyReceiptResponse): number | null {
  const candidateRows = [
    ...(data.latest_receipt_info ?? []),
    ...((data.receipt?.in_app as Array<Record<string, unknown>> | undefined) ?? []),
  ];
  let maxMs: number | null = null;
  for (const row of candidateRows) {
    const value = row["expires_date_ms"];
    if (value == null) continue;
    const ms = Number(value);
    if (!Number.isFinite(ms) || ms <= 0) continue;
    if (maxMs == null || ms > maxMs) maxMs = ms;
  }
  return maxMs;
}

Deno.serve(async (req: Request) => {
  const cors = resolveCorsHeaders(req);
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
  const authUid = await getAuthenticatedUserId(req);
  const isService = isServiceRoleRequest(req) || isServiceRoleBearer(req);
  if (!isService && !authUid) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
  if (!enforceRateLimit(req, "billing-verify-apple", { windowMs: 60_000, maxRequests: 20 })) {
    return new Response(JSON.stringify({ error: "Too many requests" }), {
      status: 429,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const appleSharedSecret = Deno.env.get("APPLE_IAP_SHARED_SECRET") ?? "";
  if (!supabaseUrl || !serviceKey || !appleSharedSecret) {
    return new Response(JSON.stringify({ error: "Server configuration error" }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const supabase = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    const body = (await req.json()) as {
      establishment_id?: string;
      receipt_data?: string;
    };
    const establishmentId = String(body.establishment_id ?? "").trim();
    const receiptData = String(body.receipt_data ?? "").trim();
    if (!establishmentId || !receiptData) {
      return new Response(JSON.stringify({ error: "establishment_id and receipt_data are required" }), {
        status: 400,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    if (!isService) {
      if (!authUid) {
        return new Response(JSON.stringify({ error: "Authenticated user required" }), {
          status: 401,
          headers: { ...cors, "Content-Type": "application/json" },
        });
      }
      const { data: caller, error: callerError } = await supabase
        .from("employees")
        .select("id, roles, establishment_id")
        .eq("establishment_id", establishmentId)
        .or(`id.eq.${authUid},auth_user_id.eq.${authUid}`)
        .maybeSingle();
      if (callerError || !caller?.id) {
        return new Response(JSON.stringify({ error: "Forbidden for establishment" }), {
          status: 403,
          headers: { ...cors, "Content-Type": "application/json" },
        });
      }
      const roles = parseRoles(caller.roles);
      if (!roles.includes("owner")) {
        return new Response(JSON.stringify({ error: "Only owner can verify subscription" }), {
          status: 403,
          headers: { ...cors, "Content-Type": "application/json" },
        });
      }
    }

    const appleResp = await verifyReceiptWithApple(receiptData, appleSharedSecret);
    if (appleResp.status !== 0) {
      return new Response(JSON.stringify({ error: "Apple receipt validation failed", status: appleResp.status }), {
        status: 400,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    const expiryMs = extractMaxExpiryMs(appleResp);
    const nowMs = Date.now();
    const isActive = expiryMs != null && expiryMs > nowMs;
    const paidUntilIso = expiryMs != null ? new Date(expiryMs).toISOString() : null;

    const updatePayload = isActive
      ? { subscription_type: "pro", pro_paid_until: paidUntilIso }
      : { subscription_type: "free", pro_paid_until: paidUntilIso };

    const { error: updateError } = await supabase
      .from("establishments")
      .update(updatePayload)
      .eq("id", establishmentId);
    if (updateError) {
      return new Response(JSON.stringify({ error: updateError.message }), {
        status: 500,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    const { data: statusRows, error: statusError } = await supabase
      .rpc("get_establishment_pro_status", { p_establishment_id: establishmentId });
    if (statusError) {
      return new Response(JSON.stringify({ error: statusError.message }), {
        status: 500,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({
      ok: true,
      is_active: isActive,
      pro_paid_until: paidUntilIso,
      apple_environment: appleResp.environment ?? null,
      status: Array.isArray(statusRows) && statusRows.length > 0 ? statusRows[0] : null,
    }), {
      status: 200,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
});
