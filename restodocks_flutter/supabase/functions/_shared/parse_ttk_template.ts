/**
 * Парсинг ТТК по шаблону — без AI.
 * Ищет заголовки (Продукт, Брутто, Нетто...) и извлекает данные по найденным колонкам.
 */

const NAME_KEYS = ["наименование", "название", "блюдо", "пф", "name", "dish"];
const PRODUCT_KEYS = ["продукт", "сырьё", "ингредиент", "product", "ingredient"];
const GROSS_KEYS = ["брутто", "бр", "gross"];
const NET_KEYS = ["нетто", "нт", "net"];
const WASTE_KEYS = ["отход", "отх", "waste", "процент отхода"];

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
    }
    if (headerIdx >= 0 && (nameCol >= 0 || productCol >= 0)) break;
  }

  if (headerIdx < 0 || (nameCol < 0 && productCol < 0)) return [];

  if (nameCol < 0) nameCol = 0;
  if (productCol < 0) productCol = 1;

  const results: TtkCard[] = [];
  let currentDish: string | null = null;
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
    const nameVal = nameCol < cells.length ? cells[nameCol] : "";
    const productVal = productCol < cells.length ? cells[productCol] : "";
    const grossVal = grossCol >= 0 && grossCol < cells.length ? cells[grossCol] : "";
    const netVal = netCol >= 0 && netCol < cells.length ? cells[netCol] : "";
    const wasteVal = wasteCol >= 0 && wasteCol < cells.length ? cells[wasteCol] : "";

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
      currentIngredients.push({
        productName: productVal,
        grossGrams: parseNum(grossVal),
        netGrams: parseNum(netVal),
        primaryWastePct: parseNum(wasteVal),
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
