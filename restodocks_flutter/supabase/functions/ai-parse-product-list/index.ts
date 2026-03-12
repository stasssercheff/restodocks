// Supabase Edge Function: всеядный парсинг списка продуктов из строк (файл или текст)
// ИИ самостоятельно определяет колонки: Название, Цена, Ед. изм. по смыслу содержимого
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { chatText } from "../_shared/ai_provider.ts";

function corsHeaders(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin || "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
}

// Промпт для режима инвентаризационного бланка
const INVENTORY_SYSTEM_PROMPT = `Ты — парсер инвентаризационного бланка. СТРОГО соблюдай правила.

ЗАДАЧА: из каждой строки извлечь название товара ДОСЛОВНО как в бланке — без изменений, без исправлений, без переименований.

ПРАВИЛА ОЧИСТКИ СТРОКИ:
1. Убери технический префикс в начале: «Т.», «Т. », «Т.  », «ТМЦ» — и всё что до первой буквы названия.
2. Числа (коды товаров, количество, остатки, цены) — НЕ включай в name, но если это цена — запиши в price.
3. Единица измерения в конце строки («кг», «г», «л», «мл», «шт», «уп») — запиши в unit, убери из name.
4. ВСЁ ОСТАЛЬНОЕ НАЗВАНИЕ — сохраняй ДОСЛОВНО, не переименовывай, не исправляй, не переводи.

ПРОПУСКАЙ строки:
- Заголовки таблицы: «Наименование», «Код», «Ед. изм.», «Остаток фактический», «Группа», «Товар»
- Метаданные: «Организация:», «На дату:», «Склад», «Бланк инвентаризации»
- Пустые строки

ВКЛЮЧАЙ все товарные строки, даже если они похожи на категории — пользователь сам разберётся.

ПРИМЕРЫ:
- «Т.  Пенообразователь Bubble drops» → {"name": "Пенообразователь Bubble drops", "unit": "l", "price": null, "currency": null}
- «Т. Абсент Грин Зомби/Фея (хаус)» → {"name": "Абсент Грин Зомби/Фея (хаус)", "unit": "l", "price": null, "currency": null}
- «Т. Мартини Бьянко вермут» → {"name": "Мартини Бьянко вермут", "unit": "l", "price": null, "currency": null}
- «Т. Вино белое «Пэй д'Ок. Домен Прень ле Вьё. Совиньон» → {"name": "Вино белое «Пэй д'Ок. Домен Прень ле Вьё. Совиньон", "unit": "l", "price": null, "currency": null}
- «Т. Апельсин чипсы» → {"name": "Апельсин чипсы", "unit": "kg", "price": null, "currency": null}

OUTPUT: JSON array of objects:
- name (string, required): название ДОСЛОВНО из бланка, только без префикса «Т.» и единиц измерения
- price (number|null): цена если явно указана в строке, иначе null
- unit (string|null): «g», «kg», «ml», «l», «pcs» или аналог — если есть в строке
- currency (string|null): валюта если есть в строке, иначе null

Return ONLY valid JSON array, no markdown, no extra text. Max 500 items.`;

