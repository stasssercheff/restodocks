/**
 * Попытка парсинга ТТК по каталогу сохранённых шаблонов (tt_parse_templates).
 * При повторной загрузке того же формата — без AI.
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { headerSignature, parseTtkByStoredTemplate } from "./parse_ttk_template.ts";
import type { TtkCard } from "./parse_ttk_template.ts";

// Сборник/ГОСТ/Word: "Наименование сырья", "Расход сырья на 1 порцию"
const KEYWORDS = ["наименование", "продукт", "брутто", "нетто", "название", "сырьё", "ингредиент", "расход сырья"];

export async function tryParseByStoredTemplates(rows: string[][]): Promise<TtkCard[] | null> {
  if (rows.length < 2) return null;

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return null;

  const supabase = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });

  for (let r = 0; r < rows.length && r < 50; r++) {
    const row = rows[r]?.map((c) => (c ?? "").trim().toLowerCase()) ?? [];
    if (row.length < 2) continue; // ГОСТ 2-row: "Наименование сырья" | "Расход" — 2 колонки
    const hasKeyword = row.some((c) => KEYWORDS.some((k) => c.includes(k)));
    if (!hasKeyword) continue;

    const headerRow = rows[r]?.map((c) => (c ?? "").trim()) ?? [];
    const sig = headerSignature(headerRow);
    if (!sig) continue;

    const { data } = await supabase
      .from("tt_parse_templates")
      .select("header_row_index, name_col, product_col, gross_col, net_col, waste_col, output_col")
      .eq("header_signature", sig)
      .limit(1)
      .maybeSingle();

    if (!data) continue;

    // r = строка, где нашли заголовок в этом файле. Для 2-row header (ГОСТ): row 0 = Наименование|Расход,
    // row 1 = Брутто|Нетто — матчим row 0, но данные с row 2. templateHeaderIdx говорит сколько строк заголовка.
    const templateHeaderIdx = (data.header_row_index as number) ?? 0;
    const headerIdx = templateHeaderIdx > 0 && r === 0 ? templateHeaderIdx : r;

    const list = parseTtkByStoredTemplate(rows, {
      headerIdx,
      nameCol: (data.name_col as number) ?? 0,
      productCol: (data.product_col as number) ?? 1,
      grossCol: (data.gross_col as number) ?? -1,
      netCol: (data.net_col as number) ?? -1,
      wasteCol: (data.waste_col as number) ?? -1,
      outputCol: (data.output_col as number) ?? -1,
    });

    if (list.length > 0) return list;
  }
  return null;
}
