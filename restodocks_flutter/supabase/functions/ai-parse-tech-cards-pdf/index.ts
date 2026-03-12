// Supabase Edge Function: распознавание ТТК из PDF
// Динамический импорт unpdf/AI — ускоряет cold start, warm-запрос возвращается сразу
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

function corsHeaders(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin || "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
}

const PDF_SYSTEM_PROMPT = `Ты парсер технологических карт (ТТК, рецептов, полуфабрикатов, калькуляционных карт КК ОП-1). На входе — сырой текст из PDF или документа Word (экспорт в текст).

КРИТИЧНО: Если в тексте есть хоть какая-то ТТК (название блюда/ПФ, ингредиенты, технология) — ты ОБЯЗАН извлечь хотя бы одну карточку. Подстраивайся под ЛЮБОЙ формат: Shama.Book, iiko, ГОСТ, КК (форма №ОП-1), Сборник технологических карт (Сборник рецептур), документы Word (кухня, июнь 2012 и т.п.), собственные шаблоны. Не требуй точного соответствия образцу.

Документ может содержать МНОГО карточек подряд (50–200+). Извлекай ВСЕ найденные ТТК — каждая секция "Технологическая карта №" / "1.Рецептура" / "Наименование сырья | Брутто | Нетто" = новая карточка.

Форматы: ГОСТ 31987-2012, СТБ 1210, Сборник: таблица "Наименование сырья" + "Расход сырья на 1 порцию" (г, мл) с колонками Брутто/Нетто; строка "Выход готовой продукции" (г). Варианты по сезону (Свекла до 01.01 / с 01.01) — брать оба или основной.

Структура бывает разной: название в заголовке или отдельной строке; таблица с колонками № / Наименование / Продукт / Сырьё / Брутто / Нетто / Расход / Норма / Цена / Сумма; числа в граммах или кг (запятая как десятичный разделитель). Для grossGrams/netGrams бери любые подходящие числа (брутто, нетто, норма в кг×1000). ingredientType: "product" — сырьё (Т.); "semi_finished" — ПФ (П/Ф). isSemiFinished: true если в названии "ПФ".

Если есть КК (калькуляционная карта) с ценами — извлекай pricePerKg (цена за кг или за л, руб.) для каждого ингредиента. Это важно для расчёта себестоимости.

Верни ТОЛЬКО валидный JSON, без markdown и обёрток:
{ "cards": [ { "dishName": string, "technologyText": string|null, "isSemiFinished": boolean|null, "ingredients": [ { "productName": string, "grossGrams": number|null, "netGrams": number|null, "primaryWastePct": number|null, "cookingMethod": string|null, "cookingLossPct": number|null, "unit": string|null, "ingredientType": "product"|"semi_finished"|null, "pricePerKg": number|null } ] } ] }

Если нет ни одной карточки: { "cards": [] }`;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders(req.headers.get("Origin")) });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  }

  try {
    const body = (await req.json()) as { pdfBase64?: string; establishmentId?: string };
    const pdfBase64 = body.pdfBase64;
    const establishmentId = typeof body.establishmentId === "string" ? body.establishmentId.trim() : undefined;
    if (!pdfBase64 || typeof pdfBase64 !== "string") {
      return new Response(JSON.stringify({ error: "pdfBase64 required" }), {
        status: 400,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }
    if (pdfBase64 === "warm") {
      return new Response(JSON.stringify({ cards: [], reason: "warm" }), {
        status: 200,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }
    const MAX_B64 = 2.5 * 1024 * 1024;
    if (pdfBase64.length > MAX_B64) {
      return new Response(JSON.stringify({ cards: [], reason: "extraction_failed: PDF too large (max ~1.8MB)" }), {
        status: 200,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    const hasProvider = Deno.env.get("GROQ_API_KEY")?.trim() ||
      Deno.env.get("GEMINI_API_KEY")?.trim() ||
      Deno.env.get("GIGACHAT_AUTH_KEY")?.trim() ||
      Deno.env.get("OPENAI_API_KEY");
    if (!hasProvider) {
      return new Response(JSON.stringify({ error: "AI provider key required" }), {
        status: 500,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    // Polyfill DOMMatrix — в Deno Edge нет, нужен для pdf-parse/PDF.js
    if (typeof globalThis.DOMMatrix === "undefined") {
      const { default: DOMMatrix } = await import("npm:@thednp/dommatrix@2.0.12");
      (globalThis as unknown as { DOMMatrix: unknown }).DOMMatrix = DOMMatrix;
    }
    const { PDFParse } = await import("npm:pdf-parse");
    const { chatText } = await import("../_shared/ai_provider.ts");
    const { pdfTextToRows, parseTtkByTemplate, parseTtkByTemplateSafe } = await import("../_shared/parse_ttk_template.ts");
    const { detectTemplateFingerprint } = await import("../_shared/parse_ttk_fingerprint.ts");
    const { parseKkOp1 } = await import("../_shared/parse_kk_op1.ts");

    let bytes: Uint8Array;
    try {
      const binary = atob(pdfBase64.replace(/\s/g, ""));
      bytes = new Uint8Array(binary.length);
      for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
      }
    } catch (e) {
      const errMsg = e instanceof Error ? e.message : String(e);
      return new Response(JSON.stringify({ cards: [], reason: `extraction_failed: invalid base64: ${errMsg.slice(0, 80)}` }), {
        status: 200,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    let text: string;
    try {
      const parser = new PDFParse({ data: bytes });
      const result = await parser.getText();
      await parser.destroy();
      // Сохраняем переносы строк — нужны для шаблонного парсинга
      text = (result?.text ?? "").replace(/\r\n/g, "\n").replace(/\r/g, "\n").trim();
    } catch (e) {
      const errMsg = e instanceof Error ? e.message : String(e);
      const part = errMsg.slice(0, 200).replace(/["\n\r]/g, " ");
      console.error("[ai-parse-tech-cards-pdf] extraction failed:", errMsg);
      return new Response(JSON.stringify({ cards: [], reason: `extraction_failed: ${part}` }), {
        status: 200,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    if (!text.trim()) {
      return new Response(JSON.stringify({ cards: [], reason: "empty_text" }), {
        status: 200,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    // 0. КК (калькуляционная карта ОП-1) — формат с ценами
    const kkCards = parseKkOp1(text);
    if (kkCards.length > 0) {
      const normalized = kkCards.map((card) => ({
        dishName: card.dishName ?? null,
        technologyText: card.technologyText ?? null,
        isSemiFinished: card.isSemiFinished ?? undefined,
        ingredients: card.ingredients.map((i) => ({
          productName: i.productName,
          grossGrams: i.grossGrams ?? undefined,
          netGrams: i.netGrams ?? undefined,
          outputGrams: i.outputGrams ?? undefined,
          primaryWastePct: i.primaryWastePct ?? undefined,
          unit: i.unit ?? "g",
          pricePerKg: i.pricePerKg ?? undefined,
          ingredientType: (i as { ingredientType?: string }).ingredientType ?? undefined,
        })),
      }));
      return new Response(
        JSON.stringify({ cards: normalized, reason: "kk_op1" }),
        { status: 200, headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" } },
      );
    }

    const rows = pdfTextToRows(text);
    const fingerprint = rows.length >= 2 ? detectTemplateFingerprint(rows, 50) : null;

    // 1. СНАЧАЛА — сохранённые шаблоны (каталог tt_parse_templates). Те же файлы, что уже сохранялись — распознаются по ним.
    let templateCards: { dishName: string | null; ingredients: unknown[] }[] = [];
    const parseErrors: Array<{ dishName?: string; error: string }> = [];
    if (rows.length >= 2) {
      const { tryParseByStoredTemplates } = await import("../_shared/try_stored_ttk_templates.ts");
      const stored = await tryParseByStoredTemplates(rows);
      if (stored && stored.length > 0) templateCards = stored;
    }
    // 2. Только если шаблон не найден — эвристический парсер
    if (templateCards.length === 0 && rows.length >= 2) {
      const parsed = parseTtkByTemplateSafe(rows);
      templateCards = parsed.cards;
      parseErrors.push(...parsed.errors);
    }

    // Shama.Book / ГОСТ: блюдо в "Проведено контрольное приготовление блюда: XXX" или на след. строке
    const dishMatch = text.match(/Проведено\s+контрольное\s+приготовление\s+блюда\s*:?\s*\n?\s*([^\n]+?)(?:\n|$)/i)
      ?? text.match(/Наименование\s+блюда[^:]*:\s*([^\n]+)/i);
    const extractedDish = dishMatch?.[1]?.trim();
    if (templateCards.length === 1 && extractedDish && !templateCards[0].dishName) {
      templateCards = [{ ...templateCards[0], dishName: extractedDish }];
    } else if (templateCards.length >= 1 && extractedDish && templateCards.every((c) => !c.dishName)) {
      templateCards = templateCards.map((c, i) => (i === 0 ? { ...c, dishName: extractedDish } : c));
    }
    if (templateCards.length > 0) {
      // Шаблон или каталог сработал — AI не используется, лимит не применяется
      const normalized = templateCards.map((card: { dishName: string | null; ingredients: unknown[] }) => ({
        dishName: card.dishName ?? null,
        technologyText: card.technologyText ?? null,
        isSemiFinished: card.isSemiFinished ?? undefined,
        ingredients: (card.ingredients ?? []).map((i: Record<string, unknown>) => ({
          productName: i.productName,
          grossGrams: i.grossGrams ?? undefined,
          netGrams: i.netGrams ?? undefined,
          outputGrams: i.outputGrams ?? undefined,
          primaryWastePct: i.primaryWastePct ?? undefined,
          unit: i.unit ?? "g",
          cookingMethod: undefined,
          cookingLossPct: undefined,
          ingredientType: undefined,
        })),
      }));
      const payload: Record<string, unknown> = { cards: normalized, reason: "template" };
      if (parseErrors.length > 0) payload.parseErrors = parseErrors;
      if (fingerprint?.hint) payload.fingerprintHint = fingerprint.hint;
      return new Response(
        JSON.stringify(payload),
        { status: 200, headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" } },
      );
    }

    // 3. Шаблон и каталог не сработали — AI. Проверяем лимит (3 ТТК/день на заведение)
    if (establishmentId) {
      const { checkAndIncrementAiTtkUsage } = await import("../_shared/ai_ttk_limit.ts");
      const { allowed } = await checkAndIncrementAiTtkUsage(establishmentId);
      if (!allowed) {
        return new Response(
          JSON.stringify({ cards: [], reason: "ai_limit_exceeded", error: "limit_3_per_day" }),
          { status: 200, headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" } },
        );
      }
    }

    const textForAi = text.replace(/\s+/g, " ").trim();
    let content: string;
    try {
      content = await chatText({
        messages: [
          { role: "system", content: PDF_SYSTEM_PROMPT },
          { role: "user", content: `PDF extracted text:\n\n${textForAi}` },
        ],
        maxTokens: 16384,
        context: "ttk",
      }) ?? "";
    } catch (aiErr) {
      return new Response(JSON.stringify({ cards: [], reason: `ai_error: ${aiErr}` }), {
        status: 200,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    if (!content?.trim()) {
      return new Response(JSON.stringify({ cards: [], reason: "ai_empty_response" }), {
        status: 200,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    let parsed: { cards?: unknown[] } | null = null;
    const cleanContent = content.replace(/^```\w*\n?|\n?```$/g, "").trim();
    const jsonCandidates = [
      cleanContent,
      content,
      content.match(/\{[\s\S]*"cards"[\s\S]*\}/)?.[0] ?? "",
      content.match(/\{[\s\S]*"cards"\s*:\s*\[[\s\S]*\]\s*[\},]/)?.[0]?.replace(/,\s*$/, "}") ?? "",
    ];
    for (const candidate of jsonCandidates) {
      if (!candidate || candidate.length < 10) continue;
      try {
        parsed = JSON.parse(candidate) as { cards?: unknown[] };
        if (Array.isArray(parsed.cards)) break;
      } catch {
        /* try next */
      }
    }

    // Retry with simpler prompt if first attempt returned no cards
    if ((!parsed || !Array.isArray(parsed.cards) || parsed.cards.length === 0) && text.length > 100) {
      try {
        const simpleContent = await chatText({
          messages: [
            { role: "system", content: "Extract tech card from text. Return JSON: { \"cards\": [ { \"dishName\": string, \"technologyText\": string|null, \"isSemiFinished\": boolean|null, \"ingredients\": [ { \"productName\": string, \"grossGrams\": number|null, \"netGrams\": number|null } ] } ] }. No markdown." },
            { role: "user", content: text },
          ],
          maxTokens: 8192,
          context: "ttk",
        });
        if (simpleContent?.trim()) {
          const simpleCleaned = simpleContent.replace(/^```\w*\n?|\n?```$/g, "").trim();
          const simpleParsed = JSON.parse(simpleCleaned) as { cards?: unknown[] };
          if (Array.isArray(simpleParsed.cards) && simpleParsed.cards.length > 0) {
            parsed = simpleParsed;
          }
        }
      } catch {
        /* keep original parsed */
      }
    }

    const cards = parsed && Array.isArray(parsed.cards) ? parsed.cards : [];
    const reasonIfEmpty = cards.length === 0 ? "ai_no_cards" : undefined;

    // Возвращаем rows для обучения шаблонов на клиенте (когда AI успешно распарсил)
    const rowsForLearning = rows.length >= 2 && cards.length > 0 ? rows : undefined;

    const normalized = cards.map((card) => {
      const c = card as Record<string, unknown>;
      const ingredients = Array.isArray(c.ingredients)
        ? (c.ingredients as Record<string, unknown>[]).map((i) => {
            const it = String(i.ingredientType ?? "").toLowerCase();
            const ingredientType = (it === "product" || it === "semi_finished") ? it : undefined;
            return {
              productName: String(i.productName ?? ""),
              grossGrams: i.grossGrams != null ? Number(i.grossGrams) : undefined,
              netGrams: i.netGrams != null ? Number(i.netGrams) : undefined,
              unit: i.unit != null ? String(i.unit) : undefined,
              cookingMethod: i.cookingMethod != null ? String(i.cookingMethod) : undefined,
              primaryWastePct: i.primaryWastePct != null ? Number(i.primaryWastePct) : undefined,
              cookingLossPct: i.cookingLossPct != null ? Number(i.cookingLossPct) : undefined,
              ingredientType,
              pricePerKg: i.pricePerKg != null ? Number(i.pricePerKg) : undefined,
            };
          })
        : [];
      return {
        dishName: c.dishName != null ? String(c.dishName) : null,
        technologyText: c.technologyText != null ? String(c.technologyText) : null,
        ingredients,
        isSemiFinished: typeof c.isSemiFinished === "boolean" ? c.isSemiFinished : undefined,
      };
    });

    const payload: Record<string, unknown> = reasonIfEmpty ? { cards: normalized, reason: reasonIfEmpty } : { cards: normalized };
    if (rowsForLearning != null) payload.rows = rowsForLearning;
    return new Response(JSON.stringify(payload), {
      status: 200,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ cards: [], reason: `error: ${e}` }), {
      status: 200,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  }
});
