// Supabase Edge Function: распознавание ТТК из PDF
// Извлечение текста: unpdf (serverless-оптимизированный PDF.js, малый бандл). Динамический импорт — cold start.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { headerSignature, isStructuralProductName, getTechnologyFromRowsUsingColumn } from "../_shared/parse_ttk_template.ts";

function corsHeaders(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin || "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
}

/** Фильтр мусорных ингредиентов — та же семантика, что в parse_ttk_template (структурные слова ≠ ингредиенты) */
function filterGarbageIngredients<T extends { productName: string }>(
  ingredients: T[],
  isStructural: (s: string) => boolean,
): T[] {
  return ingredients.filter((i) => !isStructural(i.productName ?? ""));
}

/** Нормализация для сравнения названия продукта и названия блюда (без лишних пробелов, регистра) */
function normForDishMatch(s: string): string {
  return (s ?? "").trim().toLowerCase().replace(/\s+/g, " ");
}

/** Убрать из списка ингредиентов те, у которых название совпадает с названием блюда (Shama.Book: название в таблице как строка). */
function dropIngredientsMatchingDishName<T extends { productName: string }>(
  ingredients: T[],
  dishName: string | null | undefined,
): T[] {
  if (!dishName || !dishName.trim()) return ingredients;
  const dishNorm = normForDishMatch(dishName);
  if (!dishNorm) return ingredients;
  const ingredientPrefix = /^(сыр|тесто|мука|соус|масло|молоко|яйцо|вода|бульон|паста|крем|пюре|фарш|начинка)\s+/i;
  return ingredients.filter((i) => {
    const p = normForDishMatch(i.productName ?? "");
    if (p === dishNorm) return false;
    if (p.length >= 10 && dishNorm.length >= 10 && (p.includes(dishNorm) || dishNorm.includes(p))) {
      if (ingredientPrefix.test(p)) return true;
      return false;
    }
    return true;
  });
}

const PDF_SYSTEM_PROMPT = `Ты парсер технологических карт (ТТК, рецептов, полуфабрикатов, калькуляционных карт КК ОП-1). На входе — сырой текст из PDF или документа Word (экспорт в текст).

КРИТИЧНО: Если в тексте есть хоть какая-то ТТК (название блюда/ПФ, ингредиенты, технология) — ты ОБЯЗАН извлечь хотя бы одну карточку. Подстраивайся под ЛЮБОЙ формат: Shama.Book, iiko, ГОСТ, КК (форма №ОП-1), Сборник технологических карт (Сборник рецептур), документы Word (кухня, июнь 2012 и т.п.), собственные шаблоны. Не требуй точного соответствия образцу.

Документ может содержать МНОГО карточек подряд (50–200+). Извлекай ВСЕ найденные ТТК — каждая секция "Технологическая карта №" / "1.Рецептура" / "Наименование сырья | Брутто | Нетто" = новая карточка.

Форматы: ГОСТ 31987-2012, СТБ 1210, Сборник: таблица "Наименование сырья" + "Расход сырья на 1 порцию" (г, мл) с колонками Брутто/Нетто; строка "Выход готовой продукции" (г). Варианты по сезону (Свекла до 01.01 / с 01.01) — брать оба или основной.

Структура бывает разной: название в заголовке или отдельной строке; таблица с колонками № / Наименование / Продукт / Сырьё / Брутто / Нетто / Выход / Расход / Норма / Цена / Сумма; числа в граммах или кг (запятая как десятичный разделитель). Для grossGrams/netGrams бери любые подходящие числа (брутто, нетто, норма в кг×1000). Если в таблице есть колонка «Выход» (г) — заполняй outputGrams для каждого ингредиента. Если в документе есть строка «Выход на 1 порцию: X г» или «Выход готовой продукции: X г» — заполняй yieldGrams в карточке (для блюда это вес порции).

ВАЖНО: Если в таблице есть два блока колонок — «Расход на 1 порцию» и «Расход на 10 порций» — используй ТОЛЬКО «на 1 порцию». ingredientType: "product" — сырьё; "semi_finished" — ПФ. isSemiFinished: true если в названии "ПФ".
Яйца: 1,000 шт = 1 piece → unit: "pcs", grossGrams: 1. «Сыр на X», «тесто для X» — ингредиенты, включать ВСЕГДА.

Если есть КК (калькуляционная карта) с ценами — извлекай pricePerKg (цена за кг или за л, руб.) для каждого ингредиента. Это важно для расчёта себестоимости.

Верни ТОЛЬКО валидный JSON, без markdown и обёрток:
{ "cards": [ { "dishName": string, "technologyText": string|null, "isSemiFinished": boolean|null, "yieldGrams": number|null, "ingredients": [ { "productName": string, "grossGrams": number|null, "netGrams": number|null, "outputGrams": number|null, "primaryWastePct": number|null, "cookingMethod": string|null, "cookingLossPct": number|null, "unit": string|null, "ingredientType": "product"|"semi_finished"|null, "pricePerKg": number|null } ] } ] }

Если нет ни одной карточки: { "cards": [] }`;

