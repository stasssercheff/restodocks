/**
 * Парсер Калькуляционных карт (КК) — унифицированная форма №ОП-1.
 *
 * Структура КК (ГОСТ, постановление Госкомстата 25.12.98 №132):
 * - Название блюда: «наименование блюда» (отдельная строка)
 * - Таблица: № | Продукты (наименование, код) | Норма | Ед.изм. | Цена, руб.коп. | Сумма, руб.коп.
 * - Т. = товар (сырьё), П/Ф = полуфабрикат
 * - Норма: 0,100 кг (запятая — десятичный разделитель)
 * - Цена: за единицу (за кг, за л, за шт)
 * - Сумма: Норма × Цена
 * - Выход: «Выход одного блюда в готовом виде, кг»
 *
 * Используется для ТТК: состав + цены. Продукты без цен в номенклатуре получают цену из документа.
 */

import type { TtkCard, TtkIngredient } from "./parse_ttk_template.ts";

function parseNum(s: string): number | null {
  if (!s || !s.trim()) return null;
  const cleaned = s.replace(/\s/g, "").replace(/,/g, ".").replace(/[^\d.\-]/g, "");
  const n = parseFloat(cleaned);
  return Number.isNaN(n) ? null : n;
}

/** Ед.изм. → множитель для перевода в граммы (для кг, л) */
function normToGrams(norm: number, unit: string): number {
  const u = (unit || "кг").toLowerCase().trim();
  if (u === "кг" || u === "kg") return norm * 1000;
  if (u === "л" || u === "l") return norm * 1000; // мл
  return norm; // шт — оставляем как есть, unit будет "шт"
}

/** Требует расширения TtkIngredient — пока возвращаем расширенный тип */
export interface KkIngredient extends TtkIngredient {
  pricePerKg?: number | null;
}

export interface KkCard extends TtkCard {
  ingredients: KkIngredient[];
}

function detectKkFormat(text: string): boolean {
  const lower = text.toLowerCase();
  return (
    lower.includes("калькуляционная карта") ||
    lower.includes("форма №оп-1") ||
    lower.includes("ооп-1")
  );
}

/**
 * Разбивает текст PDF на блоки (одна КК = один блок).
 * Разделитель: "-- N of M --" (pdf-parse) или повтор "наименование блюда" / "КАЛЬКУЛЯЦИОННАЯ КАРТА".
 */
function splitKkBlocks(text: string): string[] {
  const blocks: string[] = [];
  const parts = text.split(/\s*--\s*\d+\s+of\s+\d+\s*--/i);
  for (const p of parts) {
    const t = p.trim();
    if (t.length > 50) blocks.push(t);
  }
  if (blocks.length > 0) return blocks;
  return [text];
}

/**
 * Извлекает название блюда из блока.
 * В форме ОП-1: название рядом с «наименование блюда» или «структурное подразделение».
 */
function extractDishName(block: string): string | null {
  const lines = block.split(/\n/).map((l) => l.trim()).filter(Boolean);
  for (let i = 0; i < lines.length; i++) {
    const lower = lines[i].toLowerCase();
    if (lower.includes("структурное подразделение") || lower === "наименование блюда") {
      const next = lines[i + 1];
      if (next && next.length >= 2 && next.length < 100 && /[а-яА-ЯёЁa-zA-Z]/.test(next)) {
        if (!/^[\d\s.,:]+$/.test(next) && !next.toLowerCase().includes("организация")) {
          return next;
        }
      }
    }
    if (lower === "наименование блюда" && i > 0) {
      const prev = lines[i - 1];
      if (prev && prev.length >= 2 && /[а-яА-ЯёЁ]/.test(prev) && !prev.includes("Ресторан") && !prev.includes("организация")) {
        return prev;
      }
    }
  }
  const beforeKk = block.split(/калькуляционная\s+карта/i)[0];
  const beforeLines = beforeKk.split(/\n/).map((l) => l.trim()).filter(Boolean);
  for (let i = beforeLines.length - 1; i >= 0; i--) {
    const line = beforeLines[i];
    if (line.length >= 3 && line.length < 80 && /[а-яА-ЯёЁa-zA-Z]/.test(line)) {
      if (!/^[\d\s.,]+$/.test(line) && !/организация|подразделение|окуд|окпо/.test(line.toLowerCase())) {
        return line;
      }
    }
  }
  return null;
}

/**
 * Извлекает «Выход одного блюда в готовом виде, кг» (в кг).
 */
