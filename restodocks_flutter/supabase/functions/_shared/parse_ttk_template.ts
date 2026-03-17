/**
 * Парсинг ТТК по шаблону — без AI.
 * Ищет заголовки (Продукт, Брутто, Нетто...) и извлекает данные по найденным колонкам.
 *
 * Принцип: карточки формируются по формату и структуре таблицы. Подпись заголовка (headerSignature)
 * строится только из структурных ячеек (колонки), поэтому один и тот же формат в разных файлах
 * даёт одну подпись — обучение применяется ко всем таким файлам. При разборе строк принимаются
 * только строки, соответствующие структуре: в колонках весов — числа, в колонке продукта — название,
 * хотя бы один вес задан; иначе строка считается футером/метаданными и пропускается.
 *
 * Логика (не под каждый файл):
 * 1. Границы секций: строка с маркером (Техн. карта №, Выход на 1 порцию, Масса полуфабриката,
 *    Информация о пищевой, Технологический процесс, Допустимые сроки) = конец таблицы ингредиентов.
 * 2. Строка продукта валидна только ДО первой границы.
 * 3. Структурные слова (заголовки колонок, названия секций) ≠ ингредиенты — по семантике, не по списку.
 * 4. По структуре: в ячейках брутто/нетто — только числа; если там текст (фраза) — строка не ингредиент.
 * 5. Строка ингредиента должна иметь хотя бы один вес (брутто или нетто) > 0.
 * 6. Числа: gross/net > 100000 г = мусор (КБЖУ, склейки).
 */

/** Строка с маркером новой секции — конец таблицы ингредиентов (Shama, ГОСТ и др.) */
const SECTION_BOUNDARY_REGEX = /технологическая\s+карта\s+№|выход\s+на\s+1\s+порцию|масса\s+полуфабриката|информация\s+о\s+пищевой|технологический\s+процесс|допустимые\s+сроки/i;

/** Заголовки колонок и названия секций — не продукты. Точное совпадение или начало фразы. */
const STRUCTURAL_WORDS = new Set([
  "брутто", "нетто", "расход", "норма", "выход", "наименование", "продукт", "сырьё", "сырья",
  "ед.изм", "ед изм", "единица", "итого", "масса", "блюдо", "ресторан",
  "порцию", "порций", "хранение", "белки", "жиры", "углеводы", "калорийность",
  "полуфабрикатов", "жирности", "готовой",
]);
/** Фразы секций/метаданных в ячейке продукта — не ингредиенты. Совпадает с фильтрами в Dart. */
const STRUCTURAL_PHRASES = [
  /требования\s+к\s+оформлению/i, /требования\s+к\s+подаче/i, /вес\s+готового\s+(блюда|изделия)/i,
  /в\s+расч[её]те\s+на/i, /информация\s+о\s+пищ/i, /^итого\s*$/i, /срок\s+хранен/i,
  /^ед\.?\s*изм/i, /способ\s*(приготовления|оформления)?$/i, /ресторан\s*[«""]/i,
  /органолептическ/i,
  /^хранение\s*:/i, /^область\s+применения/i, /название\s+на\s+чеке/i,
  /\d[\d\s,.]*\s*порц/i, /^порц\s*$/i,
];
/** Глаголы технологии (императив) — не продукты. */
const COOKING_VERBS = /^(взбить|добавить|положить|переложить|использовать|пробить|довести|соединить|перемешать|нарезать|запечь|варить|жарить|тушить|охладить|разогреть)$/i;

export function isStructuralProductName(s: string, fromPdf: boolean): boolean {
  const low = (s ?? "").trim().toLowerCase();
  if (low.length <= 2 || /^[\d,.\s\-]+$/.test(low)) return true;
  if (low.includes("порц")) return true; // "1,000 порц", "вес в расчете на N порц"
  if (low === "хранение:" || low.startsWith("хранение:") || low.includes("область применения") || low.includes("название на чеке")) return true;
  const word = low.replace(/\s+/g, " ");
  if (STRUCTURAL_WORDS.has(word)) return true;
  for (const re of STRUCTURAL_PHRASES) {
    if (re.test(word)) return true;
  }
  if (fromPdf && COOKING_VERBS.test(word)) return true;
  if (fromPdf && word.length <= 10 && /кдж|ккал/i.test(word) && !/[а-яё]{4,}/i.test(word)) return true;
  return false;
}

