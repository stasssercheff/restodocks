/**
 * Лимит парсинга ТТК через ИИ: 3 документа в день на заведение.
 * Шаблонный парсинг не учитывается.
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const LIMIT_PER_DAY = 3;

export async function checkAndIncrementAiTtkUsage(
  establishmentId: string,
): Promise<{ allowed: boolean; countToday: number }> {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    return { allowed: true, countToday: 0 };
  }
  const supabase = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
  const today = new Date().toISOString().slice(0, 10);

  const { data: row } = await supabase
    .from("ai_ttk_daily_usage")
    .select("ai_parse_count")
    .eq("establishment_id", establishmentId)
    .eq("usage_date", today)
    .maybeSingle();

  const currentCount = row?.ai_parse_count ?? 0;
  if (currentCount >= LIMIT_PER_DAY) {
    return { allowed: false, countToday: currentCount };
  }

  const { error } = await supabase.from("ai_ttk_daily_usage").upsert(
    {
      establishment_id: establishmentId,
      usage_date: today,
      ai_parse_count: currentCount + 1,
    },
    { onConflict: "establishment_id,usage_date" },
  );
  if (error) {
    console.error("[ai_ttk_limit] upsert error:", error);
    return { allowed: true, countToday: 0 };
  }
  return { allowed: true, countToday: currentCount + 1 };
}
