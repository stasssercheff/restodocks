/**
 * Fingerprinting: определение шаблона ТТК по первым N строкам.
 * Сигнатуры — ключевые слова и их координаты для iiko, ГОСТ, generic.
 */

export type TemplateId = "iiko" | "gost" | "generic";

export interface SignatureHit {
  keyword: string;
  row: number;
  col: number;
  weight: number;
}

export interface FingerprintResult {
  templateId: TemplateId;
  confidence: number; // 0–100
  hits: SignatureHit[];
  hint?: string; // "На 80% уверен, что это iiko, но структура чуть сбита"
}

/** Сигнатуры шаблонов: ключевое слово, ожидаемая строка (или -1 — любая), колонка (-1 — любая), вес */
const TEMPLATE_SIGNATURES: { template: TemplateId; keyword: string; row: number; col: number; weight: number }[] = [
  // iiko: № | Наименование продукта | Ед.изм | Брутто | Вес брутто кг | Вес нетто кг
  { template: "iiko", keyword: "iiko", row: -1, col: -1, weight: 25 },
  { template: "iiko", keyword: "наименование продукта", row: -1, col: -1, weight: 15 },
  { template: "iiko", keyword: "вес брутто кг", row: -1, col: -1, weight: 12 },
  { template: "iiko", keyword: "вес нетто кг", row: -1, col: -1, weight: 12 },
  { template: "iiko", keyword: "ед.изм", row: -1, col: -1, weight: 8 },
  // ГОСТ / Сборник: Утверждаю, Наименование сырья, Расход сырья, Выход готовой продукции
  { template: "gost", keyword: "утверждаю", row: 3, col: 1, weight: 20 },
  { template: "gost", keyword: "утверждаю", row: -1, col: -1, weight: 10 },
  { template: "gost", keyword: "наименование сырья", row: -1, col: -1, weight: 15 },
  { template: "gost", keyword: "расход сырья на 1 порцию", row: -1, col: -1, weight: 15 },
  { template: "gost", keyword: "расход сырья", row: -1, col: -1, weight: 10 },
  { template: "gost", keyword: "выход готовой продукции", row: -1, col: -1, weight: 12 },
  { template: "gost", keyword: "наименование", row: 9, col: 0, weight: 8 },
  // generic: стандартные заголовки
  { template: "generic", keyword: "наименование", row: -1, col: -1, weight: 5 },
  { template: "generic", keyword: "брутто", row: -1, col: -1, weight: 5 },
  { template: "generic", keyword: "нетто", row: -1, col: -1, weight: 5 },
  { template: "generic", keyword: "продукт", row: -1, col: -1, weight: 5 },
];

const FINGERPRINT_MAX_ROWS = 50;

/**
 * Определяет шаблон по первым maxRows строкам.
 */
export function detectTemplateFingerprint(
  rows: string[][],
  maxRows: number = FINGERPRINT_MAX_ROWS,
): FingerprintResult {
  const scanRows = rows.slice(0, Math.min(maxRows, rows.length));
  const hits: SignatureHit[] = [];
  const scores: Record<TemplateId, number> = { iiko: 0, gost: 0, generic: 0 };

  for (let r = 0; r < scanRows.length; r++) {
    const row = scanRows[r] ?? [];
    for (let c = 0; c < row.length; c++) {
      const cell = (row[c] ?? "").trim().toLowerCase();
      if (!cell) continue;
      for (const sig of TEMPLATE_SIGNATURES) {
        if (!cell.includes(sig.keyword)) continue;
        const rowMatch = sig.row < 0 || sig.row === r;
        const colMatch = sig.col < 0 || sig.col === c;
        if (rowMatch && colMatch) {
          hits.push({ keyword: sig.keyword, row: r, col: c, weight: sig.weight });
          scores[sig.template] = (scores[sig.template] ?? 0) + sig.weight;
        }
      }
    }
  }

  const total = hits.reduce((s, h) => s + h.weight, 0);
  const best = (["iiko", "gost", "generic"] as TemplateId[]).reduce(
    (a, b) => (scores[a] > scores[b] ? a : b),
  );
  const bestScore = scores[best];
  const secondBest = (["iiko", "gost", "generic"] as TemplateId[]).filter((t) => t !== best).reduce(
    (a, b) => (scores[a] > scores[b] ? a : b),
  );
  const secondScore = scores[secondBest];

  let confidence = total > 0 ? Math.min(100, Math.round((bestScore / Math.max(total * 0.5, 30)) * 100)) : 0;
  if (confidence > 100) confidence = 100;

  let hint: string | undefined;
  if (confidence >= 60 && confidence < 90 && secondScore > 0) {
    const names: Record<TemplateId, string> = { iiko: "iiko", gost: "ГОСТ", generic: "универсальный" };
    hint = `На ${confidence}% уверен, что это шаблон ${names[best]}, но есть признаки ${names[secondBest]}. Попробовать распознать?`;
  }

  return { templateId: best, confidence, hits, hint };
}