const SYSTEM_PROMPT = `Ты — парсер списка продуктов для ресторана. ОБЯЗАТЕЛЬНО выполняй ВСЕ пункты.

ИСТОЧНИКИ (принимай любые): RTF, XLS, XLSX, DOC, DOCX, TXT, CSV — у разных пользователей разная структура.

ФОРМАТЫ И СТРУКТУРА — определяй по контексту (может быть что угодно):
- Одна строка: "Название Цена" или "Название\\tЦена" — извлечь оба
- Таблица: несколько колонок — определи, где название, где цена. Остальное (№, поставщик, дата и т.д.) — игнорируй
- Чередование строк: строка 1 — название, строка 2 — цена, и т.д. — связывай пары по порядку
- Любые варианты: нумерация, доп. поля — ГЛАВНОЕ: найти название продукта и цену, привязанную к нему. Цена относится к ближайшему названию выше/рядом
- Никогда не возвращай строку с ценой без названия продукта. Голое число — это цена, не название

КРИТИЧЕСКИ ВАЖНО — ИСПРАВЛЕНИЕ ОПЕЧАТОК:
- Прогоняй каждое название через проверку. Исправляй ВСЕ опечатки
- Примеры: "Авокало"->"Авокадо", "Анчоусм"->"Анчоусы", "АпельсмН"->"Апельсин", "картофан"->"Картофель", "морков"->"Морковь"
- Используй стандартную кулинарную терминологию. Нет названий с опечатками в результате

OUTPUT: JSON array of objects, each with:
- name (string, required): product name, cleaned and normalized, typos fixed
- price (number|null): price per kg or unit if detectable
- unit (string|null): "g", "kg", "ml", "l", "pcs", "portion" or similar
- currency (string|null): "RUB", "USD", "EUR", "KZT", "UAH", "BYN", etc. — infer from "50р", "120 руб", "$10", "10€", "10 EUR"

RULES:
- Infer columns by content meaning. Product names can be in any column. Extra columns (numbering, supplier, etc.) — ignore
- If lines alternate: text line (product name) then number line (price) — pair them. Price belongs to the product above
- Extract and normalize product names: fix ALL typos (grammatical and semantic)
- Fix typos: "картофан" -> "Картофель", "помидор" -> "Томат", "лук" -> "Лук репчатый", "Авокало" -> "Авокадо", "Анчоусм" -> "Анчоусы", "АпельсмН" -> "Апельсин"
- Используй стандартную кулинарную терминологию. Результат — без опечаток
- Цены: "50р", "50 руб", "50.5", "50,5", "110000", "1 360 000"
- Валюта: определяй из текста (р/руб/₽→RUB, $/usd→USD, €/eur→EUR, тг/тенге→KZT, грн→UAH, бел.руб→BYN). Если в строке нет валюты — используй defaultCurrency из запроса
- Recognize units: кг, г, шт, л, мл, порция, упаковка
- Handle comma as decimal separator (50,5 = 50.5) and dots (50.5 = 50.5)
- Handle spaces in numbers (1 000 = 1000)
- Skip rows without product names (headers, totals, empty rows)
- Никогда не используй голое число (110000, 4302) как name — это цена. Ищи название продукта в контексте строки
- Return ONLY valid JSON array, no markdown, no extra text.
- Max 500 items. If more rows, take first 500.

EXAMPLES:
- "Картофель 45р кг" -> {"name": "Картофель", "price": 45, "unit": "kg", "currency": "RUB"}
- "Лук репчатый;120;шт" -> {"name": "Лук репчатый", "price": 120, "unit": "pcs", "currency": "RUB"}
- "Помидоры черри 250 руб/кг" -> {"name": "Томат черри", "price": 250, "unit": "kg", "currency": "RUB"}
- "Avocado $5.99" -> {"name": "Авокадо", "price": 5.99, "unit": "pcs", "currency": "USD"}
- "Milk 2.50 EUR/l" -> {"name": "Молоко", "price": 2.5, "unit": "l", "currency": "EUR"}`;

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

  const hasProvider =
    Deno.env.get("GROQ_API_KEY")?.trim() ||
    Deno.env.get("GEMINI_API_KEY")?.trim() ||
    Deno.env.get("GIGACHAT_AUTH_KEY")?.trim() ||
    Deno.env.get("OPENAI_API_KEY");
  if (!hasProvider) {
    return new Response(
      JSON.stringify({ error: "GROQ_API_KEY, GEMINI_API_KEY, GIGACHAT_AUTH_KEY or OPENAI_API_KEY required" }),
      {
        status: 500,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      },
    );
  }

  try {
    const body = (await req.json()) as {
      rows?: string[];
      text?: string;
      source?: string;
      hintCurrency?: string;
      userLocale?: string;
      mode?: string;
    };
    let rows: string[] = [];
    const source = typeof body.source === "string" ? body.source : "";
    const isInventoryMode = typeof body.mode === "string" && body.mode.trim().toLowerCase() === "inventory";
    let defaultCurrency = typeof body.hintCurrency === "string" && body.hintCurrency.trim()
      ? body.hintCurrency.trim().toUpperCase()
      : null;
    if (!defaultCurrency && typeof body.userLocale === "string" && body.userLocale.trim()) {
      const locale = body.userLocale.trim().toLowerCase();
      if (locale.startsWith("ru")) defaultCurrency = "RUB";
      else if (locale.startsWith("en_us") || locale === "en") defaultCurrency = "USD";
      else if (locale.startsWith("de")) defaultCurrency = "EUR";
      else if (locale.startsWith("fr") || locale.startsWith("es") || locale.startsWith("it")) defaultCurrency = "EUR";
      else if (locale.startsWith("kk")) defaultCurrency = "KZT";
      else if (locale.startsWith("uk")) defaultCurrency = "UAH";
      else if (locale.startsWith("be")) defaultCurrency = "BYN";
    }
    if (!defaultCurrency) {
      try {
        const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
          req.headers.get("x-real-ip") || req.headers.get("cf-connecting-ip");
        if (ip) {
          const geo = await fetch(`https://ipapi.co/${ip}/json/`).then((r) => r.json()) as { country_code?: string; error?: boolean };
          const cc = !geo.error && geo.country_code ? geo.country_code.toUpperCase() : null;
          if (cc === "RU") defaultCurrency = "RUB";
          else if (cc === "US" || cc === "CA") defaultCurrency = "USD";
          else if (["DE", "FR", "ES", "IT", "NL", "BE", "AT"].includes(cc || "")) defaultCurrency = "EUR";
          else if (cc === "KZ") defaultCurrency = "KZT";
          else if (cc === "UA") defaultCurrency = "UAH";
          else if (cc === "BY") defaultCurrency = "BYN";
        }
      } catch {
        // ignore geo errors
      }
    }
    if (!defaultCurrency) defaultCurrency = "RUB"; // fallback

    if (Array.isArray(body.rows) && body.rows.length > 0) {
      rows = body.rows
        .map((r) => (typeof r === "string" ? r : String(r ?? "")).trim())
        .filter((r) => r.length > 0);
    } else if (typeof body.text === "string" && body.text.trim()) {
      rows = body.text
        .split(/\r?\n/)
        .map((r) => r.trim())
        .filter((r) => r.length > 0);
      if (rows.length === 0) rows = [body.text.trim()];
    }

    if (rows.length === 0) {
      return new Response(JSON.stringify({ items: [] }), {
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    const sourceHint = source ? `\n\nИсточник: ${source}. Обработай соответственно.` : "";
    const currencyHint = `\n\ndefaultCurrency (если в строке нет валюты): ${defaultCurrency}`;
    const toSend = rows.slice(0, 500);

    const activeSystemPrompt = isInventoryMode ? INVENTORY_SYSTEM_PROMPT : SYSTEM_PROMPT;
    const userContent = isInventoryMode
      ? `Извлеки названия товаров из строк инвентаризационного бланка. Убери только префикс «Т.» и цифры. Названия сохраняй ДОСЛОВНО — не переименовывай, не исправляй.${currencyHint}\n\nСтрок: ${toSend.length}\n\n${toSend.map((r, i) => `${i + 1}. ${r}`).join("\n")}`
      : `Распарси в список продуктов. Обязательно исправь ВСЕ опечатки в названиях. Определи валюту по тексту или используй defaultCurrency.${sourceHint}${currencyHint}\n\nСтрок: ${toSend.length}\n\n${toSend.map((r, i) => `${i + 1}. ${r}`).join("\n")}`;

    const content = await chatText({
      messages: [
        { role: "system", content: activeSystemPrompt },
        { role: "user", content: userContent },
      ],
      temperature: 0.2,
      maxTokens: 8192,
      context: "product",
    });

    if (!content?.trim()) {
      return new Response(JSON.stringify({ items: [], error: "Empty AI response" }), {
        status: 200,
        headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
      });
    }

    let jsonStr = content.trim();
    const codeBlock = jsonStr.match(/```(?:json)?\s*([\s\S]*?)```/);
    if (codeBlock) jsonStr = codeBlock[1].trim();

    const parsed = JSON.parse(jsonStr);
    const arr = Array.isArray(parsed) ? parsed : parsed.items ?? parsed.data ?? [];
    const items = arr
      .filter((o: unknown) => o && typeof o === "object")
      .map((o: Record<string, unknown>) => {
        const curr = typeof o.currency === "string" && o.currency.trim()
          ? o.currency.trim().toUpperCase()
          : defaultCurrency;
        return {
          name: typeof o.name === "string" ? o.name.trim() : String(o.name ?? "").trim(),
          price: typeof o.price === "number" && !Number.isNaN(o.price) ? o.price : (o.price != null ? Number(o.price) : null),
          unit: typeof o.unit === "string" && o.unit.trim() ? o.unit.trim() : null,
          currency: curr,
        };
      })
      .filter((o: { name: string }) => o.name.length > 0);

    return new Response(JSON.stringify({ items, defaultCurrency }), {
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e), items: [] }), {
      status: 500,
      headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  }
});
