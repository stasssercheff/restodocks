// Edge Function: server-side validation Apple receipt -> единый Pro-статус заведения.
//
// Продукт: подписка Apple ID привязана к одному заведению Restodocks (и тем самым к аккаунту владельца):
// клиент передаёт UUID заведения в StoreKit как applicationUserName; в чеке это application_username / app_account_token.
// Сервер отклоняет верификацию, если привязка в чеке ≠ запрошенное заведение (403), и не выдаёт Pro без
// подтверждённой привязки (claims по OTID или сильная привязка из чека).
//
// Тестовый режим (Edge Secrets в проекте Supabase):
//   IAP_BILLING_TEST_ESTABLISHMENT_IDS=uuid1,uuid2 — заведения, для которых после успешной верификации
//   через ~IAP_BILLING_TEST_RESET_MINUTES минут сбрасываются subscription_type / привязка apple_iap_subscription_claims
//   (удобно для повторных прогонов TestFlight). Нужны миграции: apple_iap_subscription_claims, iap_billing_test_state.
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
    const text = await res.text();
    try {
      return JSON.parse(text) as AppleVerifyReceiptResponse;
    } catch {
      throw new Error(`Apple verifyReceipt non-JSON (${res.status}): ${text.slice(0, 200)}`);
    }
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

function pickReceiptRows(data: AppleVerifyReceiptResponse): Array<Record<string, unknown>> {
  const fromReceipt = [
    ...(data.latest_receipt_info ?? []),
    ...((data.receipt?.in_app as Array<Record<string, unknown>> | undefined) ?? []),
  ];
  const forOurProduct = fromReceipt.filter((row) =>
    String(row["product_id"] ?? "") === TARGET_PRODUCT_ID
  );
  return forOurProduct.length > 0 ? forOurProduct : fromReceipt;
}

function rowExpiryMs(row: Record<string, unknown>): number | null {
  const a = toExpiresMs(row["expires_date_ms"]);
  const b = toExpiresMs(row["expires_date"]);
  if (a != null && b != null) return Math.max(a, b);
  return a ?? b;
}

/** Apple в JSON иногда отдаёт original_transaction_id числом. */
function rawOtid(row: Record<string, unknown>): string {
  const v = row["original_transaction_id"];
  if (v == null || v === "") return "";
  if (typeof v === "number" && Number.isFinite(v)) return String(Math.trunc(v));
  return String(v).trim();
}

/** Apple auto-renewable: стабильный идентификатор цепочки подписки (не путать с transaction_id). */
function extractOriginalTransactionId(data: AppleVerifyReceiptResponse): string | null {
  const rows = pickReceiptRows(data);
  const pending = (data.pending_renewal_info ?? []).filter((row) =>
    String(row["product_id"] ?? "") === TARGET_PRODUCT_ID ||
    rows.length === 0
  );
  const combined = [...rows, ...pending];

  let best: { ms: number; otid: string } | null = null;
  for (const row of combined) {
    const ms = rowExpiryMs(row);
    const otid = rawOtid(row);
    if (otid.length === 0) continue;
    if (ms != null) {
      if (best == null || ms > best.ms) best = { ms, otid };
    }
  }
  if (best != null) return best.otid;
  for (const row of combined) {
    const otid = rawOtid(row);
    if (otid.length > 0) return otid;
  }
  return null;
}

function normalizeEstId(s: string): string {
  return s.trim().toLowerCase().replace(/-/g, "");
}

function estIdsEqual(a: string, b: string): boolean {
  return normalizeEstId(a) === normalizeEstId(b);
}