const KK_MULTI_SYSTEM_PROMPT = `Ты парсер Калькуляционных карт (КК) формы №ОП-1 из PDF (русский язык). Документ может содержать МНОГО КК подряд.

Твоя задача: извлечь ВСЕ карточки (каждое блюдо = отдельная карточка).

Как отделять карточки:
- каждая новая секция с заголовком "Наименование блюда" (или повторяющаяся шапка формы ОП-1) = новая карточка
- часто перед строкой "организация" / "структурное подразделение" стоит название блюда
- внутри карточки таблица ингредиентов: строки вида "1 Т. <продукт> <код> <норма> <цена> <сумма> кг" и т.п.
- конец карточки обычно рядом с "Общая стоимость" / "Выход одного блюда в готовом виде"

Нужно вернуть ТОЛЬКО JSON:
{ "cards": [ { "dishName": string, "technologyText": null, "isSemiFinished": boolean|null, "yieldGrams": number|null, "ingredients": [ { "productName": string, "grossGrams": number|null, "netGrams": number|null, "unit": string|null, "pricePerKg": number|null, "ingredientType": "product"|"semi_finished"|null } ] } ] }

Правила:
- Норма часто в кг с запятой: 0,100 кг → grossGrams/netGrams = 100 (граммы)
- unit: "g" для кг; "ml" для л; "pcs" для шт
- ingredientType: "product" если "Т.", "semi_finished" если "П/Ф"
- Если не уверен в цене, можно оставить pricePerKg null

Если не нашёл карточек: { "cards": [] }`;

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
    const body = (await req.json()) as { pdfBase64?: string; establishmentId?: string; nomenclatureProductNames?: string[] };
    const pdfBase64 = body.pdfBase64;
    const establishmentId = typeof body.establishmentId === "string" ? body.establishmentId.trim() : undefined;
    const nomenclatureProductNames = Array.isArray(body.nomenclatureProductNames) ? body.nomenclatureProductNames.filter((n): n is string => typeof n === "string").slice(0, 500) : [];
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

    const { getDocumentProxy, extractText } = await import("npm:unpdf");
    const { chatText } = await import("../_shared/ai_provider.ts");
    const { pdfMergeContinuationLines, pdfTextToRows, parseTtkByTemplate } = await import("../_shared/parse_ttk_template.ts");
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
    let pageTexts: string[] = [];
    try {
      const pdf = await getDocumentProxy(bytes);
      // mergePages: false — иначе unpdf делает .replace(/\s+/g, ' ') и убивает переносы строк, нужные для таблиц
      const result = await extractText(pdf, { mergePages: false });
      pageTexts = (result?.text as string[] | undefined) ?? [];
      text = pageTexts.join("\n").replace(/\r\n/g, "\n").replace(/\r/g, "\n").trim();
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
    // Для unpdf у нас уже есть страницы: KК почти всегда "1 блюдо = 1 страница".
    // Это надёжнее, чем пытаться резать один склеенный text по маркерам (которых может не быть в unpdf-выводе).
    const kkCardsByPage = (pageTexts.length > 0)
      ? pageTexts.flatMap((p) => parseKkOp1((p ?? "").replace(/\r\n/g, "\n").replace(/\r/g, "\n").trim()))
      : [];
    const kkCards = kkCardsByPage.length > 0 ? kkCardsByPage : parseKkOp1(text);
    const looksLikeManyKkOp1 = (t: string): boolean => {
      const m1 = (t.match(/(?:^|\n)\s*Наименование\s+блюда\s*(?:\n|$)/gim) ?? []).length;
      const m2 = (t.match(/выход\s+одного\s+блюда/gi) ?? []).length;
      const m3 = (t.match(/общая\s+стоимость/gi) ?? []).length;
      // если форма явно повторяется — точно много карточек
      if (m1 >= 2) return true;
      if (m2 >= 2) return true;
      if (m3 >= 2) return true;
      return false;
    };

    // Fallback: если КК-парсер нашёл 1 карточку, но документ похож на "много КК в одном PDF", используем AI для разбиения.
    const shouldUseAiForKk = kkCards.length === 1 && looksLikeManyKkOp1(text);

    if (kkCards.length > 0 && !shouldUseAiForKk) {
      const normalized = kkCards.map((card) => {
        const filtered = filterGarbageIngredients(card.ingredients, (s) => isStructuralProductName(s, true));
        const noDishName = dropIngredientsMatchingDishName(filtered, card.dishName);
        return {
        dishName: card.dishName ?? null,
        technologyText: card.technologyText ?? null,
        isSemiFinished: card.isSemiFinished ?? undefined,
        ingredients: noDishName.map((i) => ({
          productName: i.productName,
          grossGrams: i.grossGrams ?? undefined,
          netGrams: i.netGrams ?? undefined,
          outputGrams: i.outputGrams ?? undefined,
          primaryWastePct: i.primaryWastePct ?? undefined,
          unit: i.unit ?? "g",
          pricePerKg: i.pricePerKg ?? undefined,
          ingredientType: (i as { ingredientType?: string }).ingredientType ?? undefined,
        })),
        };
      });
      return new Response(
        JSON.stringify({ cards: normalized, reason: "kk_op1" }),
        { status: 200, headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" } },
      );
    }

    // 1. Шаблонный парсинг: склеиваем многострочные ячейки PDF, затем в rows
    const mergedText = pdfMergeContinuationLines(text);
    const rows = pdfTextToRows(mergedText);
    let templateCards = rows.length >= 2 ? parseTtkByTemplate(rows) : [];

    // 2. Если встроенный шаблон не сработал — пробуем каталог (сохранённые шаблоны после AI/Excel)
    if (templateCards.length === 0 && rows.length >= 2) {
      const { tryParseByStoredTemplates } = await import("../_shared/try_stored_ttk_templates.ts");
      const stored = await tryParseByStoredTemplates(rows, { fromPdf: true });
      if (stored && stored.cards.length > 0) templateCards = stored.cards;
    }

    // ГОСТ / типовые ТТК: блюдо в канонических блоках — приоритет над парсером по таблице
    const dishMatch = text.match(/Проведено\s+контрольное\s+приготовление\s+блюда\s*:?\s*\n?\s*([^\n]+?)(?:\n|$)/i)
      ?? text.match(/Наименование\s+блюда[^:]*:\s*([^\n]+)/i)
      ?? text.match(/Наименование[^:]*:\s*([^\n]{4,80})/i)
      ?? text.match(/ТК\s+на\s+([^\n,_№]+?)(?:\s*[,№_]|$)/i)
      ?? null;
    const techCardMatches = [...text.matchAll(/Технологическая\s+карта\s+№\s*\d*[^\n]*\n\s*([^\n]{5,80})/gi)];
    const sourceMatches = [...text.matchAll(/Источник\s+рецептуры[^\n]*\n[^\n]*\n\s*([^\n]{5,80})/gi)];
    const extractedDishes: string[] = dishMatch ? [dishMatch[1].trim()] : techCardMatches.map((m) => m[1].trim());
    if (extractedDishes.length === 0 && sourceMatches.length > 0) extractedDishes.push(...sourceMatches.map((m) => m[1].trim()));
    const isValidExtracted = (s: string) => s.length >= 4 && !/^\d+[,.\s]*$/.test(s);
    if (templateCards.length >= 1 && extractedDishes.some(isValidExtracted)) {
      templateCards = templateCards.map((c, i) => {
        const d = extractedDishes[i] ?? extractedDishes[0];
        return (d && isValidExtracted(d)) ? { ...c, dishName: d } : c;
      });
    }
    const isFragmentDish = (s: string) => {
      const t = (s ?? "").trim();
      if (!t || t.includes(" ")) return false;
      if (t.length > 8) return false;
      return /(ов|ей|ий|овь)$/i.test(t);
    };
    templateCards = templateCards.filter((c) => !(c.ingredients.length === 0 && c.dishName && isFragmentDish(c.dishName)));
    const yieldMatch = text.match(/Выход\s+на\s+1\s+порцию\s*:\s*(\d+)\s*г/i);
    const yieldMatchKg = text.match(/Выход\s+в\s+готовом\s+виде\s*:\s*([\d,.\s]+)\s*кг/i);
    let extractedYield = yieldMatch ? parseInt(yieldMatch[1], 10) : undefined;
    if (extractedYield == null && yieldMatchKg) {
      const kgVal = parseFloat(yieldMatchKg[1].replace(/,/g, ".").replace(/\s/g, "").trim());
      if (!Number.isNaN(kgVal) && kgVal > 0) extractedYield = Math.round(kgVal * 1000);
    }
    /** Shama.Book / Хмели-сумели: технология после «Технологический процесс» или «Технология приготовления» — fallback если парсер не захватил */
    const extractedTechFromText = (() => {
      let m = text.match(
        /Технологический\s+процесс[\s\S]*?(?:\n|\r\n?)([\s\S]*?)(?=\n\s*Допустимые\s+сроки|\n\s*Информация\s+о\s+пищевой|$)/i,
      );
      if (!m || !m[1]) {
        m = text.match(
          /Технология\s+приготовления[\s\S]*?(?:\n|\r\n?)([\s\S]*?)(?=\n\s*Директор|\n\s*Шеф-повар|\s+Директор\b|\s+Шеф-повар\b|Дата\s+печати|$)/i,
        );
      }
      if (!m || !m[1]) return "";
      let t = m[1].trim().replace(/\r\n/g, "\n");
      const lines = t.split(/\n/).map((l) => l.trim()).filter(Boolean);
      const skipHeader = /^условия\s+и\s+сроки|^изготовления|^оформления\s+и\s+подачи/i;
      const footerLine = /^директор$|^шеф-повар$|^калькулятор$|^дата\s+печати|^-1-$|^-\d+-$/i;
      const filtered = lines.filter((l) => !skipHeader.test(l) && !footerLine.test(l) && l.length > 2);
      while (filtered.length > 0 && (filtered[0].length < 20 || /^(директор|шеф|калькулятор|дата)/i.test(filtered[0]))) filtered.shift();
      t = filtered.join(" ").replace(/\s+/g, " ");
      if (t.length < 30 || /^(кдж|ккал|белки|жиры|углеводы)/i.test(t)) return "";
      return t;
    })();
    // Шаблон дал карточки с ингредиентами — возвращаем. Если все карточки без ингредиентов — пробуем AI.
    const templateHasIngredients = templateCards.some((c) => (c.ingredients?.length ?? 0) > 0);
    if (templateCards.length > 0 && templateHasIngredients) {
      // Обогащение технологии из обучения: даже когда шаблон сработал, подставляем выученную колонку (чтобы правки пользователя давали эффект)
      let learnedTechText = "";
      try {
        const KEYWORDS = ["наименование", "продукт", "брутто", "нетто", "название", "сырьё", "ингредиент", "расход сырья"];
        let firstSig: string | null = null;
        for (let r = 0; r < rows.length && r < 100; r++) {
          const row = rows[r]?.map((c) => (c ?? "").trim().toLowerCase()) ?? [];
          if (row.length < 2) continue;
          if (!row.some((c) => KEYWORDS.some((k) => c.includes(k)))) continue;
          const headerRow = rows[r]?.map((c) => (c ?? "").trim()) ?? [];
          firstSig = headerSignature(headerRow);
          if (firstSig) break;
        }
        if (firstSig) {
          const { createClient } = await import("https://esm.sh/@supabase/supabase-js@2");
          const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
          const { data: learned } = await supabase.from("tt_parse_learned_dish_name").select("technology_col").eq("header_signature", firstSig).limit(1).maybeSingle();
          const techCol = learned?.technology_col as number | undefined;
          if (typeof techCol === "number" && techCol >= 0) {
            learnedTechText = getTechnologyFromRowsUsingColumn(rows, techCol, 1);
          }
        }
      } catch (_) {
        /* ignore */
      }

      // Шаблон или каталог сработал — AI не используется, лимит не применяется
      const normalized = templateCards.map((card, idx) => {
        const filtered = filterGarbageIngredients(card.ingredients, (s) => isStructuralProductName(s, true));
        const noDishName = dropIngredientsMatchingDishName(filtered, card.dishName);
        let ingredients = noDishName.map((i) => ({
          productName: i.productName,
          grossGrams: i.grossGrams ?? undefined,
          netGrams: i.netGrams ?? undefined,
          outputGrams: i.outputGrams ?? undefined,
          primaryWastePct: i.primaryWastePct ?? undefined,
          unit: i.unit ?? "g",
          cookingMethod: undefined,
          cookingLossPct: undefined,
          ingredientType: undefined,
        }));
        // Shama: если в тексте явно «Выход на 1 порцию: 25 г» — использовать для единственного ингредиента (приоритет над колонкой таблицы)
        if (extractedYield != null && extractedYield > 0 && ingredients.length === 1) {
          ingredients = [{ ...ingredients[0], outputGrams: extractedYield }];
        }
        const useLearnedTech = learnedTechText.length > 0 && (idx === 0 || !(card.technologyText ?? "").trim()) && learnedTechText.length >= (card.technologyText ?? "").length;
        let tech = useLearnedTech ? learnedTechText : (card.technologyText ?? null);
        if ((!tech || tech.trim().length < 30) && extractedTechFromText.length > 30) tech = extractedTechFromText;
        return {
        dishName: card.dishName ?? null,
        technologyText: tech,
        isSemiFinished: card.isSemiFinished ?? undefined,
        yieldGrams: extractedYield ?? card.yieldGrams ?? undefined,
        ingredients,
        };
      });
      // Возвращаем rows для обучения на клиенте (learnDishNamePosition, дообучение)
      const payload: Record<string, unknown> = { cards: normalized, reason: "template" };
      if (rows.length >= 2) payload.rows = rows;
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
        const payload: Record<string, unknown> = { cards: [], reason: "ai_limit_exceeded", error: "limit_3_per_day" };
        if (rows.length >= 2) payload.rows = rows;
        return new Response(JSON.stringify(payload), {
          status: 200, headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" } },
        );
      }
    }

    const nomenclatureHint = nomenclatureProductNames.length > 0
      ? `\n\nНоменклатура заведения (подсказка при маппинге — предпочитать эти названия, если документ явно ссылается на тот же продукт; НЕ заменять произвольно): ${nomenclatureProductNames.slice(0, 200).join(", ")}`
      : "";
    const textForAi = text.replace(/\s+/g, " ").trim();
    let content: string;
    try {
      content = await chatText({
        messages: [
          { role: "system", content: (shouldUseAiForKk ? KK_MULTI_SYSTEM_PROMPT : PDF_SYSTEM_PROMPT) + nomenclatureHint },
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

    // Возвращаем rows всегда — чтобы клиент мог сохранить шаблон и выйти на «Проверку импорта» с placeholder для обучения
    const rowsForLearning = rows.length >= 2 ? rows : undefined;

    // Выход на 1 порцию из текста (для AI-пути; для шаблона уже учтён выше)
    const yieldMatchAi = text.match(/Выход\s+на\s+1\s+порцию\s*:\s*(\d+)\s*г/i);
    const yieldMatchKgAi = text.match(/Выход\s+в\s+готовом\s+виде\s*:\s*([\d,.\s]+)\s*кг/i);
    let extractedYieldAi = yieldMatchAi ? parseInt(yieldMatchAi[1], 10) : undefined;
    if (extractedYieldAi == null && yieldMatchKgAi) {
      const kgVal = parseFloat(yieldMatchKgAi[1].replace(/,/g, ".").replace(/\s/g, "").trim());
      if (!Number.isNaN(kgVal) && kgVal > 0) extractedYieldAi = Math.round(kgVal * 1000);
    }

    const normalized = cards.map((card) => {
      const c = card as Record<string, unknown>;
      const dishName = c.dishName != null ? String(c.dishName) : null;
      const rawIngredients = Array.isArray(c.ingredients)
        ? (c.ingredients as Record<string, unknown>[]).map((i) => {
            const it = String(i.ingredientType ?? "").toLowerCase();
            const ingredientType = (it === "product" || it === "semi_finished") ? it : undefined;
            return {
              productName: String(i.productName ?? ""),
              grossGrams: i.grossGrams != null ? Number(i.grossGrams) : undefined,
              netGrams: i.netGrams != null ? Number(i.netGrams) : undefined,
              outputGrams: i.outputGrams != null ? Number(i.outputGrams) : undefined,
              unit: i.unit != null ? String(i.unit) : undefined,
              cookingMethod: i.cookingMethod != null ? String(i.cookingMethod) : undefined,
              primaryWastePct: i.primaryWastePct != null ? Number(i.primaryWastePct) : undefined,
              cookingLossPct: i.cookingLossPct != null ? Number(i.cookingLossPct) : undefined,
              ingredientType,
              pricePerKg: i.pricePerKg != null ? Number(i.pricePerKg) : undefined,
            };
          })
        : [];
      const filtered = filterGarbageIngredients(rawIngredients, (s) => isStructuralProductName(s, true));
      let ingredients = dropIngredientsMatchingDishName(filtered, dishName);
      if (extractedYieldAi != null && extractedYieldAi > 0 && ingredients.length === 1 && (ingredients[0].outputGrams == null || ingredients[0].outputGrams === 0)) {
        ingredients = [{ ...ingredients[0], outputGrams: extractedYieldAi }];
      }
      return {
        dishName,
        technologyText: c.technologyText != null ? String(c.technologyText) : null,
        ingredients,
        isSemiFinished: typeof c.isSemiFinished === "boolean" ? c.isSemiFinished : undefined,
        yieldGrams: extractedYieldAi ?? (c.yieldGrams != null ? Number(c.yieldGrams) : undefined),
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
