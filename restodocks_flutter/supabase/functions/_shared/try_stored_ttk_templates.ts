/**
 * Попытка парсинга ТТК по каталогу сохранённых шаблонов (tt_parse_templates).
 * При повторной загрузке того же формата — без AI.
 * Каталог постоянно растёт: клиент при первом парсинге нового формата (keyword/AI) сохраняет шаблон
 * через tt-parse-save-learning; при правках на экране проверки — learned_dish_name и corrections.
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

export async function tryParseByStoredTemplates(rows: string[][], options?: { fromPdf?: boolean }): Promise<TryParseResult | null> {
  const fromPdf = options?.fromPdf === true;
  if (rows.length < 2) return null;

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return null;

  const supabase = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });

  // Находим первый заголовок с шаблоном (точное совпадение или prefix)
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
    let res = await supabase.from("tt_parse_templates").select("header_signature, header_row_index, name_col, product_col, gross_col, net_col, waste_col, output_col, technology_col").eq("header_signature", sig).limit(1).maybeSingle();
    if (!res.data) {
      const all = await supabase.from("tt_parse_templates").select("header_signature, header_row_index, name_col, product_col, gross_col, net_col, waste_col, output_col, technology_col");
      const templates = (all.data ?? []) as Array<Record<string, unknown>>;
      const sigPrefix6 = sig.split("|").slice(0, 6).join("|");
      const match = templates.find((t) => {
        const ts = (t.header_signature as string) ?? "";
        if (sig === ts || sig.startsWith(ts + "|") || ts.startsWith(sig + "|")) return true;
        const tsPrefix6 = ts.split("|").slice(0, 6).join("|");
        return sigPrefix6 && tsPrefix6 && (sigPrefix6 === tsPrefix6 || sig.startsWith(tsPrefix6 + "|"));
      });
      if (match) {
        res = { data: match };
      }
    }
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
  let learnedTechnologyCol: number | null = null;
  const learnedSig = (data?.header_signature as string) ?? firstSig;
  const { data: learned } = await supabase
    .from("tt_parse_learned_dish_name")
    .select("dish_name_row_offset, dish_name_col, product_col, gross_col, net_col, technology_col")
    .eq("header_signature", learnedSig)
    .limit(1)
    .maybeSingle();
  if (learned?.dish_name_row_offset != null && learned?.dish_name_col != null) {
    dishNameRowOffset = learned.dish_name_row_offset as number;
    dishNameCol = learned.dish_name_col as number;
  }
  if (learned?.product_col != null) learnedProductCol = learned.product_col as number;
  if (learned?.gross_col != null) learnedGrossCol = learned.gross_col as number;
  if (learned?.net_col != null) learnedNetCol = learned.net_col as number;
  if (learned?.technology_col != null) learnedTechnologyCol = learned.technology_col as number;

  const templateHeaderIdx = (data.header_row_index as number) ?? 0;
  const templateGrossCol = (data.gross_col as number) ?? -1;
  const templateNetCol = (data.net_col as number) ?? -1;
  // ГОСТ 2-row: колонки из следующей строки («Брутто»/«Нетто»). Нужно когда: -1/-1 или оба равны (ошибочно одна колонка).
  let inferredGrossCol = -1;
  let inferredNetCol = -1;
  if (headerIndices.length > 0) {
    const nextRowIdx = headerIndices[0] + 1;
    const nextRow = (rows[nextRowIdx] ?? []).map((c) => (c ?? "").trim().toLowerCase());
    for (let c = 0; c < nextRow.length; c++) {
      const cell = nextRow[c];
      if (cell.includes("брутто") && inferredGrossCol < 0) inferredGrossCol = c;
      if (cell.includes("нетто") && inferredNetCol < 0) inferredNetCol = c;
    }
  }
  const needInferred = templateGrossCol < 0 || templateNetCol < 0 || templateGrossCol === templateNetCol;
  const useInferred = needInferred && inferredGrossCol >= 0 && inferredNetCol >= 0 && inferredGrossCol !== inferredNetCol;
  const effectiveGrossCol = useInferred ? inferredGrossCol : (templateGrossCol >= 0 ? templateGrossCol : inferredGrossCol);
  const effectiveNetCol = useInferred ? inferredNetCol : (templateNetCol >= 0 ? templateNetCol : inferredNetCol);

  const headerWords = ["брутто", "нетто", "наименование", "продукт", "сырьё"];
  const isGarbageCard = (c: { dishName: string | null; ingredients: { productName: string }[] }) => {
    const dn = (c.dishName ?? "").trim().toLowerCase();
    if (headerWords.some((w) => dn === w || dn.startsWith(w))) return true;
    const garbage = c.ingredients.filter((i) => {
      const p = (i.productName ?? "").trim().toLowerCase();
      return headerWords.some((w) => p === w) || /^[\d,.\s]+$/.test(p) || p.length <= 2;
    }).length;
    return c.ingredients.length > 0 && garbage / c.ingredients.length >= 0.5;
  };

  const templateProductCol = (data.product_col as number) ?? 1;
  const nameCol = (data.name_col as number) ?? 0;
  const parseBlock = (useLearned: boolean) => {
    const cards: TtkCard[] = [];
    const issues: string[] = [];
    const pColFromTemplate = useLearned ? (learnedProductCol ?? templateProductCol) : templateProductCol;
    // ГОСТ 2-row: продукт в колонке наименования (0), иначе колонка 1 = брутто и мы пропускаем первый вес.
    const pCol = inferredGrossCol >= 0 && (templateProductCol === inferredGrossCol || (useLearned && learnedProductCol === inferredGrossCol))
      ? nameCol
      : pColFromTemplate;
    for (let i = 0; i < headerIndices.length; i++) {
      const headerIdx = headerIndices[i];
      const nextHeader = headerIndices[i + 1] ?? rows.length;
      const effectiveHeader = templateHeaderIdx > 0 && headerIdx === 0 ? templateHeaderIdx : headerIdx;
      const dOffset = useLearned ? (dishNameRowOffset ?? 0) : 0;
      const startRow = i === 0 ? 0 : Math.max(0, effectiveHeader + dOffset);
      const blockRows = rows.slice(startRow, nextHeader);
      const headerIdxInBlock = effectiveHeader - startRow;
      let gCol = useLearned ? (learnedGrossCol ?? effectiveGrossCol) : effectiveGrossCol;
      let nCol = useLearned ? (learnedNetCol ?? effectiveNetCol) : effectiveNetCol;
      // Если выученные/шаблонные колонки совпадают (нетто=брутто), а по следующей строке есть две разные — используем их.
      if (gCol >= 0 && nCol >= 0 && gCol === nCol && effectiveGrossCol >= 0 && effectiveNetCol >= 0 && effectiveGrossCol !== effectiveNetCol) {
        gCol = effectiveGrossCol;
        nCol = effectiveNetCol;
      }
      const res = parseTtkByStoredTemplate(blockRows, {
        headerIdx: headerIdxInBlock,
        nameCol,
        productCol: pCol,
        grossCol: gCol,
        netCol: nCol,
        wasteCol: (data.waste_col as number) ?? -1,
        outputCol: (data.output_col as number) ?? -1,
        technologyCol: useLearned ? (learnedTechnologyCol ?? (data.technology_col as number) ?? -1) : (data.technology_col as number) ?? -1,
        dishNameRowOffset: useLearned ? dishNameRowOffset ?? undefined : undefined,
        dishNameCol: useLearned ? dishNameCol ?? undefined : undefined,
        fromPdf,
      });
      cards.push(...res.cards);
      issues.push(...res.sanityIssues);
    }
    return { cards, issues };
  };

  let { cards: allCards, issues: allSanityIssues } = parseBlock(true);
  if (allCards.some(isGarbageCard) && (dishNameRowOffset != null || learnedProductCol != null)) {
    const fallback = parseBlock(false);
    if (fallback.cards.length > 0 && !fallback.cards.every(isGarbageCard)) {
      allCards = fallback.cards;
      allSanityIssues = fallback.issues;
    }
  }

  const uniqueSanity = [...new Set(allSanityIssues)];
  if (allCards.length > 0) return { cards: allCards, headerSignature: firstSig, sanityIssues: uniqueSanity };
  return null;
}
