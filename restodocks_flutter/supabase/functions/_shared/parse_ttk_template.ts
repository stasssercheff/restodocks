/**
 * Парсинг ТТК по шаблону — без AI.
 * Ищет заголовки (Продукт, Брутто, Нетто...) и извлекает данные по найденным колонкам.
 */

const NAME_KEYS = ["наименование", "название", "блюдо", "пф", "name", "dish"];
const PRODUCT_KEYS = ["продукт", "сырьё", "сырья", "ингредиент", "product", "ingredient"];
// iiko DOCX: "Вес брутто, кг" приоритетнее "Брутто в ед. изм."
const GROSS_KEYS = ["вес брутто", "масса брутто", "брутто", "бр", "вес гр", "вес гр/шт", "расход сырья", "расход", "норма", "норма закладки", "масса", "gross"];
const NET_KEYS = ["вес нетто", "масса нетто", "нетто", "нт", "net"];
const WASTE_KEYS = ["отход", "отх", "waste", "процент отхода"];
// Сборник/ГОСТ: "Выход готовой продукции"
const OUTPUT_KEYS = ["выход", "вес готового", "вес готового продукта", "выход готовой продукции", "готовый", "output"];
const UNIT_KEYS = ["ед. изм", "ед изм", "единица", "unit"];

function parseNum(s: string): number | null {
  if (!s || !s.trim()) return null;
  const cleaned = s.replace(/,/g, ".").replace(/[^\d.\-]/g, "");
  const n = parseFloat(cleaned);
  return Number.isNaN(n) ? null : n;
}

export interface TtkIngredient {
  productName: string;
  grossGrams: number | null;
  netGrams: number | null;
  primaryWastePct: number | null;
  outputGrams?: number | null;
  unit: string | null;
  /** Цена за кг/л из КК (калькуляционная карта). Для создания продуктов в номенклатуру. */
  pricePerKg?: number | null;
  ingredientType?: "product" | "semi_finished" | null;
}

export interface TtkCard {
  dishName: string | null;
  technologyText: string | null;
  ingredients: TtkIngredient[];
  isSemiFinished: boolean | null;
  /** Выход (г) — из строки «итого» / «выход». Для блюд = вес порции. */
  yieldGrams?: number | null;
}

/**
 * Парсит rows по шаблону (поиск колонок по ключевым словам).
 */
