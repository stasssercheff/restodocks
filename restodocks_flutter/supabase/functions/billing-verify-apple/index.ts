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
  /** Автопродления; здесь же grace period при проблеме с оплатой (Connect → Grace Period). */
  pending_renewal_info?: Array<Record<string, unknown>>;
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

const VERIFY_PROD = "https://buy.itunes.apple.com/verifyReceipt";
const VERIFY_SANDBOX = "https://sandbox.itunes.apple.com/verifyReceipt";

async function verifyReceiptWithApple(
  receiptData: string,
  sharedSecret: string,
): Promise<AppleVerifyReceiptResponse> {
  const payload = {
    "receipt-data": receiptData,
    password: sharedSecret,
    "exclude-old-transactions": true,
  };

  const post = async (url: string): Promise<AppleVerifyReceiptResponse> => {
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    return (await res.json()) as AppleVerifyReceiptResponse;
  };

  // Стандарт Apple: сначала production; 21007 = чек из Sandbox (TestFlight/локальные тесты).
  let json = await post(VERIFY_PROD);
  if (json.status === 21007) {
    json = await post(VERIFY_SANDBOX);
  }
  // 21008 = production-чек отправили на sandbox URL (редко; бывает при смене окружения).
  if (json.status === 21008) {
    json = await post(VERIFY_PROD);
  }
  return json;
}

function toExpiresMs(raw: unknown): number | null {
  if (raw == null) return null;
  if (typeof raw === "number" && Number.isFinite(raw) && raw > 0) return raw;
  if (typeof raw === "string") {
    const t = raw.trim().replace(/\s/g, "");
    const n = Number(t);
    if (Number.isFinite(n) && n > 0) return n;
    // Apple иногда отдаёт только `expires_date` (ISO / RFC), без *_ms — в Sandbox чаще.
    const parsed = Date.parse(raw);
    if (!Number.isNaN(parsed)) return parsed;
  }
  return null;
}

const TARGET_PRODUCT_ID = "restodocks_pro_monthly";

function extractMaxExpiryMs(data: AppleVerifyReceiptResponse): number | null {
  let maxMs: number | null = null;
  const consider = (raw: unknown) => {
    const ms = toExpiresMs(raw);
    if (ms == null) return;
    if (maxMs == null || ms > maxMs) maxMs = ms;
  };

  const fromReceipt = [
    ...(data.latest_receipt_info ?? []),
    ...((data.receipt?.in_app as Array<Record<string, unknown>> | undefined) ?? []),
  ];
  const forOurProduct = fromReceipt.filter((row) =>
    String(row["product_id"] ?? "") === TARGET_PRODUCT_ID
  );
  const rows = forOurProduct.length > 0 ? forOurProduct : fromReceipt;

  for (const row of rows) {
    consider(row["expires_date_ms"]);
    consider(row["expires_date"]);
  }

  // Billing grace / retry: конец доступа может быть позже `expires_date_ms` строки подписки.
  for (const row of data.pending_renewal_info ?? []) {
    if (String(row["product_id"] ?? "") !== TARGET_PRODUCT_ID && forOurProduct.length > 0) {
      continue;
    }
    consider(row["grace_period_expires_date_ms"]);
    consider(row["grace_period_expires_date"]);
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

    // Не вызывать get_establishment_pro_status из Edge: RPC требует auth.uid(), а клиент
    // с SUPABASE_SERVICE_ROLE_KEY даёт в БД auth.uid() = NULL → всегда ошибка.
    const { data: estSnapshot } = await supabase
      .from("establishments")
      .select("subscription_type, pro_paid_until, pro_trial_ends_at")
      .eq("id", establishmentId)
      .maybeSingle();

    return new Response(JSON.stringify({
      ok: true,
      is_active: isActive,
      pro_paid_until: paidUntilIso,
      apple_environment: appleResp.environment ?? null,
      establishment: estSnapshot ?? null,
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