/** Индекс первой строки с границей секции (конец таблицы). Экспорт для обогащения технологии из выученной колонки. */
export function findTableEndRow(rows: string[][], fromRow: number): number {
  for (let r = fromRow; r < rows.length && r < fromRow + 200; r++) {
    const row = rows[r] ?? [];
    const text = row.map((c) => (c ?? "").trim()).join(" ").toLowerCase();
    if (SECTION_BOUNDARY_REGEX.test(text)) return r;
  }
  return rows.length;
}

/** Извлечь текст технологии из [rows], начиная с границы таблицы, беря ячейки из колонки [technologyCol]. Для подстановки из обучения. */
export function getTechnologyFromRowsUsingColumn(rows: string[][], technologyCol: number, fromRow: number): string {
  if (technologyCol < 0 || rows.length <= fromRow) return "";
  const tableEndRow = findTableEndRow(rows, fromRow);
  const parts: string[] = [];
  for (let r = tableEndRow; r < rows.length; r++) {
    const row = rows[r] ?? [];
    const cell = (row[technologyCol] ?? "").trim();
    if (cell.length > 15 && !/^допустимые сроки\s|^информация о пищевой/i.test(cell)) parts.push(cell);
  }
  return parts.join("\n").trim();
}

const NAME_KEYS = ["наименование", "название", "блюдо", "пф", "name", "dish"];
const PRODUCT_KEYS = ["продукт", "сырьё", "сырья", "ингредиент", "product", "ingredient"];
// iiko DOCX: "Вес брутто, кг" приоритетнее "Брутто в ед. изм."
const GROSS_KEYS = ["вес брутто", "масса брутто", "брутто", "бр", "вес гр", "вес гр/шт", "расход сырья", "расход", "норма", "норма закладки", "масса", "gross"];
const NET_KEYS = ["вес нетто", "масса нетто", "нетто", "нт", "net"];
const WASTE_KEYS = ["отход", "отх", "waste", "процент отхода", "% отхода", "отх.", "отх %", "отход%"];
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
    // Shama: «Наименование» в строке 0, «Брутто/Нетто/Выход» — в строке 1. Не выходить, пока не найдём колонки весов или не просмотрели 3 строки.
    const hasWeights = grossCol >= 0 || netCol >= 0 || outputCol >= 0;
    if (headerIdx >= 0 && (nameCol >= 0 || productCol >= 0) && (hasWeights || r >= 2)) break;
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
  // Shama: двухстрочный заголовок — колонки весов могут не найтись. Fallback: № | Продукт | Брутто | Нетто | Выход
  if (grossCol < 0 && netCol < 0) {
    grossCol = 2;
    netCol = 3;
    if (outputCol < 0) outputCol = 4;
  }

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
      if (cell.trim().toLowerCase() === "выход") continue;
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
  const technologyParts: string[] = [];
  const tableEndRow = findTableEndRow(rows, headerIdx + 1);

  const flushCard = (yieldGrams?: number | null) => {
    if (currentDish != null && (currentDish.length > 0 || currentIngredients.length > 0)) {
      const techText = technologyParts
        .filter((s) => s.length > 15 && !/^технологический процесс|допустимые сроки|условия и сроки|информация о пищевой/i.test(s.trim()))
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
    let productVal = pCol < cells.length ? cells[pCol] : "";
    let weightStartCol = -1;
    if (productVal && cells.length > pCol + 4) {
      const parts: string[] = [productVal];
      for (let c = pCol + 1; c < cells.length - 2; c++) {
        const a = parseNum(cells[c] ?? "");
        const b = parseNum(cells[c + 1] ?? "");
        if (a != null && b != null && a > 0 && a <= 10000 && b > 0 && b <= 10000) {
          weightStartCol = c;
          if (parts.length > 1) productVal = parts.join(" ");
          break;
        }
        const v = cells[c] ?? "";
        if (v.length >= 2 && !/^[\d,.\-\s]+$/.test(v)) parts.push(v);
      }
    }
    const gColEff = weightStartCol >= 0 ? weightStartCol : (gCol >= 0 ? gCol : -1);
    const nColEff = weightStartCol >= 0 ? weightStartCol + 1 : nCol;
    const oColEff = weightStartCol >= 0 ? weightStartCol + 2 : outputCol;
    const grossVal = gColEff >= 0 && gColEff < cells.length ? cells[gColEff] : "";
    const netVal = nColEff >= 0 && nColEff < cells.length ? cells[nColEff] : "";
    const wasteVal = wasteCol >= 0 && wasteCol < cells.length ? cells[wasteCol] : "";
    const outputVal = (oColEff >= 0 && oColEff < cells.length ? cells[oColEff] : "") || (outputCol >= 0 && outputCol < cells.length ? cells[outputCol] : "");

    const rowText = cells.join(" ").trim();
    const rowTextLow = rowText.toLowerCase();
    const isPastTable = r >= tableEndRow;
    if (isPastTable && rowText.length > 20 && !/^допустимые сроки\s/i.test(rowTextLow)) {
      technologyParts.push(rowText);
    }
    // Строки технологии иногда в PDF идут до «Выход на 1 порцию» — не терять начало инструкции (Shama.Book: «сахар пробить...», «добавить сыр, ванильный экстракт...»)
    const justBeforeBoundary = r >= tableEndRow - 5 && r < tableEndRow;
    if (!isPastTable && justBeforeBoundary && rowText.length > 25 && !/^допустимые сроки\s|^информация о пищевой|^технологический процесс\s/i.test(rowTextLow)) {
      const gw = parseNum(grossVal);
      const nw = parseNum(netVal);
      const hasWeight = (gw != null && gw > 0) || (nw != null && nw > 0);
      const startsWithVerb =
        /^(соединить|добавить|взбить|перемешать|положить|нарезать|варить|жарить|тушить|охладить|разогреть|довести|пробить|использовать|переложить|ввести|смешать)/i.test(
          rowText.trim(),
        );
      const startsWithNounThenVerb = /^[а-яё\s]{2,35}(пробить|положить|добавить|взбить|переложить|соединить|перемешать)/i.test(rowText.trim());
      if (!hasWeight && (startsWithVerb || startsWithNounThenVerb)) technologyParts.push(rowText);
    }

    if (nameVal.toLowerCase() === "итого" || productVal.toLowerCase() === "итого" || productVal.toLowerCase().startsWith("всего")) {
      // В PDF инструкция может быть на одной строке с «Итого» — сохранить хвост как технологию
      const afterNums = rowText.replace(/^.*?\bитого\s*[\d,.\s]*/i, "").trim();
      if (afterNums.length > 30 && /[а-яё]/i.test(afterNums)) technologyParts.push(afterNums);
      let outG = parseNum(outputVal);
      if (outputColIsKg && outG != null && outG > 0 && outG < 100) outG = outG * 1000;
      flushCard(outG);
      currentDish = null;
      continue;
    }
    // Строка «Выход» + число — конец карточки (формат супы.xlsx и др.)
    if (nameVal.trim().toLowerCase() === "выход" || productVal.trim().toLowerCase() === "выход") {
      let outG = parseNum(grossVal) || parseNum(netVal) || parseNum(outputVal);
      if (outG == null && cells.length > 1) outG = parseNum(cells[1]);
      if (outputColIsKg && outG != null && outG > 0 && outG < 100) outG = outG * 1000;
      flushCard(outG ?? undefined);
      currentDish = null;
      continue;
    }
    if (isPastTable) continue;
    if (isStructuralProductName(productVal, true)) continue;
    if (productVal.toLowerCase().includes("выход блюда") || productVal.toLowerCase().startsWith("выход одного")) continue;

    // Строка с названием блюда (начало новой карточки). «Выход» — не название. Строка с весом (число в брутто/нетто) — ингредиент.
    const grossNumPrev = parseNum(grossVal);
    const netNumPrev = parseNum(netVal);
    const rowHasWeight = (grossNumPrev != null && grossNumPrev > 0) || (netNumPrev != null && netNumPrev > 0);
    if (
      nameVal &&
      nameVal.trim().toLowerCase() !== "выход" &&
      !rowHasWeight &&
      isValidDishName(nameVal) &&
      !isLikelyFragment(nameVal) &&
      !/^[\d\s.,]+$/.test(nameVal) &&
      !productVal
    ) {
      if (currentDish != null && currentIngredients.length > 0) flushCard(undefined);
      currentDish = nameVal;
    }

    // Строка с продуктом (ингредиент) — только до границы секции; по структуре таблицы колонки весов — числа
    if (productVal) {
      const grossValLooksLikeText = grossVal.trim().length > 12 && /[а-яёa-z]{3,}/i.test(grossVal);
      const netValLooksLikeText = netVal.trim().length > 12 && /[а-яёa-z]{3,}/i.test(netVal);
      if (grossValLooksLikeText || netValLooksLikeText) continue;
      if (currentDish == null && nameVal && nameVal.trim().toLowerCase() !== "выход" && isValidDishName(nameVal)) currentDish = nameVal;
      const norm = (s: string) => s.trim().toLowerCase();
      if (currentDish != null && norm(productVal) === norm(currentDish)) continue;
      let gross = parseNum(grossVal);
      let net = parseNum(netVal);
      if ((gross != null && gross > 100000) || (net != null && net > 100000)) continue;
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
      if ((gross == null || gross <= 0) && (net == null || net <= 0)) continue;
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

/** Нормализация ячейки для подписи. Совпадает с _headerSignature в Dart: trim, toLowerCase, схлопывание пробелов — чтобы один формат не дублировался из‑за пробелов. */
function normalizeCellForSignature(s: string): string {
  return (s ?? "").trim().toLowerCase().replace(/\s+/g, " ");
}

/** Ячейка похожа на заголовок колонки (брутто, нетто, наименование...), а не на название блюда. Совпадает с Dart _isStructuralHeaderCell. */
function isStructuralHeaderCell(cell: string): boolean {
  const low = (cell ?? "").trim().toLowerCase();
  if (!low || low.length > 80) return false;
  if (/^[а-яА-ЯёЁ\s]+\s+к\s+[а-яА-ЯёЁ\s]+$/.test((cell ?? "").trim()) && (cell ?? "").trim().length < 35) return false;
  const structural = [
    "наименование", "продукт", "брутто", "нетто", "название", "сырьё", "ингредиент", "расход", "норма",
    "ед.изм", "ед изм", "единица", "отход", "выход", "№", "n",
  ];
  return structural.some((k) => low.includes(k)) || low === "бр" || low === "нт";
}

/** Подпись заголовка для сопоставления с каталогом шаблонов. Только структурные ячейки (колонки), чтобы один формат таблицы давал одну подпись у разных файлов и обучение применялось ко всем. */
export function headerSignature(headerCells: string[]): string {
  const normalized = headerCells.map((c) => normalizeCellForSignature(c)).filter(Boolean);
  const structural = normalized.filter((c) => isStructuralHeaderCell(c));
  const parts = structural.length > 0 ? structural : normalized;
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
  const tableEndRow = findTableEndRow(rows, headerIdx + 1);

  const flushCard = (yieldGrams?: number | null) => {
    if (currentDish != null && (currentDish.length > 0 || currentIngredients.length > 0)) {
      const techText = technologyParts.filter((s) => s.length > 15 && !/требования к оформлению|требования к подаче|информация о пищевой/i.test(s)).join("\n").trim() || null;
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

  const isJunkProductName = (s: string) => fromPdf ? isStructuralProductName(s, true) : isStructuralProductName(s, false);

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
        if (s.toLowerCase() === "выход") continue;
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
        if (n != null && n > 0 && n < 10000) numCells.push({ col: c, val: v, num: n });
      }
      if (numCells.length >= 1 && !grossVal.trim()) grossVal = numCells[0].val;
      if (numCells.length >= 2 && !netVal.trim()) netVal = numCells[1].val;
      else if (numCells.length >= 1 && !netVal.trim()) netVal = numCells[0].val;
    }
    const wasteVal = wasteCol >= 0 && wasteCol < cells.length ? cells[wasteCol] : "";
    const outputVal = outputCol >= 0 && outputCol < cells.length ? cells[outputCol] : "";
    const techVal = technologyCol >= 0 && technologyCol < cells.length ? cells[technologyCol] : "";
    const isPastTable = r >= tableEndRow;
    if (isPastTable && techVal.trim().length > 15) technologyParts.push(techVal.trim());

    // По структуре таблицы: в колонках брутто/нетто — числа, не текст (футер, объединённые ячейки)
    const grossValLooksLikeText = grossVal.trim().length > 12 && /[а-яёa-z]{3,}/i.test(grossVal);
    const netValLooksLikeText = netVal.trim().length > 12 && /[а-яёa-z]{3,}/i.test(netVal);
    if (productVal && (grossValLooksLikeText || netValLooksLikeText)) continue;

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
      let outG = parseNum(outputVal) || parseNum(grossVal) || parseNum(netVal);
      if (outG == null && cells.length > 1) outG = parseNum(cells[1]);
      const outputColIsKgStored = outputCol >= 0 && outputCol < headerRow.length && headerRow[outputCol]?.includes("кг");
      if (outputColIsKgStored && outG != null && outG > 0 && outG < 100) outG = outG * 1000;
      flushCard(outG ?? undefined);
      currentDish = null;
      continue;
    }
    if (nameVal.trim().toLowerCase() === "выход" || productVal.trim().toLowerCase() === "выход") {
      let outG = parseNum(grossVal) || parseNum(netVal) || parseNum(outputVal);
      if (outG == null && cells.length > 1) outG = parseNum(cells[1]);
      const outputColIsKgStored = outputCol >= 0 && outputCol < headerRow.length && headerRow[outputCol]?.includes("кг");
      if (outputColIsKgStored && outG != null && outG > 0 && outG < 100) outG = outG * 1000;
      flushCard(outG ?? undefined);
      currentDish = null;
      continue;
    }
    const rowText = cells.join(" ").toLowerCase();
    const pastTableInPdf = fromPdf && isPastTable;
    const rowHasWeightStored = (grossNum != null && grossNum > 0) || (netNum != null && netNum > 0);
    if ((!fromPdf || !pastTableInPdf) && nameVal && nameVal.trim().toLowerCase() !== "выход" && !rowHasWeightStored && isValidDish(nameVal) && !isLikelyFragment(nameVal) && !/^[\d\s.,]+$/.test(nameVal) && !productVal) {
      if (currentDish != null && currentIngredients.length > 0) flushCard(undefined);
      currentDish = nameVal;
    }
    if (productVal && (!fromPdf || !pastTableInPdf) && isValidProduct(productVal) && !isJunkProductName(productVal)) {
      if ((grossNum != null && grossNum > 100000) || (netNum != null && netNum > 100000)) continue;
      if ((grossNum == null || grossNum <= 0) && (netNum == null || netNum <= 0)) continue;
      const hasWeight = (grossNum != null && grossNum > 0) || (netNum != null && netNum > 0);
      if (currentDish == null && nameVal && nameVal.trim().toLowerCase() !== "выход" && !hasWeight && isValidDish(nameVal) && !isHeaderWord(nameVal) && !isLikelyFragment(nameVal)) currentDish = nameVal;
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
 * Склеивает многострочные ячейки PDF (Shama.Book и др.): «Сливки 38%» + «жирности» + «160 160...».
 * Только для PDF.
 */
export function pdfMergeContinuationLines(text: string): string {
  const lines = text.split(/\r\n|\r|\n/).map((l) => l.trim()).filter(Boolean);
  if (lines.length < 2) return text;

  const merged: string[] = [];
  let i = 0;
  while (i < lines.length) {
    let line = lines[i];
    let j = i + 1;
    // Строка неполная: заканчивается на %, ), ,, ( или без весов в конце; следующая — продолжение
    while (j < lines.length) {
      const next = lines[j];
      const trimmed = line.trim();
      const endsWithContinuation = /[%),\s]$/.test(trimmed) || /[а-яёa-z]$/i.test(trimmed);
      const trailingNums = line.match(/([\d,.\s]+)$/);
      const hasTrailingWeights = !!trailingNums && trailingNums[1].trim().split(/\s+/).filter(Boolean).length >= 2;
      const nextIsContinuation =
        (next.length <= 25 && !/^\d+\s+[а-яА-Яё]/i.test(next) && !/^технологическ|^допустимые|^информация/i.test(next)) ||
        /^[а-яёa-z\(\)]/.test(next) ||
        /^[\d,.\s]+$/.test(next);
      if (!hasTrailingWeights && (endsWithContinuation || line.length < 30) && nextIsContinuation && j - i < 3) {
        line = line + " " + next;
        j++;
      } else {
        break;
      }
    }
    merged.push(line);
    i = j;
  }
  return merged.join("\n");
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