export function parseTtkByTemplate(rows: string[][]): TtkCard[] {
  if (rows.length < 2) return [];

  let headerIdx = -1;
  let nameCol = -1;
  let productCol = -1;
  let grossCol = -1;
  let netCol = -1;
  let wasteCol = -1;
  let outputCol = -1;

  let unitCol = -1;
  let grossColIsKg = false;
  let netColIsKg = false;
  let outputColIsKg = false;

  for (let r = 0; r < rows.length && r < 25; r++) {
    const row = rows[r].map((c) => (c ?? "").trim().toLowerCase());
    for (let c = 0; c < row.length; c++) {
      const cell = row[c];
      if (!cell) continue;
      if (NAME_KEYS.some((k) => cell.includes(k))) {
        headerIdx = r;
        nameCol = c;
      }
      if (PRODUCT_KEYS.some((k) => cell.includes(k))) {
        headerIdx = r;
        productCol = c;
      }
      if (GROSS_KEYS.some((k) => cell.includes(k))) {
        headerIdx = r;
        const isBruttoInEdIzm = cell.includes("брутто") && (cell.includes("в ед") || cell.includes("ед.изм") || cell.includes("ед изм")) && !cell.includes("вес брутто") && !cell.includes("масса брутто");
        if (isBruttoInEdIzm) {
          if (grossCol < 0) grossCol = c;
        } else {
          if (grossCol < 0 || cell.includes("кг")) grossCol = c;
        }
      }
      if (NET_KEYS.some((k) => cell.includes(k))) {
        headerIdx = r;
        const isNettoInEdIzm = cell.includes("нетто") && (cell.includes("в ед") || cell.includes("ед.изм") || cell.includes("ед изм")) && !cell.includes("вес нетто") && !cell.includes("масса нетто");
        if (isNettoInEdIzm) {
          if (netCol < 0) netCol = c;
        } else {
          if (netCol < 0 || cell.includes("кг")) netCol = c;
        }
      }
      if (WASTE_KEYS.some((k) => cell.includes(k))) {
        headerIdx = r;
        wasteCol = c;
      }
      if (OUTPUT_KEYS.some((k) => cell.includes(k))) {
        headerIdx = r;
        outputCol = c;
      }
      if (UNIT_KEYS.some((k) => cell.includes(k))) {
        headerIdx = r;
        unitCol = c;
      }
    }
    if (headerIdx >= 0 && (nameCol >= 0 || productCol >= 0)) break;
  }

  if (headerIdx < 0 || (nameCol < 0 && productCol < 0)) {
    for (let r = 0; r < rows.length && r < 15; r++) {
      const row = rows[r] ?? [];
      const c0 = (row[0] ?? "").trim().toLowerCase();
      const c1 = (row[1] ?? "").trim();
      if ((c0 === "№" || c0 === "n" || /^\d+$/.test(c0)) && c1.length >= 2 && !/^[\d,.\s]+$/.test(c1)) {
        headerIdx = r;
        nameCol = 1;
        productCol = 1;
        if (row.length >= 4) { grossCol = 2; netCol = 3; }
        if (row.length >= 5) outputCol = 4;
        break;
      }
    }
  }
  if (headerIdx < 0 || (nameCol < 0 && productCol < 0)) return [];
  const headerRow = headerIdx < rows.length ? rows[headerIdx].map((c) => (c ?? "").trim().toLowerCase()) : [];
  if (grossCol >= 0 && headerRow[grossCol]?.includes("кг")) grossColIsKg = true;
  if (netCol >= 0 && headerRow[netCol]?.includes("кг")) netColIsKg = true;
  if (outputCol >= 0 && headerRow[outputCol]?.includes("кг")) outputColIsKg = true;

  if (nameCol < 0) nameCol = 0;
  if (productCol < 0) productCol = 1;

  // Единицы измерения и КБЖУ — не названия блюд (PDF даёт "г", "кДж)" и т.п.)
  const UNIT_PATTERNS = /^(г|кг|мл|л|шт|кдж\)?|ккал\)?)$/i;
  const isUnitOrNutrition = (s: string) =>
    s.length <= 6 && (UNIT_PATTERNS.test(s.replace(/\s/g, "")) || /^\d+\s*кдж\)?$/i.test(s) || /^\d+\s*ккал$/i.test(s));
  const isValidDishName = (s: string) =>
    s.length >= 4 && !isUnitOrNutrition(s) && /[а-яА-ЯёЁa-zA-Z]{2,}/.test(s);

  /** Слово-фрагмент из текста технологии ("коржей тортов", "изделий") — не название блюда */
  const isLikelyFragment = (s: string) => {
    const t = s.trim();
    if (t.includes(" ")) return false;
    if (t.length > 8) return false;
    return /(ов|ей|ий|овь)$/i.test(t) || /^(коржей|тортов|изделий|блюд|порций)/i.test(t);
  };

  const isSkipForDishName = (s: string) => {
    const low = s.trim().toLowerCase();
    return low.includes("органолептическ") || low.includes("внешний вид") || low.includes("консистенция") ||
      low.includes("запах") || low.includes("вкус") || low.includes("цвет") ||
      (low.includes("показатели") && low.includes("органолепт"));
  };
  const extractDishBeforeOrganoleptic = (cell: string): string | null => {
    const idx = cell.toLowerCase().indexOf("органолептическ");
    if (idx <= 0) return null;
    const before = cell.substring(0, idx).trim();
    if (before.length < 4) return null;
    const stop = /технологическая карта|название на чеке|область применения|хранение|срок хранения/i;
    const stopMatch = before.match(stop);
    const segment = stopMatch ? before.substring(0, stopMatch.index!).trim() : before;
    const words = segment.split(/\s+/).filter((w) => w.length > 1).slice(0, 6);
    if (words.length === 0) return null;
    const candidate = words.join(" ").trim();
    if (candidate.length >= 4 && isValidDishName(candidate) && !isSkipForDishName(candidate)) return candidate;
    return null;
  };

  // Название блюда часто в первых строках или в той же строке, что заголовок (iiko: Мясная к пенному | ... | Органолептические показатели:)
  let initialDish: string | null = null;
  const headerKeys = [...NAME_KEYS, ...PRODUCT_KEYS, ...GROSS_KEYS, ...NET_KEYS, ...WASTE_KEYS, ...OUTPUT_KEYS, ...UNIT_KEYS];
  const limitCol = headerIdx >= 0 && (nameCol > 0 || productCol > 0) ? Math.min(nameCol > 0 ? nameCol : productCol, 20) : 999;
  for (let r = 0; r <= headerIdx && r < rows.length; r++) {
    const row = rows[r] ?? [];
    const colLimit = r === headerIdx ? limitCol : row.length;
    for (let c = 0; c < row.length && c < colLimit; c++) {
      const cell = (row[c] ?? "").trim();
      if (cell.length < 3) continue;
      if (cell.endsWith(":")) continue;
      if (/^\d{1,2}\.\d{1,2}\.\d{2,4}/.test(cell)) continue;
      if (cell.toLowerCase().startsWith("технологическая карта")) continue;
      if (cell.toLowerCase().includes("название на чеке") || cell.toLowerCase().includes("название чека")) continue;
      if (isSkipForDishName(cell)) {
        const extracted = extractDishBeforeOrganoleptic(cell);
        if (extracted) { initialDish = extracted; break; }
        continue;
      }
      if (!isValidDishName(cell)) continue;
      if (cell.length < 15 && !/[a-zA-Zа-яА-ЯёЁ]{4,}/.test(cell)) continue;
      const lower = cell.toLowerCase();
      if (headerKeys.some((k) => lower.includes(k))) continue;
      if (!/[a-zA-Zа-яА-ЯёЁ]/.test(cell)) continue;
      if (/^[\d\s.,]+$/.test(cell)) continue;
      initialDish = cell;
      break;
    }
    if (initialDish) break;
  }

  const results: TtkCard[] = [];
  let currentDish: string | null = initialDish;
  const currentIngredients: TtkIngredient[] = [];
  let inTechnologySection = false;
  const technologyParts: string[] = [];

  const flushCard = (yieldGrams?: number | null) => {
    if (currentDish != null && (currentDish.length > 0 || currentIngredients.length > 0)) {
      const techText = technologyParts
        .filter((s) => s.length > 15 && !/^технологический процесс|допустимые сроки|условия и сроки/i.test(s.trim()))
        .join("\n")
        .trim() || null;
      results.push({
        dishName: currentDish || null,
        technologyText: techText || null,
        ingredients: [...currentIngredients],
        isSemiFinished: (currentDish ?? "").toLowerCase().includes("пф"),
        yieldGrams: yieldGrams ?? undefined,
      });
    }
    currentIngredients.length = 0;
    technologyParts.length = 0;
  };

  for (let r = headerIdx + 1; r < rows.length; r++) {
    const row = rows[r];
    if (!row || row.length === 0) continue;
    const cells = row.map((c) => (c ?? "").trim());
    let pCol = productCol;
    let gCol = grossCol;
    let nCol = netCol;
    if (cells.length >= 3 && cells.length <= 8) {
      const atProduct = productCol < cells.length ? cells[productCol] : "";
      if (atProduct && /^[\d,.\-\s]+$/.test(atProduct)) {
        pCol = 1;
        if (cells.length >= 4) {
          gCol = 2;
          nCol = 3;
        }
      }
    }
    const nameVal = nameCol < cells.length ? cells[nameCol] : "";
    const productVal = pCol < cells.length ? cells[pCol] : "";
    const grossVal = gCol >= 0 && gCol < cells.length ? cells[gCol] : "";
    const netVal = nCol >= 0 && nCol < cells.length ? cells[nCol] : "";
    const wasteVal = wasteCol >= 0 && wasteCol < cells.length ? cells[wasteCol] : "";
    const outputVal = outputCol >= 0 && outputCol < cells.length ? cells[outputCol] : "";

    if (nameVal.toLowerCase() === "итого" || productVal.toLowerCase() === "итого" || productVal.toLowerCase().startsWith("всего")) {
      let outG = parseNum(outputVal);
      if (outputColIsKg && outG != null && outG > 0 && outG < 100) outG = outG * 1000;
      flushCard(outG);
      currentDish = null;
      continue;
    }
    if (productVal.toLowerCase().includes("выход блюда") || productVal.toLowerCase().startsWith("выход одного")) continue;
    const pLow = productVal.toLowerCase();
    if (
      pLow.includes("требования к оформлению") || pLow.includes("требования к подаче") ||
      pLow.includes("вес готового блюда") || pLow.includes("вес готового изделия") ||
      pLow.includes("в расчете на") || pLow.includes("порц") ||
      pLow.includes("органолептическ") || pLow.includes("органолет") || /^итого\s*$/.test(pLow.trim()) ||
      pLow.includes("хранение") || pLow.startsWith("срок хранен") ||
      /^ед\.?\s*изм\.?\.?$/i.test(pLow.trim()) || /^ед\s*изм/i.test(pLow) ||
      pLow.includes("ресторан") || /^ресторан\s*[«""]/.test(pLow) || pLow === "блюдо" ||
      /^способ\s*(приготовления|оформления)?$/i.test(pLow.trim()) ||
      /^(взбить|добавить|положить|переложить|использовать|пробить|довести|соединить|перемешать|нарезать|запечь|варить|жарить|тушить|охладить|разогреть)$/i.test(pLow.trim())
    ) continue;

    const rowText = cells.join(" ").trim();
    const rowTextLow = rowText.toLowerCase();
    if (rowTextLow.includes("технологический процесс") || rowTextLow.includes("допустимые сроки") || rowTextLow.includes("использовать для")) {
      inTechnologySection = true;
    }
    if (productVal && (productVal.includes("технологический процесс") || productVal.includes("допустимые сроки") || productVal.includes("использовать для"))) {
      inTechnologySection = true;
    }
    if (inTechnologySection && rowText.length > 20 && !/^допустимые сроки\s/i.test(rowTextLow)) {
      technologyParts.push(rowText);
    }

    // Строка с названием блюда (начало новой карточки) — не из блока технологии и не фрагмент
    if (
      !inTechnologySection &&
      nameVal &&
      isValidDishName(nameVal) &&
      !isLikelyFragment(nameVal) &&
      !/^[\d\s.,]+$/.test(nameVal) &&
      !productVal
    ) {
      if (currentDish != null && currentIngredients.length > 0) flushCard(undefined);
      currentDish = nameVal;
    }

    // Строка с продуктом (ингредиент) — не из блока технологии (взбить, добавить и т.п.)
    if (productVal && !inTechnologySection) {
      if (currentDish == null && nameVal && isValidDishName(nameVal)) currentDish = nameVal;
      let gross = parseNum(grossVal);
      let net = parseNum(netVal);
      // iiko DOCX: gross==net==100 — часто "брутто в ед. изм", а строка с названием блюда ("Мясная к пенному") — не продукт
      const both100 = gross != null && net != null && gross > 99 && gross < 101 && Math.abs(gross - net) < 0.01;
      const looksLikeDishName = /^[а-яА-ЯёЁ\s]+\s+к\s+[а-яА-ЯёЁ\s]+$/.test(productVal.trim()) && productVal.trim().length < 30;
      if (both100 && looksLikeDishName) continue;
      let outputG = parseNum(outputVal);
      if (grossColIsKg && gross != null && gross > 0 && gross < 100) gross = gross * 1000;
      if (netColIsKg && net != null && net > 0 && net < 100) net = net * 1000;
      if (outputColIsKg && outputG != null && outputG > 0 && outputG < 100) outputG = outputG * 1000;
      let waste = parseNum(wasteVal);
      if (gross != null && gross > 0 && net != null && net > 0 && net < gross && (waste == null || waste === 0)) {
        waste = (1 - net / gross) * 100;
      }
      const unitCell = unitCol >= 0 && unitCol < cells.length ? (cells[unitCol] ?? "").trim().toLowerCase() : "";
      let unit = "g";
      if (unitCell.includes("л") || unitCell === "l") unit = "ml";
      else if (unitCell.includes("шт") || unitCell === "pcs") unit = "pcs";
      const cleanName = productVal.replace(/^Т\.\s*/i, "").replace(/^П\/Ф\s*/i, "").trim() || productVal;
      const isPf = /^П\/Ф\s/i.test(productVal);
      currentIngredients.push({
        productName: cleanName,
        grossGrams: gross,
        netGrams: net,
        primaryWastePct: waste,
        outputGrams: outputG,
        unit,
        ingredientType: isPf ? "semi_finished" : "product",
      } as TtkIngredient);
    }
  }
  flushCard(undefined);

  return results;
}

