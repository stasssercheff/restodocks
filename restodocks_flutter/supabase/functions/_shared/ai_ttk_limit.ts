import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const PRO_MONTH_LIMIT = 15;
const ULTRA_MONTH_LIMIT = 35;
const TRIAL_TOTAL_LIMIT = 3;
const PAID_TIERS = new Set(["pro", "plus", "starter", "business", "ultra", "premium"]);
const ULTRA_TIERS = new Set(["ultra", "premium"]);

type AiTtkUsageStatus = {
  allowed: boolean;
  count: number;
  limit: number;
  reason?: string;
  periodType?: string;
  periodKey?: string;
};

async function resolveAiTtkUsageStatus(
  supabase: ReturnType<typeof createClient>,
  establishmentId: string,
  department: string,
): Promise<AiTtkUsageStatus> {
  const { data: est, error: estError } = await supabase
    .from("establishments")
    .select("subscription_type, pro_trial_ends_at, pro_paid_until")
    .eq("id", establishmentId)
    .maybeSingle();
  if (estError || !est) {
    return { allowed: true, count: 0, limit: ULTRA_MONTH_LIMIT };
  }

  const now = new Date();
  const subscriptionType = String(est.subscription_type ?? "free").toLowerCase().trim();
  const paidUntil = est.pro_paid_until ? new Date(String(est.pro_paid_until)) : null;
  const trialEndsAt = est.pro_trial_ends_at ? new Date(String(est.pro_trial_ends_at)) : null;
  const isPaidTier = PAID_TIERS.has(subscriptionType);
  const isPaidActive = isPaidTier && (!paidUntil || paidUntil > now);
  const isTrialActive = trialEndsAt ? trialEndsAt > now : false;

  let periodType = "";
  let periodKey = "";
  let limit = 0;
  let denyReason = "";

  const scope = department.trim().toLowerCase().includes("bar") ? "bar" : "kitchen";

  if (isPaidActive) {
    const monthKey = `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, "0")}`;
    periodType = "month";
    periodKey = `${scope}:${monthKey}`;
    if (ULTRA_TIERS.has(subscriptionType)) {
      limit = ULTRA_MONTH_LIMIT;
      denyReason = "ai_ttk_limit_ultra_month";
    } else {
      limit = PRO_MONTH_LIMIT;
      denyReason = "ai_ttk_limit_pro_month";
    }
  } else if (isTrialActive) {
    periodType = "trial_total";
    periodKey = `${scope}:trial_total`;
    limit = TRIAL_TOTAL_LIMIT;
    denyReason = "ai_ttk_limit_trial_total";
  } else {
    return {
      allowed: false,
      count: 0,
      limit: 0,
      reason: "ai_ttk_no_access_lite",
    };
  }

  const { data: row } = await supabase
    .from("ai_ttk_usage_counters")
    .select("ai_parse_count")
    .eq("establishment_id", establishmentId)
    .eq("period_type", periodType)
    .eq("period_key", periodKey)
    .maybeSingle();

  const currentCount = row?.ai_parse_count ?? 0;
  const allowed = currentCount < limit;
  return {
    allowed,
    count: currentCount,
    limit,
    reason: allowed ? undefined : denyReason,
    periodType,
    periodKey,
  };
}

export async function getAiTtkUsageStatus(
  establishmentId: string,
  department = "kitchen",
): Promise<AiTtkUsageStatus> {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    return { allowed: true, count: 0, limit: ULTRA_MONTH_LIMIT };
  }
  const supabase = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
  return resolveAiTtkUsageStatus(supabase, establishmentId, department);
}

export async function checkAndIncrementAiTtkUsage(
  establishmentId: string,
  department = "kitchen",
): Promise<{ allowed: boolean; count: number; limit: number; reason?: string }> {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    return { allowed: true, count: 0, limit: ULTRA_MONTH_LIMIT };
  }
  const supabase = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
  const status = await resolveAiTtkUsageStatus(supabase, establishmentId, department);
  if (!status.allowed) {
    return { allowed: false, count: status.count, limit: status.limit, reason: status.reason };
  }

  const now = new Date();
  const { error } = await supabase.from("ai_ttk_usage_counters").upsert(
    {
      establishment_id: establishmentId,
      period_type: status.periodType,
      period_key: status.periodKey,
      ai_parse_count: status.count + 1,
      updated_at: now.toISOString(),
    },
    { onConflict: "establishment_id,period_type,period_key" },
  );
  if (error) {
    console.error("[ai_ttk_limit] upsert error:", error);
    return { allowed: true, count: status.count, limit: status.limit };
  }
  return { allowed: true, count: status.count + 1, limit: status.limit };
}
