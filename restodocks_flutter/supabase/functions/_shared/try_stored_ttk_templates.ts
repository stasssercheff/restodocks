/**
 * Попытка парсинга ТТК по каталогу сохранённых шаблонов (tt_parse_templates).
 * При повторной загрузке того же формата — без AI.
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { headerSignature, parseTtkByStoredTemplate } from "./parse_ttk_template.ts";
import type { TtkCard } from "./parse_ttk_template.ts";

// Сборник/ГОСТ/Word: "Наименование сырья", "Расход сырья на 1 порцию"
const KEYWORDS = ["наименование", "продукт", "брутто", "нетто", "название", "сырьё", "ингредиент", "расход сырья"];

export interface TryParseResult {
  cards: TtkCard[];
  headerSignature: string;
  sanityIssues?: string[];
}

export async function tryParseByStoredTemplates(rows: string[][]): Promise<TryParseResult | null> {
  if (rows.length < 2) return null;

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return null;

  const supabase = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });

  // Находим первый заголовок с шаблоном
  let firstSig: string | null = null;
  let data: Record<string, unknown> | null = null;
  for (let r = 0; r < rows.length && r < 100; r++) {
    const row = rows[r]?.map((c) => (c ?? "").trim().toLowerCase()) ?? [];
    if (row.length < 2) continue;
    const hasKeyword = row.some((c) => KEYWORDS.some((k) => c.includes(k)));
    if (!hasKeyword) continue;
    const headerRow = rows[r]?.map((c) => (c ?? "").trim()) ?? [];
    const sig = headerSignature(headerRow);
    if (!sig) continue;
    const res = await supabase.from("tt_parse_templates").select("header_row_index, name_col, product_col, gross_col, net_col, waste_col, output_col").eq("header_signature", sig).limit(1).maybeSingle();
    if (res.data) {
      firstSig = sig;
      data = res.data;
      break;
    }
  }
  if (!firstSig || !data) return null;

  // Собираем все строки с тем же заголовком (offset от каждого отдельно)
  const headerIndices: number[] = [];
  for (let r = 0; r < rows.length && r < 500; r++) {
    const headerRow = rows[r]?.map((c) => (c ?? "").trim()) ?? [];
    const sig = headerSignature(headerRow);
    if (sig === firstSig) headerIndices.push(r);
  }

  let dishNameRowOffset: number | null = null;
  let dishNameCol: number | null = null;
  let learnedProductCol: number | null = null;
  let learnedGrossCol: number | null = null;
  let learnedNetCol: number | null = null;
  const { data: learned } = await supabase
    .from("tt_parse_learned_dish_name")
    .select("dish_name_row_offset, dish_name_col, product_col, gross_col, net_col")
    .eq("header_signature", firstSig)
    .limit(1)
    .maybeSingle();
  if (learned?.dish_name_row_offset != null && learned?.dish_name_col != null) {
    dishNameRowOffset = learned.dish_name_row_offset as number;
    dishNameCol = learned.dish_name_col as number;
  }
  if (learned?.product_col != null) learnedProductCol = learned.product_col as number;
  if (learned?.gross_col != null) learnedGrossCol = learned.gross_col as number;
  if (learned?.net_col != null) learnedNetCol = learned.net_col as number;

  const templateHeaderIdx = (data.header_row_index as number) ?? 0;
  const allCards: TtkCard[] = [];
  const allSanityIssues: string[] = [];

  for (let i = 0; i < headerIndices.length; i++) {
    const headerIdx = headerIndices[i];
    const nextHeader = headerIndices[i + 1] ?? rows.length;
    const effectiveHeader = templateHeaderIdx > 0 && headerIdx === 0 ? templateHeaderIdx : headerIdx;
    const startRow = Math.max(0, effectiveHeader + (dishNameRowOffset ?? 0));
    const blockRows = rows.slice(startRow, nextHeader);
    const headerIdxInBlock = effectiveHeader - startRow;

    const result = parseTtkByStoredTemplate(blockRows, {
      headerIdx: headerIdxInBlock,
      nameCol: (data.name_col as number) ?? 0,
      productCol: learnedProductCol ?? (data.product_col as number) ?? 1,
      grossCol: learnedGrossCol ?? (data.gross_col as number) ?? -1,
      netCol: learnedNetCol ?? (data.net_col as number) ?? -1,
      wasteCol: (data.waste_col as number) ?? -1,
      outputCol: (data.output_col as number) ?? -1,
      dishNameRowOffset: dishNameRowOffset ?? undefined,
      dishNameCol: dishNameCol ?? undefined,
    });
    allCards.push(...result.cards);
    allSanityIssues.push(...result.sanityIssues);
  }

  const uniqueSanity = [...new Set(allSanityIssues)];
  if (allCards.length > 0) return { cards: allCards, headerSignature: firstSig, sanityIssues: uniqueSanity };
  return null;
}