function extractOutputKg(block: string): number | null {
  const match = block.match(/выход\s+одного\s+блюда[^\d]*([\d\s,]+)/i);
  if (match) return parseNum(match[1]);
  return null;
}

/**
 * Парсит строку ингредиента КК.
 * Формат: "1 Т. Гребешок с/м 00479 0,100 3 286,24 328,62 кг"
 * или: "6 Т. Икра сига/палтуса 04550 0,002 4 726,77 9,45 кг"
 * Код — 5 цифр, норма — число с запятой, цена и сумма — могут с пробелом как разряд (3 286,24).
 */
function parseIngredientLine(line: string): KkIngredient | null {
  const trimmed = line.trim();
  if (trimmed.length < 10) return null;

  const leadMatch = trimmed.match(/^(\d+)\s+(Т\.|П\/Ф|П\/ф)\s+(.+)$/i);
  if (!leadMatch) return null;
  const productPart = leadMatch[3];
  const isPf = /п\/ф|п\/Ф/i.test(leadMatch[2]);

  // В конце: код(5 цифр) норма цена сумма [единица]
  const tailMatch = productPart.match(/\s+(\d{5})\s+([\d\s,.\-]+)\s+([\d\s,.\-]+)\s+([\d\s,.\-]+)\s*(кг|л|шт)?\s*$/i);
  if (!tailMatch) return null;

  const productName = productPart.slice(0, productPart.length - tailMatch[0].length).trim();
  if (!productName || productName.length < 2) return null;

  const norm = parseNum(tailMatch[2]);
  const price = parseNum(tailMatch[3]);
  const unit = (tailMatch[5] || "кг").trim().toLowerCase();
  if (norm == null || norm < 0) return null;

  const grams = unit === "шт" ? norm : normToGrams(norm, unit);
  const actualUnit = unit === "л" ? "ml" : unit === "кг" ? "g" : unit === "шт" ? "pcs" : "g";

  let pricePerKg: number | null = null;
  if (price != null && price > 0) {
    if (unit === "кг" || unit === "kg") pricePerKg = price;
    else if (unit === "л" || unit === "l") pricePerKg = price;
    else if (unit === "шт") pricePerKg = (norm > 0 ? price / norm : 0) * 1000;
  }

  return {
    productName,
    grossGrams: grams,
    netGrams: grams,
    primaryWastePct: null,
    outputGrams: null,
    unit: actualUnit,
    pricePerKg: pricePerKg ?? undefined,
    ingredientType: isPf ? "semi_finished" : "product",
  } as KkIngredient;
}

/**
 * Извлекает строки таблицы ингредиентов (между заголовком и «Общая стоимость»).
 */
function extractIngredientLines(block: string): string[] {
  const lines: string[] = [];
  const allLines = block.split(/\n/).map((l) => l.trim()).filter(Boolean);
  let inTable = false;
  for (const line of allLines) {
    if (/^[\d]+\s+(Т\.|П\/Ф|П\/ф)\s+.+\d{4,6}\s+[\d\s,]+\s+[\d\s,]+/i.test(line)) {
      inTable = true;
      lines.push(line);
    } else if (inTable && line.toLowerCase().includes("общая стоимость")) {
      break;
    } else if (inTable && line.match(/^[\d]+\s+.+\d{4,6}/)) {
      lines.push(line);
    }
  }
  return lines;
}

/**
 * Парсит один блок КК в карточку.
 */
function parseKkBlock(block: string): KkCard | null {
  const dishName = extractDishName(block);
  const outputKg = extractOutputKg(block);
  const ingredientLines = extractIngredientLines(block);
  const ingredients: KkIngredient[] = [];
  for (const line of ingredientLines) {
    const ing = parseIngredientLine(line);
    if (ing && ing.productName) ingredients.push(ing);
  }
  if (ingredients.length === 0) return null;

  return {
    dishName: dishName || null,
    technologyText: null,
    ingredients,
    isSemiFinished: false, // КК — обычно блюда
  };
}

/**
 * Парсит текст PDF в формате КК (ОП-1).
 * Возвращает массив карточек или пустой массив, если формат не КК.
 */
export function parseKkOp1(text: string): KkCard[] {
  if (!detectKkFormat(text)) return [];
  const blocks = splitKkBlocks(text);
  const results: KkCard[] = [];
  for (const block of blocks) {
    const card = parseKkBlock(block);
    if (card) results.push(card);
  }
  return results;
}