/** Нормализация ячейки: лишние пробелы, чтобы подпись совпадала с каталогом. */
function normalizeCellForSignature(s: string): string {
  return (s ?? "")
    .trim()
    .toLowerCase()
    .replace(/\s+/g, " ");
}

/** Подпись заголовка для сопоставления с каталогом шаблонов */
export function headerSignature(headerCells: string[]): string {
  const parts = headerCells.map((c) => normalizeCellForSignature(c)).filter(Boolean);
  return parts.join("|");
}

/** Результат парсинга по шаблону: карточки + предупреждения для дообучения */
export interface ParseTtkStoredResult {
  cards: TtkCard[];
  sanityIssues: string[];
}

/** Парсинг по сохранённому шаблону (индексы колонок заданы явно). */
export function parseTtkByStoredTemplate(
  rows: string[][],
  opts: {
    headerIdx: number;
    nameCol: number;
    productCol: number;
    grossCol?: number;
    netCol?: number;
    wasteCol?: number;
    outputCol?: number;
    /** Колонка «Технология приготовления» — собираем текст по строкам. */
    technologyCol?: number;
    /** Выученная позиция: смещение строки названия от header (0=header, -1=выше). */
    dishNameRowOffset?: number;
    /** Выученная позиция: колонка с названием. */
    dishNameCol?: number;
    /** Источник PDF: включать логику блокировки ингредиентов в блоке «Технологический процесс» и фильтрацию глаголов. */
    fromPdf?: boolean;
  },
): ParseTtkStoredResult {
  const { headerIdx, nameCol, productCol, grossCol = -1, netCol = -1, wasteCol = -1, outputCol = -1, technologyCol = -1, dishNameRowOffset, dishNameCol, fromPdf = false } = opts;
  const sanityIssuesSet = new Set<string>();
  if (rows.length <= headerIdx + 1) return { cards: [], sanityIssues: [] };

  const headerRow = rows[headerIdx]?.map((c) => (c ?? "").trim().toLowerCase()) ?? [];
  const grossColIsKg = grossCol >= 0 && grossCol < headerRow.length && headerRow[grossCol]?.includes("кг");
  const netColIsKg = netCol >= 0 && netCol < headerRow.length && headerRow[netCol]?.includes("кг");

  let currentDish: string | null = null;
  const currentIngredients: TtkIngredient[] = [];
  const results: TtkCard[] = [];
  let technologyParts: string[] = [];
  let inTechnologySection = false;

  const flushCard = (yieldGrams?: number | null) => {
    if (currentDish != null && (currentDish.length > 0 || currentIngredients.length > 0)) {
      const techText = technologyParts.filter((s) => s.length > 15 && !/требования к оформлению|требования к подаче/i.test(s)).join("\n").trim() || null;
      results.push({
        dishName: currentDish || null,
        technologyText: techText || null,
        ingredients: [...currentIngredients],
        isSemiFinished: (currentDish ?? "").toLowerCase().includes("пф"),
        yieldGrams: yieldGrams ?? undefined,
      });
    }
    currentIngredients.length = 0;
    technologyParts = [];
  };

  const unitPatterns = /^(г|кг|мл|л|шт|кдж|ккал|кдж\)|ккал\))$/i;
  const isValidDish = (s: string) =>
    s.length >= 4 && !unitPatterns.test(s.replace(/\s/g, "")) && !/^\d+\s*кдж\)?$/i.test(s) && /[а-яА-ЯёЁa-zA-Z]{2,}/.test(s);

  const isLikelyFragment = (s: string) => {
    const t = s.trim();
    if (t.includes(" ")) return false;
    if (t.length > 8) return false;
    return /(ов|ей|ий|овь)$/i.test(t) || /^(коржей|тортов|изделий|блюд|порций)/i.test(t);
  };

  /** Слова заголовка и мусор — не название блюда и не продукт */
  const HEADER_WORDS = ["брутто", "нетто", "наименование", "продукт", "сырьё", "расход", "норма", "выход", "ед.изм", "ед изм"];
  const TRASH_WORDS = ["из", "на", "жидкая", "пищевой"];
  const isHeaderWord = (s: string) => {
    const low = s.trim().toLowerCase();
    if (TRASH_WORDS.includes(low)) return true;
    return HEADER_WORDS.some((w) => low === w || low.startsWith(w + " ") || low.endsWith(" " + w));
  };

  const isSkip = (s: string) => {
    const low = s.trim().toLowerCase();
    return low.includes("органолептическ") || low.includes("внешний вид") || low.includes("консистенция") ||
      low.includes("запах") || low.includes("вкус") || low.includes("цвет");
  };

  const isJunkProductName = (s: string) => {
    const low = s.trim().toLowerCase();
    const base = low.includes("требования к оформлению") || low.includes("требования к подаче") ||
      low.includes("вес готового блюда") || low.includes("вес готового изделия") ||
      low.includes("в расчете на") || low.includes("порц") ||
      low.includes("органолептическ") || low.includes("органолет") || /^итого\s*$/.test(low.trim()) ||
      low.includes("хранение") || low.startsWith("срок хранен") ||
      /^ед\.?\s*изм\.?\.?$/i.test(low.trim()) || /^ед\s*изм/i.test(low) ||
      low.includes("ресторан") || /^ресторан\s*[«""]/.test(low) || low === "блюдо" ||
      /^способ\s*(приготовления|оформления)?$/i.test(low.trim());
    const cookingVerbs = /^(взбить|добавить|положить|переложить|использовать|пробить|довести|соединить|перемешать|нарезать|запечь|варить|жарить|тушить|охладить|разогреть)$/i.test(low.trim());
    return base || (fromPdf && cookingVerbs);
  };

  /** Wide Search: если ячейка пуста — проверить соседние 3 колонки в той же строке */
  const getCellOrNeighbor = (row: string[], col: number, isValid: (s: string) => boolean): { value: string; usedWideSearch: boolean } => {
    const primary = (row?.[col] ?? "").trim();
    if (primary.length >= 2 && isValid(primary)) return { value: primary, usedWideSearch: false };
    const neighbors = [col - 1, col - 2, col + 1, col + 2].filter((c) => c >= 0 && c < (row?.length ?? 0));
    for (const c of neighbors) {
      const v = (row?.[c] ?? "").trim();
      if (v.length >= 2 && isValid(v)) return { value: v, usedWideSearch: true };
    }
    return { value: "", usedWideSearch: false };
  };

  // Выученная позиция: берём название из заданной ячейки, при пустоте — Wide Search
  if (dishNameRowOffset != null && dishNameCol != null) {
    const nameRow = headerIdx + dishNameRowOffset;
    if (nameRow >= 0 && nameRow < rows.length) {
      const row = rows[nameRow];
      const primary = (row?.[dishNameCol] ?? "").trim();
      const valid = (s: string) =>
        s.length >= 2 && !isSkip(s) && isValidDish(s) && !isHeaderWord(s);
      if (primary.length >= 2 && valid(primary)) {
        currentDish = primary;
      } else {
        const { value, usedWideSearch } = getCellOrNeighbor(row ?? [], dishNameCol, (s) => s.length >= 2 && !isSkip(s) && isValidDish(s));
        if (value) {
          currentDish = value;
          if (usedWideSearch) sanityIssuesSet.add("Выученная колонка названия пуста, нашлось в соседней. Рекомендуем дообучение.");
        } else if (primary === "" && row) {
          const hasNearby = [dishNameCol - 1, dishNameCol + 1].some((c) => c >= 0 && c < row.length && (row[c] ?? "").trim().length > 0);
          if (hasNearby) sanityIssuesSet.add("Название в выученной ячейке пусто, рядом есть текст. Дообучение.");
        }
      }
    }
  }
  // Эвристика: ищем в строках выше header
  if (currentDish == null) {
    for (let r = 0; r < headerIdx && r < rows.length; r++) {
      for (const c of rows[r] ?? []) {
        const s = (c ?? "").trim();
        if (s.length < 3 || !isValidDish(s)) continue;
        if (s.endsWith(":")) continue;
        if (/^\d{1,2}\.\d{1,2}\.\d{2,4}/.test(s)) continue;
        if (s.toLowerCase().startsWith("технологическая карта")) continue;
        if (isSkip(s)) continue;
        currentDish = s;
        break;
      }
      if (currentDish != null) break;
    }
  }

  for (let r = headerIdx + 1; r < rows.length; r++) {
    const row = rows[r];
    if (!row || row.length === 0) continue;
    const cells = row.map((c) => (c ?? "").trim());
    let pCol = productCol;
    let gCol = grossCol;
    let nCol = netCol;
    if (cells.length >= 3 && cells.length <= 8) {
      const atProduct = productCol < cells.length ? cells[productCol] : "";
      if (atProduct && /^[\d,.\-\s]+$/.test(atProduct)) {
        pCol = 1;
        if (cells.length >= 4) {
          gCol = 2;
          nCol = 3;
        }
      }
    }
    const nameVal = nameCol < cells.length ? cells[nameCol] : "";
    let productVal = pCol < cells.length ? cells[pCol] : "";
    // Wide Search для продукта: если в выученной колонке пусто — соседние 3 ячейки
    const isValidProduct = (s: string) =>
      s.trim().length >= 3 && !/^[\d,.\-\s]+$/.test(s) && s.toLowerCase() !== "итого" && !isHeaderWord(s);
    if (!productVal || !isValidProduct(productVal)) {
      const neighborCols = [pCol - 1, pCol - 2, pCol + 1, pCol + 2].filter((c) => c >= 0 && c < cells.length);
      for (const c of neighborCols) {
        const v = cells[c] ?? "";
        if (isValidProduct(v)) {
          productVal = v;
          if (c !== pCol) sanityIssuesSet.add("Колонка продукта могла сместиться. Дообучение.");
          break;
        }
      }
    }
    let grossVal = gCol >= 0 && gCol < cells.length ? cells[gCol] : "";
    let netVal = nCol >= 0 && nCol < cells.length ? cells[nCol] : "";
    // DOCX/Word: merged cells → колонки смещены. Если в выученных колонках пусто — ищем число в строке
    if ((!grossVal.trim() || !netVal.trim()) && productVal && isValidProduct(productVal) && cells.length >= 3) {
      const numCells: { col: number; val: string; num: number }[] = [];
      for (let c = 2; c < Math.min(cells.length, 10); c++) {
        if (c === pCol) continue;
        const v = (cells[c] ?? "").trim();
        const n = parseNum(v);
        // Пропускаем № (1,2,3...) — берём только веса (0.01-5 кг или 10+ г)
        if (n != null && n > 0 && (n < 1 || n >= 10) && n < 1000) numCells.push({ col: c, val: v, num: n });
      }
      if (numCells.length >= 1 && !grossVal.trim()) grossVal = numCells[0].val;
      if (numCells.length >= 2 && !netVal.trim()) netVal = numCells[1].val;
      else if (numCells.length >= 1 && !netVal.trim()) netVal = numCells[0].val;
    }
    const wasteVal = wasteCol >= 0 && wasteCol < cells.length ? cells[wasteCol] : "";
    const outputVal = outputCol >= 0 && outputCol < cells.length ? cells[outputCol] : "";
    const techVal = technologyCol >= 0 && technologyCol < cells.length ? cells[technologyCol] : "";
    if (techVal.trim().length > 15) technologyParts.push(techVal.trim());

    // Sanity Check: вместо веса — текст
    let grossNum = parseNum(grossVal);
    let netNum = parseNum(netVal);
    const unitCell = (productCol === 1 && cells.length > 2) ? (cells[2] ?? "").trim().toLowerCase() : "";
    // кг/л → г/мл; шт не конвертируем. "0,150" (европ. формат) = кг
    const rowUnitIsKgOrL = unitCell.includes("кг") || unitCell === "kg" || unitCell.includes("л") || unitCell === "l";
    const grossRawLooksLikeKg = /^\s*0[,.]\d{1,3}\s*$/.test(grossVal.trim());
    const netRawLooksLikeKg = /^\s*0[,.]\d{1,3}\s*$/.test(netVal.trim());
    const shouldConvertKg = (v: number | null) => v != null && v > 0 && v < 100;
    if (grossColIsKg && shouldConvertKg(grossNum)) grossNum = grossNum! * 1000;
    else if (rowUnitIsKgOrL && shouldConvertKg(grossNum)) grossNum = grossNum! * 1000;
    else if (grossRawLooksLikeKg && shouldConvertKg(grossNum)) grossNum = grossNum! * 1000;
    if (netColIsKg && shouldConvertKg(netNum)) netNum = netNum! * 1000;
    else if (rowUnitIsKgOrL && shouldConvertKg(netNum)) netNum = netNum! * 1000;
    else if (netRawLooksLikeKg && shouldConvertKg(netNum)) netNum = netNum! * 1000;
    if (productVal && (grossVal.trim() || netVal.trim())) {
      const grossIsText = grossVal.trim().length > 0 && grossNum == null;
      const netIsText = netVal.trim().length > 0 && netNum == null;
      if (grossIsText || netIsText) {
        sanityIssuesSet.add("В колонках брутто/нетто — текст вместо числа. Проверьте формат, дообучение.");
      }
    }

    if (nameVal.toLowerCase() === "итого" || productVal.toLowerCase() === "итого") {
      let outG = parseNum(outputVal);
      const outputColIsKgStored = outputCol >= 0 && outputCol < headerRow.length && headerRow[outputCol]?.includes("кг");
      if (outputColIsKgStored && outG != null && outG > 0 && outG < 100) outG = outG * 1000;
      flushCard(outG);
      currentDish = null;
      continue;
    }
    const rowText = cells.join(" ").toLowerCase();
    if (fromPdf && (rowText.includes("технологический процесс") || rowText.includes("допустимые сроки") || rowText.includes("использовать для"))) {
      inTechnologySection = true;
    }
    if (fromPdf && productVal && (productVal.includes("технологический процесс") || productVal.includes("допустимые сроки") || productVal.includes("использовать для"))) {
      inTechnologySection = true;
    }
    if ((!fromPdf || !inTechnologySection) && nameVal && isValidDish(nameVal) && !isLikelyFragment(nameVal) && !/^[\d\s.,]+$/.test(nameVal) && !productVal) {
      if (currentDish != null && currentIngredients.length > 0) flushCard(undefined);
      currentDish = nameVal;
    }
    if (productVal && (!fromPdf || !inTechnologySection) && isValidProduct(productVal) && !isJunkProductName(productVal)) {
      if (currentDish == null && nameVal && isValidDish(nameVal) && !isHeaderWord(nameVal) && !isLikelyFragment(nameVal)) currentDish = nameVal;
      const norm = (s: string) => s.trim().toLowerCase().replace(/\s+/g, " ");
      if (currentDish != null && norm(productVal) === norm(currentDish)) continue;
      let waste = parseNum(wasteVal);
      const gross = grossNum;
      const net = netNum;
      const both100 = gross != null && net != null && gross > 99 && gross < 101 && Math.abs((gross - net)) < 0.01;
      const looksLikeDishName = /^[а-яА-ЯёЁ\s]+\s+к\s+[а-яА-ЯёЁ\s]+$/.test(productVal.trim()) && productVal.trim().length < 30;
      if (both100 && looksLikeDishName) continue;
      let outputG = parseNum(outputVal);
      const outputColIsKg = outputCol >= 0 && outputCol < headerRow.length && headerRow[outputCol]?.includes("кг");
      if (outputColIsKg && outputG != null && outputG > 0 && outputG < 100) outputG = outputG * 1000;
      currentIngredients.push({
        productName: productVal,
        grossGrams: grossNum,
        netGrams: netNum,
        primaryWastePct: waste,
        outputGrams: outputG,
        unit: "g",
      });
    }
  }
  flushCard(undefined);
  return { cards: results, sanityIssues: [...sanityIssuesSet] };
}