/** UUID заведения из чека: StoreKit передаёт его как applicationUserName / app account token. */
function extractReceiptEstablishmentBinding(data: AppleVerifyReceiptResponse): string | null {
  const rows = pickReceiptRows(data);
  if (rows.length === 0) return null;
  let best: { ms: number; id: string } | null = null;
  for (const row of rows) {
    const ms = rowExpiryMs(row) ?? 0;
    const raw =
      row["app_account_token"] ??
      row["application_username"] ??
      row["appAccountToken"] ??
      row["applicationUsername"];
    if (raw == null) continue;
    const id = String(raw).trim();
    if (id.length === 0) continue;
    if (best == null || ms >= best.ms) best = { ms, id };
  }
  return best?.id ?? null;
}

function isMissingRelationError(err: { message?: string; code?: string; details?: string } | null): boolean {
  if (!err) return false;
  const m = (err.message ?? "").toLowerCase();
  const d = (err.details ?? "").toLowerCase();
  return (
    m.includes("does not exist") ||
    m.includes("schema cache") ||
    d.includes("does not exist") ||
    err.code === "42P01"
  );
}

function parseTestEstablishmentIds(): string[] {
  return (Deno.env.get("IAP_BILLING_TEST_ESTABLISHMENT_IDS") ?? "")
    .split(",")
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean);
}

