/**
 * Парсинг ТТК по шаблону — без AI.
 * Ищет заголовки (Продукт, Брутто, Нетто...) и извлекает данные по найденным колонкам.
 */

const NAME_KEYS = ["наименование", "название", "блюдо", "пф", "name", "dish"];
const PRODUCT_KEYS = ["продукт", "сырьё", "ингредиент", "product", "ingredient"];
const GROSS_KEYS = ["брутто", "бр", "вес брутто", "gross"];
const NET_KEYS = ["нетто", "нт", "вес нетто", "net"];
const WASTE_KEYS = ["отход", "отх", "waste", "процент отхода"];
const OUTPUT_KEYS = ["выход", "вес готового", "готовый", "output"];

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

  for (let r = 0; r < rows.length && r < 5; r++) {
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
    }
    if (headerIdx >= 0 && (nameCol >= 0 || productCol >= 0)) break;
  }

  if (headerIdx < 0 || (nameCol < 0 && productCol < 0)) return [];

  if (nameCol < 0) nameCol = 0;
  if (productCol < 0) productCol = 1;

  // Название блюда часто в первых строках (шапка ТТК до таблицы)
  let initialDish: string | null = null;
  const headerKeys = [...NAME_KEYS, ...PRODUCT_KEYS, ...GROSS_KEYS, ...NET_KEYS, ...WASTE_KEYS, ...OUTPUT_KEYS];
  for (let r = 0; r < headerIdx && r < rows.length; r++) {
    const row = rows[r] ?? [];
    for (let c = 0; c < row.length; c++) {
      const cell = (row[c] ?? "").trim();
      if (cell.length < 15) continue;
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

    if (nameVal.toLowerCase() === "итого" || productVal.toLowerCase() === "итого") {
      flushCard();
      currentDish = null;
      continue;
    }

    // Строка с названием блюда (начало новой карточки)
    if (
      nameVal &&
      !/^[\d\s.,]+$/.test(nameVal) &&
      !productVal
    ) {
      if (currentDish != null && currentIngredients.length > 0) flushCard();
      currentDish = nameVal;
    }

    // Строка с продуктом (ингредиент)
    if (productVal) {
      if (currentDish == null && nameVal) currentDish = nameVal;
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

/** Подпись заголовка для сопоставления с каталогом шаблонов */
export function headerSignature(headerCells: string[]): string {
  return headerCells.map((c) => (c ?? "").trim().toLowerCase()).filter(Boolean).join("|");
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

  for (let r = 0; r < headerIdx && r < rows.length; r++) {
    for (const c of rows[r] ?? []) {
      const s = (c ?? "").trim();
      if (s.length < 3) continue;
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
    if (nameVal && !/^[\d\s.,]+$/.test(nameVal) && !productVal) {
      if (currentDish != null && currentIngredients.length > 0) flushCard();
      currentDish = nameVal;
    }
    if (productVal) {
      if (currentDish == null && nameVal) currentDish = nameVal;
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