/**
 * Конвертирует текст из PDF в rows (массив строк с ячейками).
 * Пробует: табуляция, 2+ пробела, разбор по числам в конце строки.
 */
export function pdfTextToRows(text: string): string[][] {
  const lines = text
    .split(/\r\n|\r|\n/)
    .map((l) => l.trim())
    .filter(Boolean);
  if (lines.length < 2) return [];

  const tabCount = lines.filter((l) => l.split(/\t/).length >= 3).length;
  const spaceCount = lines.filter((l) => l.split(/\s{2,}/).length >= 3).length;
  const useTab = tabCount >= Math.min(2, lines.length);
  const useSpaces = !useTab && spaceCount >= Math.min(2, lines.length);

  const rows: string[][] = [];
  for (const line of lines) {
    let cells: string[];
    if (useTab) {
      cells = line.split(/\t/).map((c) => c.trim()).filter(Boolean);
    } else if (useSpaces) {
      cells = line.split(/\s{2,}/).map((c) => c.trim()).filter(Boolean);
    } else {
      // Эвристика: строка "N продукт ... число число число" — числа в конце
      const trailingMatch = line.match(/([\d,.\-]+\s*)+$/);
      if (trailingMatch) {
        const numsPart = trailingMatch[0].trim();
        const nums = numsPart.split(/\s+/);
        const rest = line.slice(0, line.length - numsPart.length).trim();
        const numStart = rest.match(/^(\d+)\s+(.+)$/);
        cells = numStart
          ? [numStart[1], numStart[2], ...nums]
          : [rest, ...nums];
      } else {
        cells = line.split(/\s+/).filter(Boolean);
      }
    }
    if (cells.length > 0) rows.push(cells);
  }

  return rows;
}