function testResetMinutes(): number {
  const n = Number(Deno.env.get("IAP_BILLING_TEST_RESET_MINUTES") ?? "3");
  if (!Number.isFinite(n) || n < 1) return 3;
  if (n > 120) return 120;
  return Math.floor(n);
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
    console.error(
      JSON.stringify({
        fn: "billing-verify-apple",
        phase: "config_missing",
        has_supabase_url: Boolean(supabaseUrl),
        has_service_role: Boolean(serviceKey),
        has_apple_shared_secret: Boolean(appleSharedSecret),
      }),
    );
    return new Response(JSON.stringify({ error: "Server configuration error" }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const supabase = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    let body: { establishment_id?: string; receipt_data?: string };
    try {
      body = (await req.json()) as { establishment_id?: string; receipt_data?: string };
    } catch {
      return new Response(JSON.stringify({ error: "Invalid or empty JSON body" }), {
        status: 400,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }
    const establishmentId = String(body.establishment_id ?? "").trim();
    const receiptData = String(body.receipt_data ?? "").trim();
    if (!establishmentId || !receiptData) {
      return new Response(JSON.stringify({ error: "establishment_id and receipt_data are required" }), {
        status: 400,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    console.log(
      JSON.stringify({
        fn: "billing-verify-apple",
        phase: "start",
        establishment_id: establishmentId,
        receipt_len: receiptData.length,
        auth: isService ? "service" : (authUid ?? "none"),
      }),
    );

    if (!isService) {
      if (!authUid) {
        return new Response(JSON.stringify({ error: "Authenticated user required" }), {
          status: 401,
          headers: { ...cors, "Content-Type": "application/json" },
        });
      }
      // Два запроса вместо .or() в URL: PostgREST/прокси иногда криво кодирует UUID в or().
      let caller: { id: string; roles: unknown; establishment_id: string } | null = null;
      const sel = "id, roles, establishment_id";
      const { data: byId, error: errById } = await supabase
        .from("employees")
        .select(sel)
        .eq("establishment_id", establishmentId)
        .eq("id", authUid)
        .maybeSingle();
      if (errById && !isMissingRelationError(errById)) {
        return new Response(JSON.stringify({ error: errById.message }), {
          status: 500,
          headers: { ...cors, "Content-Type": "application/json" },
        });
      }
      if (byId?.id) {
        caller = byId as { id: string; roles: unknown; establishment_id: string };
      } else {
        const { data: byAuth, error: errAuth } = await supabase
          .from("employees")
          .select(sel)
          .eq("establishment_id", establishmentId)
          .eq("auth_user_id", authUid)
          .maybeSingle();
        if (errAuth && !isMissingRelationError(errAuth)) {
          return new Response(JSON.stringify({ error: errAuth.message }), {
            status: 500,
            headers: { ...cors, "Content-Type": "application/json" },
          });
        }
        if (byAuth?.id) {
          caller = byAuth as { id: string; roles: unknown; establishment_id: string };
        }
      }
      if (!caller?.id) {
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

    const testIds = parseTestEstablishmentIds();
    const isTestEst = testIds.includes(establishmentId.toLowerCase());
    const resetMin = testResetMinutes();

    if (isTestEst) {
      const { data: st, error: stErr } = await supabase
        .from("iap_billing_test_state")
        .select("last_success_at")
        .eq("establishment_id", establishmentId)
        .maybeSingle();
      if (!stErr && st?.last_success_at) {
        const elapsed = Date.now() - new Date(String(st.last_success_at)).getTime();
        if (elapsed >= resetMin * 60 * 1000) {
          const c1 = await supabase.from("apple_iap_subscription_claims").delete().eq("establishment_id", establishmentId);
          if (c1.error && !isMissingRelationError(c1.error)) {
            return new Response(JSON.stringify({ error: c1.error.message }), {
              status: 500,
              headers: { ...cors, "Content-Type": "application/json" },
            });
          }
          await supabase
            .from("establishments")
            .update({ subscription_type: "free", pro_paid_until: null })
            .eq("id", establishmentId);
          const c2 = await supabase.from("iap_billing_test_state").delete().eq("establishment_id", establishmentId);
          if (c2.error && !isMissingRelationError(c2.error)) {
            return new Response(JSON.stringify({ error: c2.error.message }), {
              status: 500,
              headers: { ...cors, "Content-Type": "application/json" },
            });
          }
        }
      } else if (stErr && !isMissingRelationError(stErr)) {
        return new Response(JSON.stringify({ error: stErr.message }), {
          status: 500,
          headers: { ...cors, "Content-Type": "application/json" },
        });
      }
    }

    let appleResp: AppleVerifyReceiptResponse;
    try {
      appleResp = await verifyReceiptWithApple(receiptData, appleSharedSecret);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error("billing-verify-apple: Apple verifyReceipt failed", msg);
      return new Response(
        JSON.stringify({ error: "Apple verifyReceipt request failed", detail: msg }),
        {
          status: 502,
          headers: { ...cors, "Content-Type": "application/json" },
        },
      );
    }
    if (appleResp.status !== 0) {
      return new Response(JSON.stringify({ error: "Apple receipt validation failed", status: appleResp.status }), {
        status: 400,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    const expiryMs = extractMaxExpiryMs(appleResp);
    const originalTransactionId = extractOriginalTransactionId(appleResp);
    const nowMs = Date.now();
    const isActive = expiryMs != null && expiryMs > nowMs;
    const paidUntilIso = expiryMs != null ? new Date(expiryMs).toISOString() : null;

    const receiptBindingEstId = extractReceiptEstablishmentBinding(appleResp);
    if (
      receiptBindingEstId != null &&
      receiptBindingEstId.length > 0 &&
      !estIdsEqual(receiptBindingEstId, establishmentId)
    ) {
      return new Response(
        JSON.stringify({ error: "receipt_bound_to_other_establishment" }),
        {
          status: 403,
          headers: { ...cors, "Content-Type": "application/json" },
        },
      );
    }

    const strongBinding =
      receiptBindingEstId != null &&
      receiptBindingEstId.length > 0 &&
      estIdsEqual(receiptBindingEstId, establishmentId);

    let claimsEnforced = true;
    let claimSkippedReason: string | null = null;

    if (isActive && (!originalTransactionId || originalTransactionId.length === 0)) {
      claimSkippedReason = "missing_original_transaction_id";
      claimsEnforced = false;
    }

    let allowProUpdate = false;
    if (isActive) {
      if (strongBinding) {
        allowProUpdate = true;
      } else {
        allowProUpdate = Boolean(
          claimsEnforced &&
            claimSkippedReason === null &&
            originalTransactionId &&
            originalTransactionId.length > 0,
        );
      }
      if (!allowProUpdate) {
        return new Response(
          JSON.stringify({
            error: "receipt_missing_app_account_binding",
            detail: claimSkippedReason ?? "cannot_verify_subscription_binding",
          }),
          {
            status: 400,
            headers: { ...cors, "Content-Type": "application/json" },
          },
        );
      }
    }

    if (isActive && originalTransactionId && originalTransactionId.length > 0) {
      const { data: rowByOtid, error: errByOtid } = await supabase
        .from("apple_iap_subscription_claims")
        .select("establishment_id")
        .eq("original_transaction_id", originalTransactionId)
        .maybeSingle();
      if (errByOtid) {
        if (isMissingRelationError(errByOtid)) {
          claimsEnforced = false;
          claimSkippedReason = "claims_table_unavailable";
        } else {
          return new Response(JSON.stringify({ error: errByOtid.message }), {
            status: 500,
            headers: { ...cors, "Content-Type": "application/json" },
          });
        }
      } else if (claimsEnforced && rowByOtid && !estIdsEqual(String(rowByOtid.establishment_id), establishmentId)) {
        return new Response(
          JSON.stringify({
            error: "apple_subscription_already_linked",
            linked_establishment_id: rowByOtid.establishment_id,
          }),
          {
            status: 409,
            headers: { ...cors, "Content-Type": "application/json" },
          },
        );
      }

      const { error: delMine } = await supabase
        .from("apple_iap_subscription_claims")
        .delete()
        .eq("establishment_id", establishmentId);
      if (delMine) {
        if (isMissingRelationError(delMine)) {
          claimsEnforced = false;
          claimSkippedReason = "claims_table_unavailable";
        } else {
          return new Response(JSON.stringify({ error: delMine.message }), {
            status: 500,
            headers: { ...cors, "Content-Type": "application/json" },
          });
        }
      }
      if (claimsEnforced) {
        const { error: insErr } = await supabase.from("apple_iap_subscription_claims").insert({
          original_transaction_id: originalTransactionId,
          establishment_id: establishmentId,
        });
        if (insErr) {
          if (isMissingRelationError(insErr)) {
            claimsEnforced = false;
            claimSkippedReason = "claims_table_unavailable";
          } else if (
            insErr.code === "23505" ||
            (insErr.message ?? "").toLowerCase().includes("duplicate key")
          ) {
            return new Response(
              JSON.stringify({
                error: "apple_subscription_already_linked",
                detail: insErr.message ?? "duplicate key",
              }),
              {
                status: 409,
                headers: { ...cors, "Content-Type": "application/json" },
              },
            );
          } else {
            return new Response(JSON.stringify({ error: insErr.message }), {
              status: 500,
              headers: { ...cors, "Content-Type": "application/json" },
            });
          }
        }
      }

      if (!strongBinding && (!claimsEnforced || claimSkippedReason != null)) {
        return new Response(
          JSON.stringify({
            error: "receipt_missing_app_account_binding",
            detail: claimSkippedReason ?? "claims_unavailable",
          }),
          {
            status: 400,
            headers: { ...cors, "Content-Type": "application/json" },
          },
        );
      }
    }

    if (!isActive) {
      let allowDowngradeUpdate = false;
      if (strongBinding) {
        allowDowngradeUpdate = true;
      } else if (originalTransactionId && originalTransactionId.length > 0) {
        const { data: clRow, error: errCl } = await supabase
          .from("apple_iap_subscription_claims")
          .select("establishment_id")
          .eq("original_transaction_id", originalTransactionId)
          .maybeSingle();
        if (errCl && !isMissingRelationError(errCl)) {
          return new Response(JSON.stringify({ error: errCl.message }), {
            status: 500,
            headers: { ...cors, "Content-Type": "application/json" },
          });
        }
        if (clRow && estIdsEqual(String(clRow.establishment_id), establishmentId)) {
          allowDowngradeUpdate = true;
        }
      }
      if (!allowDowngradeUpdate) {
        const { data: estSnapshot } = await supabase
          .from("establishments")
          .select("subscription_type, pro_paid_until, pro_trial_ends_at")
          .eq("id", establishmentId)
          .maybeSingle();
        return new Response(
          JSON.stringify({
            ok: true,
            is_active: false,
            applied: false,
            reason: "receipt_does_not_apply_to_establishment",
            pro_paid_until: paidUntilIso,
            establishment: estSnapshot ?? null,
          }),
          {
            status: 200,
            headers: { ...cors, "Content-Type": "application/json" },
          },
        );
      }
      if (originalTransactionId && originalTransactionId.length > 0) {
        const { error: delExp } = await supabase
          .from("apple_iap_subscription_claims")
          .delete()
          .eq("original_transaction_id", originalTransactionId)
          .eq("establishment_id", establishmentId);
        if (delExp && !isMissingRelationError(delExp)) {
          return new Response(JSON.stringify({ error: delExp.message }), {
            status: 500,
            headers: { ...cors, "Content-Type": "application/json" },
          });
        }
      }
    }

    const nowIso = new Date().toISOString();
    const updatePayload = isActive
      ? { subscription_type: "pro", pro_paid_until: paidUntilIso, updated_at: nowIso }
      : { subscription_type: "free", pro_paid_until: paidUntilIso, updated_at: nowIso };

    const { error: updateError } = await supabase
      .from("establishments")
      .update(updatePayload)
      .eq("id", establishmentId);
    if (updateError) {
      console.error("billing-verify-apple: establishments update failed", updateError);
      return new Response(
        JSON.stringify({
          error: updateError.message,
          code: updateError.code ?? null,
          hint: updateError.hint ?? null,
        }),
        {
          status: 500,
          headers: { ...cors, "Content-Type": "application/json" },
        },
      );
    }

    if (isTestEst) {
      if (isActive) {
        const { error: upTest } = await supabase.from("iap_billing_test_state").upsert({
          establishment_id: establishmentId,
          last_success_at: new Date().toISOString(),
        });
        if (upTest && !isMissingRelationError(upTest)) {
          return new Response(JSON.stringify({ error: upTest.message }), {
            status: 500,
            headers: { ...cors, "Content-Type": "application/json" },
          });
        }
      } else {
        const { error: delTestSt } = await supabase
          .from("iap_billing_test_state")
          .delete()
          .eq("establishment_id", establishmentId);
        if (delTestSt && !isMissingRelationError(delTestSt)) {
          return new Response(JSON.stringify({ error: delTestSt.message }), {
            status: 500,
            headers: { ...cors, "Content-Type": "application/json" },
          });
        }
      }
    }

    // Не вызывать get_establishment_pro_status из Edge: RPC требует auth.uid(), а клиент
    // с SUPABASE_SERVICE_ROLE_KEY даёт в БД auth.uid() = NULL → всегда ошибка.
    const { data: estSnapshot } = await supabase
      .from("establishments")
      .select("subscription_type, pro_paid_until, pro_trial_ends_at")
      .eq("id", establishmentId)
      .maybeSingle();

    console.log(
      JSON.stringify({
        fn: "billing-verify-apple",
        phase: "success",
        establishment_id: establishmentId,
        is_active: isActive,
      }),
    );

    return new Response(JSON.stringify({
      ok: true,
      is_active: isActive,
      pro_paid_until: paidUntilIso,
      apple_environment: appleResp.environment ?? null,
      establishment: estSnapshot ?? null,
      claim_enforced: Boolean(claimsEnforced && claimSkippedReason === null),
      claim_skipped_reason: claimSkippedReason,
    }), {
      status: 200,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error(
      JSON.stringify({
        fn: "billing-verify-apple",
        phase: "unhandled_exception",
        error: String(e),
      }),
    );
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
});
