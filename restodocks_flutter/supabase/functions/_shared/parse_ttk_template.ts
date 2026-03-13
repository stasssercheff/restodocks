/**
 * Парсинг ТТК по шаблону — без AI.
 * Ищет заголовки (Продукт, Брутто, Нетто...) и извлекает данные по найденным колонкам.
 */

const NAME_KEYS = ["наименование", "название", "блюдо", "пф", "name", "dish"];
const PRODUCT_KEYS = ["продукт", "сырьё", "сырья", "ингредиент", "product", "ingredient"];
// Сборник/ГОСТ: "Расход сырья на 1 порцию", "Наименование сырья", "Брутто", "Нетто"
const GROSS_KEYS = ["брутто", "бр", "вес брутто", "вес гр", "вес гр/шт", "расход сырья", "расход", "норма", "норма закладки", "масса", "gross"];
const NET_KEYS = ["нетто", "нт", "вес нетто", "net"];
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
        grossCol = c;
      }
      if (NET_KEYS.some((k) => cell.includes(k))) {
        headerIdx = r;
        netCol = c;
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

  // Название блюда часто в первых строках (шапка ТТК до таблицы)
  let initialDish: string | null = null;
  const headerKeys = [...NAME_KEYS, ...PRODUCT_KEYS, ...GROSS_KEYS, ...NET_KEYS, ...WASTE_KEYS, ...OUTPUT_KEYS, ...UNIT_KEYS];
  for (let r = 0; r < headerIdx && r < rows.length; r++) {
    const row = rows[r] ?? [];
    for (let c = 0; c < row.length; c++) {
      const cell = (row[c] ?? "").trim();
      if (cell.length < 3 || !isValidDishName(cell)) continue;
      if (cell.endsWith(":")) continue;
      if (/^\d{1,2}\.\d{1,2}\.\d{2,4}/.test(cell)) continue;
      if (cell.toLowerCase().startsWith("технологическая карта")) continue;
      if (cell.toLowerCase().includes("название на чеке") || cell.toLowerCase().includes("название чека")) continue;
      if (cell.toLowerCase().includes("органолептическ") || cell.toLowerCase().includes("внешний вид") || cell.toLowerCase().includes("консистенция") || cell.toLowerCase().includes("запах") || cell.toLowerCase().includes("вкус") || cell.toLowerCase().includes("цвет")) continue;
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

  const flushCard = () => {
    if (currentDish != null && (currentDish.length > 0 || currentIngredients.length > 0)) {
      results.push({
        dishName: currentDish || null,
        technologyText: null,
        ingredients: [...currentIngredients],
        isSemiFinished: (currentDish ?? "").toLowerCase().includes("пф"),
      });
    }
    currentIngredients.length = 0;
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
      flushCard();
      currentDish = null;
      continue;
    }
    if (productVal.toLowerCase().includes("выход блюда") || productVal.toLowerCase().startsWith("выход одного")) continue;

    // Строка с названием блюда (начало новой карточки)
    if (
      nameVal &&
      isValidDishName(nameVal) &&
      !/^[\d\s.,]+$/.test(nameVal) &&
      !productVal
    ) {
      if (currentDish != null && currentIngredients.length > 0) flushCard();
      currentDish = nameVal;
    }

    // Строка с продуктом (ингредиент)
    if (productVal) {
      if (currentDish == null && nameVal && isValidDishName(nameVal)) currentDish = nameVal;
      let gross = parseNum(grossVal);
      let net = parseNum(netVal);
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
  flushCard();

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
  },
): TtkCard[] {
  const { headerIdx, nameCol, productCol, grossCol = -1, netCol = -1, wasteCol = -1, outputCol = -1 } = opts;
  if (rows.length <= headerIdx + 1) return [];

  let currentDish: string | null = null;
  const currentIngredients: TtkIngredient[] = [];
  const results: TtkCard[] = [];

  const flushCard = () => {
    if (currentDish != null && (currentDish.length > 0 || currentIngredients.length > 0)) {
      results.push({
        dishName: currentDish || null,
        technologyText: null,
        ingredients: [...currentIngredients],
        isSemiFinished: (currentDish ?? "").toLowerCase().includes("пф"),
      });
    }
    currentIngredients.length = 0;
  };

  const unitPatterns = /^(г|кг|мл|л|шт|кдж|ккал|кдж\)|ккал\))$/i;
  const isValidDish = (s: string) =>
    s.length >= 4 && !unitPatterns.test(s.replace(/\s/g, "")) && !/^\d+\s*кдж\)?$/i.test(s) && /[а-яА-ЯёЁa-zA-Z]{2,}/.test(s);

  for (let r = 0; r < headerIdx && r < rows.length; r++) {
    for (const c of rows[r] ?? []) {
      const s = (c ?? "").trim();
      if (s.length < 3 || !isValidDish(s)) continue;
      if (s.endsWith(":")) continue;
      if (/^\d{1,2}\.\d{1,2}\.\d{2,4}/.test(s)) continue;
      if (s.toLowerCase().startsWith("технологическая карта")) continue;
      currentDish = s;
      break;
    }
    if (currentDish != null) break;
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
    const productVal = pCol < cells.length ? cells[pCol] : "";
    const grossVal = gCol >= 0 && gCol < cells.length ? cells[gCol] : "";
    const netVal = nCol >= 0 && nCol < cells.length ? cells[nCol] : "";
    const wasteVal = wasteCol >= 0 && wasteCol < cells.length ? cells[wasteCol] : "";
    const outputVal = outputCol >= 0 && outputCol < cells.length ? cells[outputCol] : "";

    if (nameVal.toLowerCase() === "итого" || productVal.toLowerCase() === "итого") {
      flushCard();
      currentDish = null;
      continue;
    }
    if (nameVal && isValidDish(nameVal) && !/^[\d\s.,]+$/.test(nameVal) && !productVal) {
      if (currentDish != null && currentIngredients.length > 0) flushCard();
      currentDish = nameVal;
    }
    if (productVal) {
      if (currentDish == null && nameVal && isValidDish(nameVal)) currentDish = nameVal;
      let waste = parseNum(wasteVal);
      const gross = parseNum(grossVal);
      const net = parseNum(netVal);
      if (gross != null && gross > 0 && net != null && net < gross && (waste == null || waste === 0)) {
        waste = (1 - net / gross) * 100;
      }
      currentIngredients.push({
        productName: productVal,
        grossGrams: gross,
        netGrams: net,
        primaryWastePct: waste,
        outputGrams: parseNum(outputVal),
        unit: "g",
      });
    }
  }
  flushCard();
  return results;
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
